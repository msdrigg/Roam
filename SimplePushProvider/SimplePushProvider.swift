import Foundation
import Combine
import NetworkExtension
import UserNotifications
import OSLog
import Network

class SimplePushProvider: NEAppPushProvider {
    private var connection: NWConnection? = nil
    private var lastHb: Date? = nil
    private var isActive: Bool = false
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SimplePushProvider.self)
    )
    
    override init() {
        super.init()
        
        Self.logger.info("Initialized \(String(describing: self))")
    }
    
    // MARK: - NEAppPushProvider Life Cycle
    
    override func start() {
        Self.logger.info("Started push provider \(String(describing: self))")
        self.isActive = true

        if connection?.state == .ready || connection?.state == .preparing {
            return
        } else {
            self.connection?.cancel()
            self.connection = nil
        }
        
        Task {
            await self.connectAndListen()
        }
    }

    private func connectAndListen() async {
        let host = NWEndpoint.Host("10.19.22.181")
        let port = NWEndpoint.Port(rawValue: 10495)!

        
        if Task.isCancelled || !self.isActive || self.connection != nil {
            return
        }
        
        
        Self.logger.info("Connecting to \(String(describing: host.debugDescription)):\(String(describing: port.debugDescription))")
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Self.logger.info("Connection succeeded!")
                self?.lastHb = Date.now
                self?.receive(on: connection)
            case .failed(_):
                Self.logger.warning("Connection failed")
                connection.cancel()
            case .waiting(_):
                Self.logger.warning("Connection waiting (failed)...")
                connection.cancel()
            case .cancelled:
                Self.logger.warning("Connection cancelled. Restarting...")
                self?.retryConnection(after: 5)
            default:
                Self.logger.info("Connection in new state \(String(describing: newState))")
                break
            }
        }

        connection.start(queue: .global())
        await withTaskCancellationHandler {
            try? await Task.sleep(nanoseconds: UInt64.max / 2)
        } onCancel: {
            connection.cancel()
        }
        
        Self.logger.info("Connect and listen ended somehow... isCancelled=\(Task.isCancelled)")
    }

    private func retryConnection(after delay: TimeInterval) {
        Self.logger.info("Connection failed. Retrying connection after \(delay)")
        self.connection?.cancel()
        self.connection = nil

        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.connectAndListen()
            } catch { }
        }
    }

    private func receive(on connection: NWConnection) {
        Self.logger.info("Waiting to receive new message on connection \(String(describing: connection))")
        connection.receive(minimumIncompleteLength: 0, maximumLength: Int.max) { [weak self] data, _, isComplete, error in
            self?.lastHb = Date.now
            if let data = data, let text = String(data: data, encoding: .utf8) {
                Self.logger.info("Showing local notification \(text)")
                self?.showLocalNotification(message: text)
            }
            
            if self == nil {
                Self.logger.info("Got nil self in receiveMessage...")
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
        Self.logger.warning("Stopped with reason \(String(describing: reason))")
        
        isActive = false
        self.connection?.cancel()
        self.connection = nil
        completionHandler()
    }
    
    override func handleTimerEvent() {
        let hbInterval = (self.lastHb ?? Date.distantPast).timeIntervalSinceNow
        Self.logger.log("Handle timer called with hb \(String(describing: self.lastHb)) since=\(hbInterval)")
        self.lastHb = Date.now
        if self.connection?.state != .preparing || self.connection?.state == .ready || hbInterval < -10 {
            Self.logger.info("Restarting due to cancelled conncetion or missed HB")
            self.connection?.cancel()
            self.connection = nil
            Task {
                await self.connectAndListen()
            }
        }
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

