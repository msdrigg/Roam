import Foundation
import Combine
import NetworkExtension
import UserNotifications
import OSLog
import Network

class SimplePushProvider: NEAppPushProvider {
    private var task: Task<(), Error>? = nil
    private var lastHb: Date? = nil
    private var isActive: Bool = false
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SimplePushProvider.self)
    )
    
    override init() {
        super.init()
        
        Self.logger.log("Initialized")
    }
    
    // MARK: - NEAppPushProvider Life Cycle
    
    override func start() {
        Self.logger.log("Started")
        self.isActive = true

        
        self.task = Task {
            let host = NWEndpoint.Host("192.168.8.133")
            let port = NWEndpoint.Port(rawValue: 10495)!
            await self.connectAndListen(host: host, port: port)
        }
    }

    private func connectAndListen(host: Network.NWEndpoint.Host, port: Network.NWEndpoint.Port) async {
        if Task.isCancelled || !self.isActive {
            return
        }
        Self.logger.info("Connecting to \(host.debugDescription):\(port.debugDescription)")
        let connection = NWConnection(host: host, port: port, using: .tcp)

        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Self.logger.info("Connection succeeded!")
                self?.receive(on: connection)
            case .failed(_):
                connection.cancel()
                self?.retryConnection(after: 5, host: host, port: port)
            default:
                break
            }
        }

        connection.start(queue: .global())
        await withTaskCancellationHandler {
            try? await Task.sleep(nanoseconds: UInt64.max)
        } onCancel: {
            self.isActive = false
            connection.cancel()
        }
    }

    private func retryConnection(after delay: TimeInterval, host: Network.NWEndpoint.Host, port: Network.NWEndpoint.Port) {
        Self.logger.info("Connection failed. Retrying connection to \(host.debugDescription):\(port.debugDescription) after \(delay)")
        guard !Task.isCancelled else { return }

        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.connectAndListen(host: host, port: port)
            } catch { }
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            Self.logger.info("Message received from tcp connection \(String(describing: data))")
            if let data = data, let text = String(data: data, encoding: .utf8), isComplete {
                self?.showLocalNotification(message: text)
            }

            if error == nil {
                self?.receive(on: connection)
            } else {
                Self.logger.warning("Connection got error \(error). Cancelling connection")
                connection.cancel()
            }
        }
    }
    override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Self.logger.log("Stopped with reason \(String(describing: reason))")
        
        isActive = false
        task?.cancel()
        task = nil
        completionHandler()
    }
    
    override func handleTimerEvent() {
        Self.logger.log("Handle timer called with hb \(String(describing: self.lastHb))")
    }
    
    // MARK: - Notify User
    func showLocalNotification(message: String) {
        Self.logger.log("Received text message: \(message)")
        
        let content = UNMutableNotificationContent()
        content.title = "New message"
        content.body = message
        content.sound = .default
        content.userInfo = [
            "message": message
        ]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.log("Error submitting local notification: \(error)")
                return
            }
            
            Self.logger.log("Local notification posted successfully")
        }
    }
}

