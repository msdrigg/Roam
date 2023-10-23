import AVFoundation
import RTP
import os
import Opus


class OpusDecoderWithJitterBuffer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: OpusDecoderWithJitterBuffer.self)
    )
    
    // RTPPacket
    typealias InboundIn = Packet
    typealias InboundOut = AVAudioPCMBuffer
    
    var jitterBuffer = BinaryHeap<Packet> { (a: Packet, b: Packet) in
        return a.sequenceNumber < b.sequenceNumber
    }
    var lastPacketTs: UInt32?
    let opusDecoder: Opus.Decoder
    // Delay (in realtime) 
    let bufferDelay: TimeInterval
    
    init?(bufferDelay: TimeInterval) {
        guard let opusFormat = AVAudioFormat(opusPCMFormat: .float32, sampleRate: 48000, channels: 2) else {
            Self.logger.error("Error initializing opus av format. This is a bug")
            return nil
        }
        do {
            opusDecoder = try Opus.Decoder(format: opusFormat)
        } catch {
            Self.logger.error("Error initializing opus decoder \(error)")
            return nil
        }
        self.bufferDelay = bufferDelay
    }
    
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        let packet = self.unwrapInboundIn(data)
//        
//        // Check payload type
//        if packet.payloadType != PayloadType(97) || packet.ssrc != 0 {
//            // Invalid
//            Self.logger.error("Error bad packet ssrc (\(packet.ssrc) or payload type (\(packet.payloadType.rawValue))")
//        } else {
//            self.jitterBuffer.insert(packet)
//        }
//        guard let maybeNext = self.maybeNext() else {
//            return
//        }
//        
//        do {
//            let decoded = try opusDecoder.decode(packet.payload)
//        } catch {
//            Self.logger.error("Error decoding packet payload with seqNo \(packet.sequenceNumber) and payload \(packet.payload.map{ String(format: "%02x", $0) }.joined())")
//        }
//    }
    
    func maybeNext() -> AVAudioPCMBuffer? {
        while true {
            guard let nextPacket = self.jitterBuffer.peek() else {
                return nil
            }
            
            Self.logger.trace("Checking packet \(nextPacket.sequenceNumber), \(nextPacket.timestamp)")
            let lastPacketTs = self.lastPacketTs ?? UInt32.max
            if lastPacketTs <= nextPacket.timestamp {
                Self.logger.trace("Dropping packet with ts \(nextPacket.timestamp) because it is before self ts by \(lastPacketTs - nextPacket.timestamp)")
                let _ = jitterBuffer.pop()
                continue
            }
            let packetTs = nextPacket.timestamp
        }
    }
}

