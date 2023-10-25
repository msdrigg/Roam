import Foundation
import Network
import CommonCrypto
import os
import AVFoundation
import AsyncAlgorithms

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "PrivateListening"
)

let HOST_RTP_PORT: UInt16 = 31694
let HOST_RTCP_PORT: UInt16 = 31695
let DEFAULT_REMOTE_RTCP_PORT: UInt16 = 5150
let RTP_PAYLOAD_TYPE = 97
let CLOCK_RATE = 48000
let PACKET_SIZE_MS: Int64 = 10

enum PrivateListeningError: Error, LocalizedError {
    case BadURL
}

public func listenContinually(location: String, rtcpPort: UInt16?) async throws {
    do {
        try await withThrowingDiscardingTaskGroup{ taskGroup in
            logger.info("Starting PL")
            let ecpSession: ECPSession
            do {
                ecpSession = try ECPSession(location: location)
            } catch {
                logger.error("Error creating ECPSession: \(error)")
                // Throwing in body explicitly cancels all tasks in group
                throw error
            }
            
            let rtpSession: RTPSession
            if let url = URL(string: location), let host = url.host() {
                rtpSession = try RTPSession(localRTPPort: HOST_RTP_PORT, localRTCPPort: HOST_RTCP_PORT, remoteRTCPPort: rtcpPort ?? DEFAULT_REMOTE_RTCP_PORT, remoteRTCPAddress: host)
            } else {
                logger.error("Error getting RTPSession")
                throw PrivateListeningError.BadURL
            }
            taskGroup.addTask {
                try await rtpSession.streamAudio()
            }
            
            
            taskGroup.addTask{
                do {
                    try await ecpSession.configure()
                    try await ecpSession.requestPrivateListening(requestId: "1")
                    await Task.sleepUntilCancelled()
                } catch {
                    logger.error("Error requesting private listing \(error)")
                    // Throwing an error from a child task in a throwingDiscardingTaskGroup cancels the whole group
                    await ecpSession.close()
                    throw error
                }
                await ecpSession.close()
            }
            
            taskGroup.addTask {
                try await withTimeout(delay: 6.0) {
                    try await rtpSession.performRTCPHandshake()
                }
                try await rtpSession.sendRTCPReceiverReports()
            }

        }
    } catch {
        logger.error("Error in PL task group \(error)")
        throw error
    }
}

