import Foundation
import Network
import CommonCrypto
import os

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>


actor PrivateListeningActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PrivateListeningActor.self)
    )
    
    var url: URL
    var session: URLSession
    var webSocketTask: URLSessionWebSocketTask
    
    private struct AuthChallenge: Codable {
        let paramChallenge: String
        
        private enum CodingKeys : String, CodingKey {
            case paramChallenge = "param-challenge"
        }
    }
    
    private struct AuthRequest: Codable {
        let paramMicrophoneSampleRates: String = "1600"
        let paramResponse: String
        let paramClientFriendlyName: String = "Wireless Speaker"
        let request: String = "authenticate"
        let paramHasMicrophone: String = "false"
        
        private enum CodingKeys : String, CodingKey {
            case paramMicrophoneSampleRates = "param-microphone-sample-rates"
            case paramResponse = "param-response"
            case paramClientFriendlyName = "param-client-friendly-name"
            case request
            case paramHasMicrophone = "param-has-microphone"
        }
    }
    
    static let HOST_RTP_PORT = 6970
    static let HOST_RTCP_PORT = 6971
    static let RTP_TYPE = 97
    static let CLOCK_RATE = 48000
    
    private struct AuthResponse: Codable {
        let response: String
        let status: String
        
        var isSuccess: Bool {
            return response == "authenticate" && status == "200"
        }
    }
    
    private struct ConfigureAudioRequest: Codable {
        let paramDevname: String?
        let paramAudioOutput: String
        let request: String = "set-audio-output"
        
        static func privateListening(hostIp: String) -> Self {
            Self(paramDevname: "\(hostIp):\(HOST_RTP_PORT):\(RTP_TYPE):\(CLOCK_RATE / 50)", paramAudioOutput: "datagram")
        }
        
        static func standardListening() -> Self {
            Self(paramDevname: nil, paramAudioOutput: "speakers")
        }
        
        private enum CodingKeys: String, CodingKey {
            case paramDevname = "param-devname"
            case paramAudioOutput = "param-audio-output"
            case request
        }
    }
    
    enum PrivateListeningError: Error {
        case BadWebsocketMessage
        case AuthDenied
        case BadURL
        case ConnectFailed
        case BadInterfaceIP
    }
    
    public init(location: String) async throws {
        guard let url = URL(string: "\(location)ecp-session") else {
            Self.logger.error("Bad url for location \(location)ecp-session")
            throw PrivateListeningError.BadURL
        }
        self.url = url
        self.session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: self.url)
    }
    
    deinit {
        webSocketTask.cancel()
        session.invalidateAndCancel()
    }
    
    public func configure() async throws {
        if webSocketTask.state == .completed {
            self.webSocketTask = session.webSocketTask(with: self.url)
        }
        self.webSocketTask.resume()
        do {
            try await establishConnectionAndAuthenticate()
        } catch {
            Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error)")
            self.webSocketTask.cancel()
            throw error
        }
    }
    
    public func requestPrivateListening() async throws {
        guard let connectingInterface = await tryConnectTCP(location: self.url.absoluteString, timeout: 3.0) else {
            Self.logger.error("Unable to connect tcp to \(self.url) to request private listening")
            throw PrivateListeningError.ConnectFailed
        }
        let localInterfaces = await getAllInterfaces()
        guard let localNWInterface = localInterfaces.first(where: { connectingInterface.name == $0.name }) else {
            Self.logger.error("Connected with interface \(connectingInterface.name) but no match in \(localInterfaces.map{$0.name})")
            throw PrivateListeningError.BadInterfaceIP
        }
        let localAddress = localNWInterface.address
        Self.logger.debug("Got local address \(localAddress)")
        
        if webSocketTask.state != .running {
            try await configure()
        }
        
        let responseData = try JSONEncoder().encode(ConfigureAudioRequest.privateListening(hostIp: localAddress))
        try await webSocketTask.send(.data(responseData))
        let response = try await webSocketTask.receive()
        Self.logger.debug("Getting response from pl request \(String(describing: response))")
    }
    
    public func requestStandardListening() async throws {
        if webSocketTask.state != .running {
            try await configure()
        }
    }
    
    private func authResponse(_ challenge: String) -> AuthRequest {
        let KEY = "95E610D0-7C29-44EF-FB0F-97F1FCE4C297"
        
        func charTransform(_ var1: UInt8, _ var2: UInt8) -> UInt8 {
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

        let authKeySeed: Data = Data(KEY.utf8.map { charTransform($0, 9) })

        func createAuthKey(_ s: String) -> String {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            let data = s.data(using: .utf8)! + authKeySeed
            data.withUnsafeBytes {
                _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
            }
            let base64String = Data(digest).base64EncodedString()
            return base64String
        }
        
        return AuthRequest(paramResponse: createAuthKey(challenge))
    }
    
    private func establishConnectionAndAuthenticate() async throws {
        do {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            
            while true {
                let authMessage = try await webSocketTask.receive()
                let authMessageData = switch authMessage {
                case .data(let data):
                    data
                case .string(let str):
                    if let data = str.data(using: .utf8) {
                        data
                    } else {
                        Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                        throw PrivateListeningError.BadWebsocketMessage
                    }
                @unknown default:
                    Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                    throw PrivateListeningError.BadWebsocketMessage
                }
                
                let challengeMessage = try decoder.decode(AuthChallenge.self, from: authMessageData)
                let responseMessage = authResponse(challengeMessage.paramChallenge)
                let responseData = try encoder.encode(responseMessage)
                try await webSocketTask.send(.data(responseData))
                
                let authResponseMessage = try await webSocketTask.receive()
                let authResponseMessageData = switch authResponseMessage {
                case .data(let data):
                    data
                case .string(let str):
                    if let data = str.data(using: .utf8) {
                        data
                    } else {
                        Self.logger.error("Unknown message type received: \(String(describing: authResponseMessage))")
                        throw PrivateListeningError.BadWebsocketMessage
                    }
                @unknown default:
                    Self.logger.error("Unknown message type received: \(String(describing: authResponseMessage))")
                    throw PrivateListeningError.BadWebsocketMessage
                }
                
                let authResponse = try decoder.decode(AuthResponse.self, from: authResponseMessageData)
                if !authResponse.isSuccess {
                    Self.logger.error("Unable to authenticate to roku with response \(String(describing: authResponse))")
                    throw PrivateListeningError.AuthDenied
                }
            }
        } catch {
            print("WebSocket connection failed: \(error)")
        }
    }
    
    
    public func listenContinually() throws {
        
    }
}

extension URLSessionWebSocketTask {
    var stream: WebSocketStream {
        return WebSocketStream { continuation in
            Task {
                var isAlive = true
                
                while isAlive && closeCode == .invalid {
                    do {
                        let value = try await receive()
                        continuation.yield(value)
                    } catch {
                        continuation.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }
}


class SocketStream: AsyncSequence {
    typealias AsyncIterator = WebSocketStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message
    
    private var continuation: WebSocketStream.Continuation?
    private let task: URLSessionWebSocketTask
    
    private lazy var stream: WebSocketStream = {
        return WebSocketStream { continuation in
            self.continuation = continuation
            
            Task {
                var isAlive = true
                
                while isAlive && task.closeCode == .invalid {
                    do {
                        let value = try await task.receive()
                        continuation.yield(value)
                    } catch {
                        continuation.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }()
    
    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }
    
    deinit {
        continuation?.finish()
    }
    
    func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }
    
    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
}
