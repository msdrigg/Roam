import WatchConnectivity
import os.log

class DeviceReceiverManager: NSObject, WCSessionDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceReceiverManager.self)
    )
    
    static let shared = DeviceReceiverManager()
    var session: WCSession?
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleAddDevices(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any] = [:]) {
        handleAddDevices(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleAddDevices(userInfo)
    }
    
    func handleAddDevices(_ devices: [String: Any]) {
        if let deviceMap = devices as? [String: String] {
            Self.logger.info("Trying to add devices \(deviceMap)")
            Task {
                let modelContainer = getSharedModelContainer()
                let deviceActor = DeviceActor(modelContainer: modelContainer)
                for device in deviceMap {
                    if await deviceActor.deviceExists(id: device.key) {
                        Self.logger.info("Device aleady exists \(device.key)")
                        continue
                    }
                    do {
                        let pid = try await deviceActor.addOrReplaceDevice(location: device.value, friendlyDeviceName: "New device", udn: device.key)
                        await deviceActor.refreshDevice(pid)
                    } catch {
                        Self.logger.error("Unable to add new device \(device.key), \(device.value) with error \(error)")
                    }
                }
            }
        } else {
            Self.logger.warning("Error parsing userInfo as [String: String]: \(String(describing: devices))")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Self.logger.info("WCSession activated from watchOS with error \(error)")
    }
}
