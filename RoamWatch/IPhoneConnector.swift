import WatchConnectivity
import os.log

class WatchConnectivity: NSObject, WCSessionDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WatchConnectivity.self)
    )
    
    static let shared = WatchConnectivity()
    var session: WCSession?
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            WatchConnectivity.logger.info("Activating watchOS WC Receiver")
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        } else {
            WatchConnectivity.logger.info("Cannot activate WC receiver because not supported")
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleAddDevices(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleAddDevices(message)
        
        replyHandler([:])
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleAddDevices(userInfo)
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        
    }
    
    func handleAddDevices(_ devices: [String: Any]) {
        if let deviceMap = devices as? [String: [String: String]] {
            WatchConnectivity.logger.info("Trying to add devices \(deviceMap)")
            Task {
                let modelContainer = getSharedModelContainer()
                let deviceActor = DeviceActor(modelContainer: modelContainer)
                for device in deviceMap {
                    if let existingDevice = await deviceActor.existingDevice(id: device.key) {
                        WatchConnectivity.logger.info("Device aleady exists, only updating name, location \(device.key)")
                        if let location = device.value["location"] {
                            let name = device.value["name"] ?? existingDevice.name
                            try await deviceActor.updateDevice(existingDevice.modelId, name: name, location: location, udn: existingDevice.udn)
                            await deviceActor.refreshDevice(existingDevice.modelId)
                        }
                        continue
                    }
                    do {
                        if let location = device.value["location"] {
                            let name = device.value["name"] ?? "New device"
                            let pid = try await deviceActor.addOrReplaceDevice(location: location, friendlyDeviceName: name, udn: device.key)
                            await deviceActor.refreshDevice(pid)
                        }
                    } catch {
                        WatchConnectivity.logger.error("Unable to add new device \(device.key), \(device.value) with error \(error)")
                    }
                }
            }
        } else {
            WatchConnectivity.logger.warning("Error parsing userInfo as [String: String]: \(String(describing: devices))")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        WatchConnectivity.logger.info("WCSession activated from watchOS with error \(error)")
    }
}
