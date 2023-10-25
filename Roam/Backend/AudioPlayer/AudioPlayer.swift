import AVFoundation
import RTP
import os
import Opus
import CoreAudio


struct AudioFrame {
    let frame: AVAudioPCMBuffer
    let scheduleAt: AVAudioFramePosition
}

actor OpusDecoderWithJitterBuffer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: OpusDecoderWithJitterBuffer.self)
    )
    
    var jitterBuffer = MaxHeap<RtpPacket>()
    let opusDecoder: Opus.RoamDecoder
    var packetsPerSec: Int64 {
        1000 / PACKET_SIZE_MS
    }
    var lastPacketNumber: Int64 = 0
    var syncPacket: RtpPacket? = nil
    var lastSampleTime: AVAudioTime? = nil
    let audioBuffer: TimeInterval
    
    init(audioBuffer: TimeInterval) throws {
        guard let opusFormat = AVAudioFormat(opusPCMFormat: .float32, sampleRate: Double(CLOCK_RATE), channels: 2) else {
            fatalError("Error initializing opus av format. This is a bug")
        }
        do {
            opusDecoder = try Opus.RoamDecoder(format: opusFormat)
        } catch {
            Self.logger.error("Error initializing opus decoder \(error)")
            throw error
        }
        self.audioBuffer = audioBuffer
    }
        
    func syncAudio(time: AVAudioTime, additionalAudioDelay: TimeInterval) -> Bool {
        guard let syncPacket = syncPacket else {
            Self.logger.info("Not synced packet yet. Can't sync audio yet")
            return false
        }
        Self.logger.info("Syncing time with additional audio delay \(additionalAudioDelay) buffer \(self.audioBuffer)")
        
        let packetsSubtracted = Int64(audioBuffer * Double(packetsPerSec))
        
        // Estimating getting 100 packets per second
        let currentEstimatedPacketNumber = Int64((machTimeToSeconds(time.hostTime) - machTimeToSeconds(syncPacket.receivedAt)) * Double(packetsPerSec)) + Int64(syncPacket.sequenceNumber)
        lastPacketNumber = (currentEstimatedPacketNumber - packetsSubtracted + Int64(UInt16.max)) % Int64(UInt16.max)
        lastSampleTime = AVAudioTime(hostTime: time.hostTime + secondsToMachTime(additionalAudioDelay), sampleTime: time.sampleTime + Int64(time.sampleRate * additionalAudioDelay), atRate: time.sampleRate)
        
        return true
    }

    func addPacket(packet: RtpPacket) {
        if syncPacket == nil {
            syncPacket = packet
        }
        
        // Check payload type
        if packet.payloadType != PayloadType(97) || packet.ssrc != 0 {
            // Invalid payload
            Self.logger.error("Error bad packet ssrc (\(packet.ssrc) or payload type (\(packet.payloadType.rawValue))")
        }
        if lastPacketNumber < packet.sequenceNumber {
//            Self.logger.trace("Adding packet with seqNo \(packet.packet.sequenceNumber) when current seqNo is \(self.lastPacketNumber)")
            self.jitterBuffer.insert(packet)
        } else {
            Self.logger.error("Error bad packet with seqNo \(packet.unwrappedSequenceNumber) when current seqNo is \(self.lastPacketNumber)")
        }
    }
    
    func nextPacket(atTime: AVAudioTime) -> (AVAudioPCMBuffer, AVAudioTime)? {
        guard let lastSampleTime = lastSampleTime else {
            Self.logger.info("Not returning packet because not synced yet")
            return nil
        }
        
        // No need to worry about wrapping because we get several years of stream before we wrap
        var nextPacket: RtpPacket? = nil
        while true {
            if let np = jitterBuffer.peek(),
                np.sequenceNumber <= lastPacketNumber + 1 {
                if let destroyed = nextPacket {
                    Self.logger.error("Destroying packet \(destroyed.sequenceNumber) when lastPacket \(self.lastPacketNumber) next paacket \(np.sequenceNumber)")
                }
                nextPacket = jitterBuffer.remove()
            } else {
                break
            }
        }
        
        if nextPacket == nil {
            Self.logger.error("Missing packet \(String(describing: self.jitterBuffer.peek())), lpn \(self.lastPacketNumber)")
        }
                
        // Need to get schedule time for when to schedule the packet
        let sampleTime = AVAudioTime(hostTime: secondsToMachTime(0.01) + lastSampleTime.hostTime, sampleTime: lastSampleTime.sampleTime + Int64(lastSampleTime.sampleRate) / packetsPerSec, atRate: lastSampleTime.sampleRate)
        
        self.lastSampleTime = sampleTime
        self.lastPacketNumber = lastPacketNumber + 1

        let nextPcm: AVAudioPCMBuffer
        do {
            if let np = nextPacket {
                nextPcm = try opusDecoder.decode(np.payload)
//                Self.logger.info("Getting decoded packet \(nextPcm.frameLength) \(nextPcm)")
            } else {
                nextPcm = try opusDecoder.decode_loss_concealment(sampleCount: Int64(CLOCK_RATE) / packetsPerSec)
                Self.logger.error("Getting loss concealment packet for sqNo \(self.lastPacketNumber)")
            }
        } catch {
            Self.logger.error("Error decoding packet \(error)")
            return nil
        }
        
        guard sampleTime.isSampleTimeValid else {
            return nil
        }
        
        return (nextPcm, sampleTime)
    }
}