actor RTPSession {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RTPSession.self)
    )
    
    let videoBufferMs: UInt32 = 400
    let baseAudioTransitMs: UInt32 = 0
    let HUGE_FIXED_VDLY_MS: UInt32 = 1200
    
    var softwareAudioDelayMs: UInt32 {
        videoBufferMs + baseAudioTransitMs
    }
    
    let rtcpStream: AsyncThrowingBufferedChannel<RtcpPacket, any Error>
    let rtpStream: AsyncThrowingBufferedChannel<RtpPacket, any Error>
    let rtpListener: NWListener
    let rtcpListener: NWListener
    
    let remoteRtcpConnection: NWConnection
    
    enum RTPError: Error, LocalizedError {
        case BadRTCPPacket
    }
    
    init(localRTPPort: UInt16, localRTCPPort: UInt16, remoteRTCPPort: UInt16, remoteRTCPAddress: String) throws {
        let remoteRtcpEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(remoteRTCPAddress), port: NWEndpoint.Port(rawValue: remoteRTCPPort)!)
        
        let rtcpParameters = NWParameters.udp
        let localEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("0.0.0.0"), port: NWEndpoint.Port(rawValue: localRTPPort)!)
        rtcpParameters.requiredLocalEndpoint = localEndpoint
        rtcpParameters.allowLocalEndpointReuse = true
        
        remoteRtcpConnection = NWConnection(to: remoteRtcpEndpoint, using: rtcpParameters)
        
        let rtpParams = NWParameters.udp
        rtpParams.allowLocalEndpointReuse = true
        
        rtpListener = try NWListener(using: rtpParams, on: NWEndpoint.Port(rawValue: localRTPPort)!)
        rtcpListener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: localRTCPPort)!)
        
        remoteRtcpConnection.start(queue: .global())
        
        self.rtpStream = AsyncThrowingBufferedChannel<RtpPacket, Error>()
        self.rtcpStream = AsyncThrowingBufferedChannel<RtcpPacket, Error>()
        Task {
            await startRtcpStream()
            await startRtpStream()
        }
    }
    
    deinit {
        Self.logger.info("Closing rtp listeners and connections")
        self.rtpListener.cancel()
        self.rtcpListener.cancel()
        self.remoteRtcpConnection.cancel()
    }
    
    func startRtcpStream() {
        rtcpListener.newConnectionHandler = { [weak self] rtcpConnection in
            guard let rtcpStream  = self?.rtcpStream else {
                Self.logger.warning("No rtcp stream when getting new connection")
                return
            }
            Self.logger.info("Got new rtcp connection \(String(describing: rtcpConnection))")
            @Sendable func closure(_ data: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) {
                Self.logger.info("Got new rtcp packet \(String(describing: data)), error: \(error)")
                guard let data = data else {
                    return
                }
                if let packet = RtcpPacket(data: data) {
                    rtcpStream.send(packet)
                } else {
                    Self.logger.error("Error parsing rtcp packet")
                }
                rtcpConnection.receiveMessage(completion: closure)
            }
            
            rtcpConnection.receiveMessage(completion: closure)
            
            self?.rtcpListener.stateUpdateHandler = { state in
                switch state {
                case .failed(let err):
                    Self.logger.info("rtcpConnection failed with error \(err)")
                    rtcpConnection.send(content: RtcpPacket.bye(.init(ssrc: 0)).packet(), completion: .contentProcessed( {error in
                        Self.logger.info("Sent RTCP Bye with error \(error)")
                        rtcpConnection.cancel()
                    }))
                    rtcpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtcpConnection cancelled")
                    rtcpConnection.send(content: RtcpPacket.bye(.init(ssrc: 0)).packet(), completion: .contentProcessed( {error in
                        Self.logger.info("Sent RTCP Bye with error \(error)")
                        rtcpConnection.cancel()
                    }))
                    rtcpStream.finish()
                case .ready:
                    Self.logger.info("rtcpConnection ready")
                default:
                    Self.logger.info("Getting new state \(String(describing: state))")
                }
            }
            
            
            rtcpConnection.stateUpdateHandler = { state in
                switch state {
                case .failed(let err):
                    Self.logger.info("rtcpConnection connection failed with error \(err)")
                    rtcpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtcpConnection connection cancelled")
                    rtcpStream.finish()
                case .ready:
                    Self.logger.info("rtcpConnection connection ready")
                default:
                    Self.logger.info("Getting new rtcpConnection connection state \(String(describing: state))")
                }
            }
            rtcpConnection.start(queue: .global())
        }
        
        rtcpListener.start(queue: .global())
    }
    
    func startRtpStream() {
        rtpListener.newConnectionHandler = { [weak self] rtpConnection in
            guard let rtpStream  = self?.rtpStream else {
                Self.logger.warning("No rtp stream when getting new connection")
                return
            }

            Self.logger.info("Getting rtp connection \(String(describing: rtpConnection))")
            
            @Sendable func closure(_ data: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) {
                guard let data = data else {
                    return
                }
                do {
                    let packet = try RtpPacket(data: data)

                    rtpStream.send(packet)
                } catch {
                    Self.logger.error("Error parsing rtp packet")
                }
                
                rtpConnection.receiveMessage(completion: closure)
            }
            
            rtpConnection.receiveMessage(completion: closure)
            rtpConnection.stateUpdateHandler = { state in
                switch state {
                case .failed(let err):
                    Self.logger.info("rtcpConnection connection failed with error \(err)")
                    rtpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtcpConnection connection cancelled")
                    rtpStream.finish()
                case .ready:
                    Self.logger.info("rtcpConnection connection ready")
                default:
                    Self.logger.info("Getting new rtcpConnection connection state \(String(describing: state))")
                }
            }
            rtpConnection.start(queue: .global())
            
            self?.rtpListener.stateUpdateHandler = { state in
                switch state {
                case .failed(let err):
                    Self.logger.info("RTPConnection failed with error \(err)")
                    rtpConnection.cancel()
                    rtpStream.fail(err)
                case .cancelled:
                    Self.logger.info("RTPConnection cancelled")
                    rtpConnection.cancel()
                    rtpStream.finish()
                case .ready:
                    Self.logger.info("rtpConnection ready")
                default:
                    Self.logger.info("Getting new state \(String(describing: state))")
                }
            }
        }
        
        rtpListener.start(queue: .global())
    }
    
    func performVDLYHandshake() async throws {
        // Send VDLY rtcp packet using rtcpConnection
        // Wait for response XDLY using rtcpStream
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) -> Void in
            remoteRtcpConnection.send(content: RtcpPacket.vdly(delayMs: HUGE_FIXED_VDLY_MS).packet(), completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    Self.logger.debug("VDLY Sent")
                    continuation.resume(returning: ())
                }
            }))
        }
        
        for try await packet in rtcpStream {
            switch packet {
            case .appSpecific(.xdly(let xdly)):
                if xdly.delayMicroseconds == HUGE_FIXED_VDLY_MS * 1000 {
                    Self.logger.info("Got good xdly packet from rtcp as expected")
                    return
                }
                Self.logger.warning("Got bad xdly microseconds. Expecting \(self.HUGE_FIXED_VDLY_MS * 1000)")
            default:
                Self.logger.warning("Got bad packet from rtcp. Expecting App.XDLY. Got \(String(describing: packet))")
            }
        }
    }
    
    func performNewClientHandshake() async throws {
        // Send CVER rtcp packet using rtcpConnection
        // Wait for response NCLI packet using rtcpStream
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) -> Void in
            remoteRtcpConnection.send(content: RtcpPacket.cver(clientVersion: 2).packet(), completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    Self.logger.debug("VDLY Sent")
                    continuation.resume(returning: ())
                }
            }))
        }
        
        for try await packet in rtcpStream {
            switch packet {
            case .appSpecific(.ncli(_)):
                Self.logger.info("Got ncli packet from rtcp as expected")
                return
            default:
                Self.logger.warning("Got bad packet from rtcp. Expecting App.NCLI. Got \(String(describing: packet))")
            }
        }
    }
    
    func performRTCPHandshake() async throws {
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performVDLYHandshake()
                }
                break
            } catch {
                Self.logger.error("Error performing VDLY handshake \(error)")
                let _ = await timerStream.next()
            }
        }
        
        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performNewClientHandshake()
                }
                break
            } catch {
                Self.logger.error("Error performing NCLI handshake \(error)")
            }
        }
    }
    
    func sendRTCPReceiverReport() async throws {
//        Self.logger.info("Sending receiver report")
        
        let report = RtcpPacket.receiverReport(.init(ssrc: 0, reportBlocks: []))
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) -> Void in
            remoteRtcpConnection.send(content: report.packet(), completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }))
        }
    }
    
    
    func sendRTCPReceiverReports() async throws {
//        Self.logger.info("Sending receiver reports")
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await self.sendRTCPReceiverReport()
            } catch {
                Self.logger.error("Error sending receiver report \(error)")
            }
            let _ = await timerStream.next()
        }
        
    }
    
    func streamAudio() async throws {
#if !os(macOS)
        setupSessionForAudioPlayback()
        defer {
            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch {
                Self.logger.error("Failed to disable audio session active: \(error)")
            }
        }
#endif

        
        try await withThrowingDiscardingTaskGroup { taskGroup in
            let rtpAudioPlayer = AudioPlayer()
            
            Self.logger.info("Starting receiving rtp packets")
            let decoder: OpusDecoderWithJitterBuffer = try OpusDecoderWithJitterBuffer(audioBuffer: Double(videoBufferMs) / 1000)
            taskGroup.addTask {
                var count = 0
                var lsqNo: Int64 = 0
                var rollingSequenceNumber: Int64? = nil

                do {
                    for try await var rtpPacket in self.rtpStream {
                        // Drop first 5 packets because we want to have a reasonable sync packet and sometimes the first packet or two isn't valid
                        // Self.logger.debug("Getting packet from stream \(String(describing: rtpPacket)) at count \(count)")
                        count += 1
                        if count < 5 {
                            continue
                        }
                        rollingSequenceNumber = rtpPacket.updateWithRollingSequenceNumber(rollingSequenceNumber)
                        
                        if lsqNo != Int64(rtpPacket.sequenceNumber) - 1 {
                            Self.logger.info("Packet with seqno received \(rtpPacket.sequenceNumber) when expecting \(lsqNo + 1)")
                        }
                        lsqNo = Int64(rtpPacket.sequenceNumber)
                        
                        await decoder.addPacket(packet: rtpPacket)
                    }
                } catch {
                    Self.logger.error("Error iterating rtpstream \(error)")
                }
            }
            
            taskGroup.addTask {
                try await rtpAudioPlayer.start()
                defer {
                    Task {
                        await rtpAudioPlayer.stop()
                    }
                }

                
                for await _ in AsyncTimerSequence.repeating(every: .milliseconds(10), tolerance: .microseconds(10)) {
                    Task {
                        if let lrt = await rtpAudioPlayer.lastRender() {
                            if let (pcmBuffer, audioTime) = await decoder.nextPacket(atTime: lrt) {
                                await rtpAudioPlayer.scheduleAudioBytes(buffer: pcmBuffer, atTime: audioTime)
                            }
                        }
                    }
                }
            }
            
            taskGroup.addTask {
                for await _ in AsyncTimerSequence.repeating(every: .milliseconds(200)) {
                    if let lrt = await rtpAudioPlayer.lastRender() {
                        let latency = await rtpAudioPlayer.getOutputLatency()
                        if await decoder.syncAudio(time: lrt, additionalAudioDelay: Double(self.HUGE_FIXED_VDLY_MS - self.softwareAudioDelayMs) / 1000 - latency) {
                            break
                        }
                    }
                }
                
                if let stream = LatencyListener().events {
                    for await latency in stream {
                        Self.logger.error("New latency event \(latency)")
                        for await _ in AsyncTimerSequence.repeating(every: .milliseconds(200)) {
                            if let lrt = await rtpAudioPlayer.lastRender() {
                                if await decoder.syncAudio(time: lrt, additionalAudioDelay: Double(self.HUGE_FIXED_VDLY_MS - self.softwareAudioDelayMs) / 1000 - latency) {
                                    break
                                }
                            }
                        }
                        Self.logger.info("Synced audio!")
                    }
                } else {
                    Self.logger.error("Unable to get latency events stream")
                }
            }
        }
    }
    