// // Need to rework whole thing following this impl https://github.com/alin23/roku-audio-receiver/blob/2b42d832ea1de14638197392a2b29a09adc7de90/roku.py#L540
//actor AudioPlayer {
//    private let engine: AVAudioEngine
//    private let streamAudioNode: AVAudioPlayerNode
//
//    public init () {
//        engine = AVAudioEngine()
//        streamAudioNode = AVAudioPlayerNode()
//        engine.attach(streamAudioNode)
//        engine.connect(streamAudioNode, to: engine.outputNode, format: nil)
//    }
//
//    public func start() {
//        try! engine.start()
//        streamAudioNode.play()
//    }
//
//    public func scheduleAudioBytes(buffer: AVAudioPCMBuffer) async {
//        await streamAudioNode.scheduleBuffer(buffer)
//
//
//    }
//
//    public func stop() {
//        engine.stop()
//        streamAudioNode.stop()
//    }
//}
//
//enum RPError: Error {
//    case BadAudioFormat
//}
//
//public func connectAndPlay(rokuIp: String, testUrl: URL) async throws {
//    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
//    defer {
//        try! group.syncShutdownGracefully()
//    }
//
//    let udpBootstrap = DatagramBootstrap(group: group)
//        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
//
//    // 1. RTP-UDP packet forwarder
//    let udpChannel = try await udpBootstrap.bind(host: "0.0.0.0", port: 38948).get()
//    let udpHandler = RTPForwarder(destination: "127.0.0.1", port: 36148)
//    try await udpChannel.pipeline.addHandler(udpHandler).get()
//
//    // 2. VLCKit media player
//    let mediaPlayer = VLCMediaPlayer()
//    mediaPlayer.media = VLCMedia(url: testUrl)
//    mediaPlayer.play()
//
//    // Flag for starting RTCP connection
//    var startRTCP = false
//
//    // Wait for the first RTP packet to arrive
//    await udpHandler.firstPacketReceived.futureResult.whenComplete { _ in
//
//    }
//
//    // 3. Initiate RTCP connection if RTP packet is received
//    if startRTCP {
//        // Your RTCP initiation code here
//    }
//
//    // 4. Create WebSocket connection
//    let webSocket = try WebSocket.connect(to: "ws://\(rokuIp):8060/ecp-session", on: group.next()).wait()
//
//    // Cleanup
//    // Stop UDP forwarding, VLC Media player, and close WebSocket
//    udpChannel.close(promise: nil)
//    mediaPlayer.stop()
//    try webSocket.close().wait()
//}
//
//
//
//
//struct RTPPacket {
//    let payloadType: UInt8
//    let seqNo: UInt16
//    // RTP Units
//    let timestamp: RTPTimestamp
//    // RTP Units
//    let receivedAt: RTPTimestamp
//    let ssrc: UInt32
//
//    init?(buffer: ByteBuffer) {
//        guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: 12) else {
//            return nil
//        }
//
//        let version = (bytes[0] & 0xC0) >> 6
//        if version != 2 {
//            return nil
//        }
//
//        payloadType = bytes[1] & 0x7F
//        if payloadType != VALID_PAYLOAD_TYPE {
//            return nil
//        }
//
//        seqNo = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
//        timestamp = RTPTimestamp(data: Data(bytes[4..<8]))!
//        ssrc =  UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])
//    }
//}
//
//// https://www.freesoft.org/CIE/RFC/1889/19.htm
//class SourceInfo {
//    var ssrc: UInt32
//
//    var lsrReceivedAt: RTPTimestamp? = nil
//    var lsr: RTPTimestamp? = nil
//
//    var jitter: RTPTimeInterval = RTPTimeInterval(seconds: 0.0)
//    var lastTransitTime: RTPTimeInterval = RTPTimeInterval(seconds: 0.0)
//
//    var activeSender: Bool = false
//    var packetsReceived: UInt32 = 0
//
//    var expectedPrior: UInt32 = 0
//    var receivedPrior: UInt32 = 0
//
//    var maxSeq: UInt16?
//    var baseSeq: UInt16?
//    var cycles: UInt32 = 0
//    var extendedMax: UInt32 {
//        cycles + UInt32(maxSeq ?? 0)
//    }
//    var packetsExpected: UInt32 {
//        extendedMax - UInt32(baseSeq ?? 0) + 1
//    }
//    var packetsLostInterval: UInt32 {
//        packetsExpectedInterval - packetsReceivedInterval
//    }
//    var packetsExpectedInterval: UInt32 {
//        packetsExpected - expectedPrior
//    }
//    var packetsReceivedInterval: UInt32 {
//        packetsReceived - receivedPrior
//    }
//
//    init(ssrc: UInt32) {
//        self.ssrc = ssrc
//    }
//
//    func recordPacket(packet: RTPPacket, atTime: RTPTimestamp) {
//        activeSender = true
//
//        if let lastSeqMax = self.maxSeq {
//            let (trueMax, wrapped) = greatestConsideringMax(lastMax: lastSeqMax, seqNo: packet.seqNo)
//            if wrapped {
//                cycles += UInt32(UInt16.max)
//            }
//            self.maxSeq = trueMax
//        } else {
//            self.maxSeq = packet.seqNo
//            self.baseSeq = packet.seqNo
//        }
//
//        let transit = atTime.seconds - packet.timestamp.seconds
//        let jitterUpdate = abs(transit - lastTransitTime.seconds)
//        lastTransitTime = RTPTimeInterval(seconds: transit)
//        let newJitterSecs = jitter.seconds + (jitterUpdate - jitter.seconds) / 16.0
//        jitter = RTPTimeInterval(seconds: newJitterSecs)
//    }
//
//    func recordSenderReport(report: SenderReport, receivedAt: RTPTimestamp) {
//        self.lsr = report.timestamp
//        self.lsrReceivedAt = receivedAt
//    }
//
//    func disableSource() {
//        self.activeSender = false
//    }
//
//    func generateReport() -> SourceReceiverReport {
//        let expectedInterval = packetsExpectedInterval
//        let lossInterval = packetsLostInterval
//        let lossFraction = if expectedInterval == 0 || lossInterval < 0 {
//            Double.zero
//        } else {
//            Double(lossInterval) / Double(expectedInterval)
//        }
//        let dlsr = if let lsrReceivedAt = lsrReceivedAt {
//            RTPTimestamp.now().timeSince(other: lsrReceivedAt)
//        } else {
//            nil as RTPTimeInterval?
//        }
//        expectedPrior = packetsExpected
//        receivedPrior = packetsReceived
//        return SourceReceiverReport(ssrc: ssrc, lostFraction: lossFraction, cumulativePacketsLost: lossInterval, extendedSequenceMax: extendedMax, jitter: jitter, lsr: lsr, dlsr: dlsr)
//    }
//}
//
//struct SourceReceiverReport {
//    let ssrc: UInt32
//    let lostFraction: Double
//    var lossFractionBits: Data {
//        let fractionLostUInt8 = UInt8(min(max(lostFraction * 256.0, 0), 255.0))
//        return Data([fractionLostUInt8])
//    }
//    let cumulativePacketsLost: UInt32
//    var cumulativePacketsLostBits: Data {
//        let clampedTotalLost = min(cumulativePacketsLost, 0xFFFFFF)
//        let clampedTotalLostBE = UInt32(clampedTotalLost).bigEndian
//        return Data([
//            UInt8((clampedTotalLostBE & 0x00FF0000) >> 16),
//            UInt8((clampedTotalLostBE & 0x0000FF00) >> 8),
//            UInt8(clampedTotalLostBE & 0x000000FF)
//        ])
//    }
//    let extendedSequenceMax: UInt32
//
//    let jitter: RTPTimeInterval
//
//    var lsr: RTPTimestamp?
//    var dlsr: RTPTimeInterval?
//
//    func toReportBytes() -> Data {
//        var data = Data.init(capacity: 24)
//        data.append(ssrc.toData()) // 4
//        data.append(lossFractionBits) // 1
//        data.append(cumulativePacketsLostBits) // 3
//        data.append(extendedSequenceMax.toData())// 4
//        data.append(jitter.toData()) // 4
//        data.append(lsr?.toData() ?? UInt32.zero.toData()) // 4
//        data.append(dlsr?.toData() ?? UInt32.zero.toData()) // 4
//        return data
//    }
//}
//
//
//let BANDWIDTH: Double = 10000.0
//
//struct SenderReport {
//    let timestamp: RTPTimestamp
//    let ssrc: UInt32
//}
//
//actor RTCPController {
//    var sourceMap: [UInt32: SourceInfo]
//    var initial: Bool = true
//    let rootSSRC: UInt32
//    var avgPacketSize: Double = 128.0
//    let hostBindPort: Int
//    let remoteAddress: SocketAddress
//
//    init(rootSSRC: UInt32, remoteAddress: SocketAddress, hostBindPort: Int) {
//        self.sourceMap = [rootSSRC: SourceInfo(ssrc: rootSSRC)]
//        self.rootSSRC = rootSSRC
//        self.hostBindPort = hostBindPort
//        self.remoteAddress = remoteAddress
//    }
//
//    func registerPacket(packet: RTPPacket, atTime: Date) {
//        let atTime = RTPTimestamp(date: atTime)
//        if var source = sourceMap[packet.ssrc] {
//            source.recordPacket(packet: packet, atTime: atTime)
//        } else {
//            var source = SourceInfo(ssrc: packet.ssrc)
//            source.recordPacket(packet: packet, atTime: atTime)
//            sourceMap[packet.ssrc] = source
//        }
//    }
//
//    func registerSenderReport(reports: [SenderReport], atTime: Date) {
//        let rtpTS = RTPTimestamp(date: atTime)
//        for report in reports {
//            sourceMap[report.ssrc]?.recordSenderReport(report: report, receivedAt: rtpTS)
//        }
//    }
//
//    func clearAll() {
//        sourceMap = [rootSSRC: SourceInfo(ssrc: rootSSRC)]
//    }
//
//    func generateRTCPPacket() -> Data {
//        let RTCP_SIZE_GAIN = 1.0 / 16.0
//        var packet = Data()
//
//        var reportBlockBytes: [Data]  = []
//        for (_, report) in sourceMap {
//            reportBlockBytes.append(report.generateReport().toReportBytes())
//        }
//
//        // Header
//        let version: UInt8 = 2 << 6
//        let padding: UInt8 = 0
//        let reportCount: UInt8 = UInt8(reportBlockBytes.count)
//        let packetType: UInt8 = 201
//        var length: UInt16 = UInt16((1 + reportBlockBytes.count * 6) * 4 / 4).bigEndian  // in 32-bit words minus one
//        let header = version | padding | reportCount
//        packet.append(header)
//        packet.append(packetType)
//        packet.append(contentsOf: Data(bytes: &length, count: 2))
//
//        // SSRC of packet sender (placeholder)
//        packet.append(contentsOf: rootSSRC.toData())
//
//        // Append report blocks
//        for block in reportBlockBytes {
//            packet.append(block)
//        }
//
//        // Adding 28 for UDP over IP
//        avgPacketSize += (Double(packet.count + 28) - avgPacketSize) * RTCP_SIZE_GAIN
//
//        return packet
//    }
//
//    func rtcpInterval() -> Double {
//        let members = sourceMap.values.filter { $0.activeSender }.count
//        let senders = sourceMap.count
//        var rtcpBw = 0.05 * BANDWIDTH
//        let weSent = sourceMap[rootSSRC]?.activeSender ?? false
//
//        let RTCP_MIN_TIME = 5.0
//        let RTCP_SENDER_BW_FRACTION = 0.25
//        let RTCP_RCVR_BW_FRACTION = 1 - RTCP_SENDER_BW_FRACTION
//
//        var rtcpMinTime = RTCP_MIN_TIME
//
//        if initial {
//            rtcpMinTime /= 2
//        }
//        initial = false
//
//        var n = members
//        if senders > 0 && Double(senders) < Double(members) * RTCP_SENDER_BW_FRACTION {
//            if weSent {
//                rtcpBw *= RTCP_SENDER_BW_FRACTION
//                n = senders
//            } else {
//                rtcpBw *= RTCP_RCVR_BW_FRACTION
//                n -= senders
//            }
//        }
//
//
//        let t = max(avgPacketSize * Double(n) / rtcpBw, rtcpMinTime)
//
//        return t * (Double(arc4random()) / Double(UINT32_MAX) + 0.5)
//    }
//
//    func startReportingContinuously() async {
//        let controller = self
//        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        defer {
//            try? eventLoopGroup.syncShutdownGracefully()
//        }
//        let remoteAddress = controller.remoteAddress
//
//        do {
//            let bootstrap = DatagramBootstrap(group: eventLoopGroup)
//                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
//                .channelInitializer { channel in
//                    channel.pipeline.addHandler(DatagramHandler(controller: controller))
//                }
//
//            let channel: Channel = try await bootstrap.bind(host: "0.0.0.0", port: 6971).get()
//
//            try? await withTaskCancellationHandler {
//                while !Task.isCancelled {
//                    do {
//                        try await Task.sleep(nanoseconds: UInt64(controller.rtcpInterval()) * 1_000_000_000)
//                    } catch {
//                        return
//                    }
//
//                    if isInitial() {
//                        let sentPacket = getInitial
//                        var buffer = channel.allocator.buffer(capacity: sentPacket.count)
//                        buffer.writeBytes(sentPacket)
//                        let writeData = AddressedEnvelope(
//                            remoteAddress: remoteAddress,
//                            data: buffer
//                        )
//
//                        channel.writeAndFlush(writeData, promise: nil)
//
//                        var buffer = channel.allocator.buffer(capacity: sentPacket.count)
//                        buffer.writeBytes(sentPacket)
//                        let writeData = AddressedEnvelope(
//                            remoteAddress: remoteAddress,
//                            data: buffer
//                        )
//
//                        channel.writeAndFlush(writeData, promise: nil)
//                    }
//
//                    let reportPacket = await controller.generateRTCPPacket()
//                    var buffer = channel.allocator.buffer(capacity: reportPacket.count)
//                    buffer.writeBytes(reportPacket)
//                    let writeData = AddressedEnvelope(
//                        remoteAddress: remoteAddress,
//                        data: buffer
//                    )
//
//                    channel.writeAndFlush(writeData, promise: nil)
//                }
//
//                try await channel.closeFuture.get()
//            } onCancel: {
//                Task {
//                    channel.close()
//                }
//            }
//        } catch {
//            print("Failed to create datagram channel: \(error)")
//        }
//    }
//
//    final class DatagramHandler: ChannelInboundHandler {
//        typealias InboundIn = AddressedEnvelope<ByteBuffer>
//
//        let controller: RTCPController
//
//        init(controller: RTCPController) {
//            self.controller = controller
//        }
//
//        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//            let envelope = self.unwrapInboundIn(data)
//            let packet = Data(envelope.data.readableBytesView)
//
//            let receivedAt = Date.now
//
//            if let reports = parseReports(packet: packet) {
//                Task {
//                    await controller.registerSenderReport(reports: reports, atTime: receivedAt)
//                }
//            }
//        }
//    }
//}
//
//func ntpDate(mostSignificant: UInt32, leastSignificant: UInt32) -> Date {
//    let ntpEpoch = Date(timeIntervalSince1970: 2208988800) // NTP epoch in UNIX epoch
//    let seconds = Double(mostSignificant) - Double(2208988800) // Convert to UNIX epoch
//    let fraction = Double(leastSignificant) / Double(UInt32.max)
//    return Date(timeInterval: seconds + fraction, since: ntpEpoch)
//}
//
//func parseReports(packet: Data) -> [SenderReport]? {
//    var reports: [SenderReport] = []
//    var offset = 0
//
//    // Validate header (at least 28 bytes: 4 for header and 24 for sender info)
//    guard packet.count >= 28 else { return nil }
//
//    // Skip RTCP header (4 bytes)
//    offset += 4
//
//    // Get SSRC of sender (4 bytes)
//    let senderSSRC = packet[offset..<offset+4].withUnsafeBytes {
//        UInt32(bigEndian: $0.load(as: UInt32.self))
//    }
//
//    // Parse NTP timestamp (8 bytes: most significant word + least significant word)
//    let ntpMostSignificant = packet[offset+4..<offset+8].withUnsafeBytes {
//        UInt32(bigEndian: $0.load(as: UInt32.self))
//    }
//    let ntpLeastSignificant = packet[offset+8..<offset+12].withUnsafeBytes {
//        UInt32(bigEndian: $0.load(as: UInt32.self))
//    }
//
//    // Generate the date for the sender report
//    let senderDate = ntpDate(mostSignificant: ntpMostSignificant, leastSignificant: ntpLeastSignificant)
//
//    // Append the sender's report
//    reports.append(SenderReport(timestamp: RTPTimestamp(date: senderDate), ssrc: senderSSRC))
//
//    // Update the offset to skip sender info (24 bytes)
//    offset += 24
//
//    // Parse each report block (24 bytes each)
//    while offset + 24 <= packet.count {
//        let ssrc = packet[offset..<offset+4].withUnsafeBytes {
//            UInt32(bigEndian: $0.load(as: UInt32.self))
//        }
//
//        // For this example, I'll use the sender's date. You might want to use a separate date for each report.
//        reports.append(SenderReport(timestamp: RTPTimestamp(date: senderDate), ssrc: ssrc))
//
//        // Move to the next report block (24 bytes)
//        offset += 24
//    }
//
//    return reports
//}
//
//
//
//
//
//func getTemporarySDPFile(sdpString: String) throws -> URL {
//    let string: String = "test"
//    let tempDir = FileManager.default.temporaryDirectory
//    let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString)
//
//    do {
//        try string.write(to: tempFileURL, atomically: true, encoding: .utf8)
//        print("File written to: \(tempFileURL)")
//    } catch {
//        print("Error writing file: \(error)")
//    }
//
//    return tempFileURL
//}
//
//let VALID_PAYLOAD_TYPE = 97
//
//
//let SEQ_MAX: UInt32 = UInt32(UInt16.max);
//func greatestConsideringMax(lastMax: UInt16, seqNo: UInt16) -> (UInt16, Bool) {
//    let wrapAroundThresholdUpper: UInt16 = UInt16.max / 3 * 2
//    let wrapAroundThresholdLower: UInt16 = UInt16.max / 3
//
//    // Check for sequence wrap-around
//    if (lastMax > wrapAroundThresholdUpper) && (seqNo < wrapAroundThresholdLower) {
//        return (seqNo, true)
//    }
//
//    // No wrap-around, return the maximum
//    return (max(lastMax, seqNo), false)
//}
//
////try await withThrowingTaskGroup(of: QuakeLocation.self) { group in
////    var locations: [QuakeLocation] = []
////    for quake in quakes {
////        group.addTask {
////            // Work inside this closure is captured as a task.
////            // The code should return a QuakeLocation.
////            return try await quakeClient.quakeLocation(from: quake.url)
////        }
////    }
////    // Wait on a result with group.next().
////    while let location = try await group.next() {
////        // The constant location is a QuakeLocation.
////        locations.append(location)
////    }
////}
//