actor AudioPlayer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AudioPlayer.self)
    )
    
    private let engine: AVAudioEngine
    private let streamAudioNode: AVAudioPlayerNode
    private let convertor: AVAudioConverter

    public init () {
        engine = AVAudioEngine()
        streamAudioNode = AVAudioPlayerNode()
        engine.attach(streamAudioNode)
        let audioFormat = AVAudioFormat(opusPCMFormat: .float32, sampleRate: 48000, channels: 2)!
        engine.connect(streamAudioNode, to: engine.mainMixerNode, format: nil)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        convertor = AVAudioConverter(from: audioFormat, to: engine.mainMixerNode.outputFormat(forBus: 0))!
    }

    public func start() throws {
        try engine.start()
        streamAudioNode.play()
    }
    
    
    #if os(macOS)
    func getOutputLatency() -> TimeInterval {
        self.engine.outputNode.presentationLatency
    }
    #else
    func getOutputLatency() -> TimeInterval {
        return AVAudioSession.sharedInstance().outputLatency
    }
    #endif

    public func scheduleAudioBytes(buffer: AVAudioPCMBuffer, atTime: AVAudioTime) async {
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: convertor.outputFormat, frameCapacity: AVAudioFrameCount(convertor.outputFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate))!
        var error: NSError? = nil
        self.convertor.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            Self.logger.error("Error converting buffers \(error)")
        } else {
            await streamAudioNode.scheduleBuffer(outputBuffer, at: atTime)
        }
        
    }
    
    public func lastRender() -> AVAudioTime? {
        if let lrt = self.streamAudioNode.lastRenderTime {
            return self.streamAudioNode.playerTime(forNodeTime: lrt)
        }
        return nil
    }

    public func stop() {
        Self.logger.info("Stopping audioplayer")
        engine.stop()
        streamAudioNode.stop()
    }
}

func machTimeToSeconds(_ machTime: UInt64) -> Double {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds = Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
    let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
    return machTimeInSeconds
}

func secondsToMachTime(_ seconds: Double) -> UInt64 {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds = seconds * 1_000_000_000.0
    let machTime = UInt64(machTimeInNanoseconds) * UInt64(timebaseInfo.denom) / UInt64(timebaseInfo.numer)
    return machTime
}

extension AVAudioTime {
    func offsetFromNow() -> TimeInterval {
        let timeNow = mach_absolute_time()
        let machTime = Int64(hostTime) - Int64(timeNow)
        
        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)
        let machTimeInNanoseconds = Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
        return machTimeInSeconds
    }
}