#if !os(macOS)
    func setupSessionForAudioPlayback() {
        // Retrieve the shared audio session.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            Self.logger.info("Settingup audio session")
            // Set the audio session category and mode.
            try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audioSession.setActive(true)
        } catch {
            Self.logger.error("Failed to set the audio session configuration: \(error)")
        }
    }
#endif
}

actor ECPSession {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ECPSession.self)
    )
    
    let url: URL
    var session: URLSession
    var webSocketTask: URLSessionWebSocketTask
    
    enum ECPSessionError: Error, LocalizedError {
        case BadWebsocketMessage
        case AuthDenied
        case BadURL
        case ConnectFailed
        case BadInterfaceIP
        case PLStartFailed
    }
    
    public init(location: String) throws {
        guard let url = URL(string: "\(location.replacing(try! Regex("http"), with: "ws"))ecp-session") else {
            Self.logger.error("Bad url for location \(location)ecp-session")
            throw ECPSessionError.BadURL
        }
        self.url = url
        let config: URLSessionConfiguration = .default
        
        self.session = URLSession(configuration: config)
        webSocketTask = session.webSocketTask(with: self.url, protocols: ["ecp-2"])
        self.webSocketTask.resume()
    }
    
    public func close() async {
        Self.logger.info("Closing ecp")
        webSocketTask.cancel()
        session.invalidateAndCancel()
    }
    
    public func configure() async throws {
        if webSocketTask.state == .completed {
            self.webSocketTask = session.webSocketTask(with: self.url, protocols: ["ecp-2"])
            self.webSocketTask.resume()
        }
        do {
            try await establishConnectionAndAuthenticate()
        } catch {
            Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error)")
            self.webSocketTask.cancel()
            throw error
        }
    }
    
    public func requestPrivateListening(requestId: String) async throws {
        guard let connectingInterface = await tryConnectTCP(location: self.url.absoluteString, timeout: 3.0) else {
            Self.logger.error("Unable to connect tcp to \(self.url.absoluteString) to request private listening")
            throw ECPSessionError.ConnectFailed
        }
        let localInterfaces = await allAddressedInterfaces()
        guard let localNWInterface = localInterfaces.first(where: { connectingInterface.name == $0.name && $0.isIPV4 }) else {
            Self.logger.error("Connected with interface \(connectingInterface.name) but no match in \(localInterfaces.map{$0.name})")
            throw ECPSessionError.BadInterfaceIP
        }
        let localAddress = localNWInterface.address.addressString
        Self.logger.debug("Got local address \(localAddress)")
        
        let requestData = String(data: try JSONEncoder().encode(ConfigureAudioRequest.privateListening(hostIp: localAddress, requestId: requestId)), encoding: .utf8)!
        // We can unwrap because json encoder always encodes to string
        try await webSocketTask.send(.string(requestData))
        
        let responseMessage = try await webSocketTask.receive()
        let plResponseData = switch responseMessage {
        case .data(let data):
            data
        case .string(let str):
            if let data = str.data(using: .utf8) {
                data
            } else {
                Self.logger.error("Unknown message type received: \(String(describing: responseMessage))")
                throw ECPSessionError.BadWebsocketMessage
            }
        @unknown default:
            Self.logger.error("Unknown message type received: \(String(describing: responseMessage))")
            throw ECPSessionError.BadWebsocketMessage
        }
        
        let authResponse = try JSONDecoder().decode(BaseResponse.self, from: plResponseData)
        if !authResponse.isSuccess {
            Self.logger.error("Unable to start PL session on roku with response \(String(describing: authResponse))")
            throw ECPSessionError.PLStartFailed
        }
    }
    
    private func establishConnectionAndAuthenticate() async throws {
        do {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            
            let authMessage = try await webSocketTask.receive()
            let authMessageData = switch authMessage {
            case .data(let data):
                data
            case .string(let str):
                if let data = str.data(using: .utf8) {
                    data
                } else {
                    Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                    throw ECPSessionError.BadWebsocketMessage
                }
            @unknown default:
                Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                throw ECPSessionError.BadWebsocketMessage
            }
            
            let challengeMessage = try decoder.decode(AuthChallenge.self, from: authMessageData)
            let responseMessage = AuthVerifyRequest(challenge: challengeMessage.paramChallenge)
            let responseData = try encoder.encode(responseMessage)
            // We can unwrap here because data always encodes to string
            try await webSocketTask.send(.string(String(data: responseData, encoding: .utf8)!))
            
            let authResponseMessage = try await webSocketTask.receive()
            let authResponseMessageData = switch authResponseMessage {
            case .data(let data):
                data
            case .string(let str):
                if let data = str.data(using: .utf8) {
                    data
                } else {
                    Self.logger.error("Unknown message type received: \(String(describing: authResponseMessage))")
                    throw ECPSessionError.BadWebsocketMessage
                }
            @unknown default:
                Self.logger.error("Unknown message type received: \(String(describing: authResponseMessage))")
                throw ECPSessionError.BadWebsocketMessage
            }
            
            let authResponse = try decoder.decode(BaseResponse.self, from: authResponseMessageData)
            if !authResponse.isSuccess {
                Self.logger.error("Unable to authenticate to roku with response \(String(describing: authResponse))")
                throw ECPSessionError.AuthDenied
            }
            Self.logger.info("Authenticated to roku successfully")
        } catch {
            Self.logger.error("WebSocket connection failed: \(error)")
            throw error
        }
    }
    
    private struct AuthChallenge: Codable {
        let paramChallenge: String
        
        private enum CodingKeys : String, CodingKey {
            case paramChallenge = "param-challenge"
        }
    }
    
    private struct AuthVerifyRequest: Codable {
        let paramMicrophoneSampleRates: String = "1600"
        let paramResponse: String
        let requestId: String
        let paramClientFriendlyName: String = "Wireless Speaker"
        let request: String = "authenticate"
        let paramHasMicrophone: String = "false"
        
        static let KEY = "95E610D0-7C29-44EF-FB0F-97F1FCE4C297"
        
        private static func charTransform(_ var1: UInt8, _ var2: UInt8) -> UInt8 {
            var var3: UInt8
            if var1 >= UInt8(ascii: "0") && var1 <= UInt8(ascii: "9") {
                var3 = var1 - UInt8(ascii: "0")
            } else if var1 >= UInt8(ascii: "A") && var1 <= UInt8(ascii: "F") {
                var3 = var1 - UInt8(ascii: "A") + 10
            } else {
                return var1
            }
            
            var var2 = (15 - var3 + var2) & 15
            if var2 < 10 {
                var2 += UInt8(ascii: "0")
            } else {
                var2 = var2 + UInt8(ascii: "A") - 10
            }
            
            return var2
        }
        
        
        init(challenge: String) {
            let authKeySeed: Data = Data(Self.KEY.utf8.map { Self.charTransform($0, 9) })
            
            func createAuthKey(_ s: String) -> String {
                var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                let data = s.data(using: .utf8)! + authKeySeed
                data.withUnsafeBytes {
                    _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
                }
                let base64String = Data(digest).base64EncodedString()
                return base64String
            }
            paramResponse = createAuthKey(challenge)
            requestId = "0"
            
        }
        
        private enum CodingKeys : String, CodingKey {
            case paramMicrophoneSampleRates = "param-microphone-sample-rates"
            case paramResponse = "param-response"
            case paramClientFriendlyName = "param-client-friendly-name"
            case request
            case requestId = "request-id"
            case paramHasMicrophone = "param-has-microphone"
        }
    }
    
    
    private struct BaseResponse: Codable {
        let response: String
        let status: String
        
        var isSuccess: Bool {
            return status == "200"
        }
    }
    
    private struct ConfigureAudioRequest: Codable {
        let paramDevname: String?
        let paramAudioOutput: String
        let request: String = "set-audio-output"
        let requestId: String
        
        static func privateListening(hostIp: String, requestId: String) -> Self {
            Self(paramDevname: "\(hostIp):\(HOST_RTP_PORT):\(RTP_PAYLOAD_TYPE):\(CLOCK_RATE / 50)", paramAudioOutput: "datagram", requestId: requestId)
        }
        
        private enum CodingKeys: String, CodingKey {
            case paramDevname = "param-devname"
            case paramAudioOutput = "param-audio-output"
            case request
            case requestId = "request-id"
        }
    }
}
