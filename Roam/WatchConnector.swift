#if os(iOS)
import WatchConnectivity
import os.log

class DeviceTransferManager: NSObject, WCSessionDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceTransferManager.self)
    )
    
    static let shared = DeviceTransferManager()
    var session: WCSession?
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func transferDevices(devices: [DeviceAppEntity]) {
        guard let session = session else {
            Self.logger.info("Not transfering devices because WCSession not initialized")
            return
        }
        if session.activationState == .activated {
            if devices.count == 0 {
                Self.logger.info("Not transfering devices because devices is empty")
                return
            }
            var deviceMap: [String: String] = [:]
            for device in devices {
                deviceMap[device.id] = device.location
            }
            Self.logger.info("Transfering devices \(deviceMap)")
            if session.outstandingUserInfoTransfers.count > 0 {
                Self.logger.info("Cancelling ongoing transfer because we are creating a new one")
                self.session?.outstandingUserInfoTransfers.last?.cancel()
            }
            session.transferUserInfo(deviceMap)
        } else {
            Self.logger.info("Not transfering devices activation state not activated: \(String(describing: self.session?.activationState))")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Self.logger.error("WCSession activated with error: \(error)")
        Task {
            do {
                let container = try getSharedModelContainer()
                let devices = try await DeviceActor(modelContainer: container).allDeviceEntities()
                DispatchQueue.main.async {
                    self.transferDevices(devices: devices)
                }
            } catch {
                Self.logger.error("Error refreshing devices on session active: \(error)")
            }
        }
        
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        Self.logger.info("WatchConnectivity session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        Self.logger.info("WatchConnectivity session deactivated")
    }
}
#endif
