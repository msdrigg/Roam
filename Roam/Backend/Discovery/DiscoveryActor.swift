import SwiftData
import Foundation
import os
import XMLCoder
import Network
import SwiftUI

actor DeviceDiscoveryActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceDiscoveryActor.self)
    )
    
    let deviceActor: DeviceActor
    
    init(modelContainer: ModelContainer) {
        deviceActor = DeviceActor(modelContainer: modelContainer)
    }
    
    func refreshDevice(id: String) async {
        await deviceActor.refreshDevice(id) 
    }
    
    func addDevice(location: String) async {
        Self.logger.debug("Adding device at \(location)")
        
        guard let deviceInfo = await fetchDeviceInfo(location: location) else {
            Self.logger.error("Error getting device info for found device \(location)")
            return
        }
        
        if await deviceActor.deviceExists(id: deviceInfo.udn) {
            Self.logger.info("Trying to add device that already exists with UDN \(deviceInfo.udn)")
            return
        }
        
        
        
        do {
            try await deviceActor.addDevice(location: location, friendlyDeviceName: deviceInfo.friendlyDeviceName ?? "New device", id: deviceInfo.udn)
            Self.logger.info("Saved new device \(deviceInfo.udn), \(location)")
            await self.refreshDevice(id: deviceInfo.udn)
        } catch {
            Self.logger.error("Error saving device with id \(deviceInfo.udn) \(location): \(error)")
        }
    }
    
    func refreshSelectedDeviceContinually(id: String) async {
        // Refresh every 30 seconds
        Self.logger.debug("Refreshing device \(id)")
        await self.refreshDevice(id: id)
        for await _ in interval(time: 30) {
            Self.logger.debug("Refreshing device \(id)")
            await self.refreshDevice(id: id)
        }
    }
    
    func scanIPV4Once() async {
        // Don't scan IPV4 in previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        
        
        let MAX_CONCURRENT_SCANNED = 37
        
        let scannableInterfaces = await allAddressedInterfaces().filter{ $0.isIPV4 && $0.isEthernetLike }
        let sem = AsyncSemaphore(value: MAX_CONCURRENT_SCANNED)
        
        await withDiscardingTaskGroup { taskGroup in
            for iface in scannableInterfaces {
                let range = iface.scannableIPV4NetworkRange
                if range.count > 1024 {
                    Self.logger.error("IPV4 range has \(range.count) items. Max is 1024")
                } else {
                    Self.logger.debug("Manually scanning \(range.count) devices in network range \(range)")
                }
                
                for ipAddress in range {
                    taskGroup.addTask {
                        try? await sem.waitUnlessCancelled()
                        if Task.isCancelled {
                            return
                        }
                        defer {
                            sem.signal()
                        }
                        
                        let location = "http://\(ipAddress.addressString):8060/"
                        Self.logger.trace("Scanning address \(ipAddress.addressString)")
                        
                        if !(await canConnectTCP(location: location, timeout: 1.2, interface: iface.nwInterface)) {
                            // This device is a potential item
                            return
                        }
                        
                        await self.addDevice(location: location)
                    }
                }
            }
        }
    }
    
    func scanSSDPContinually() async {
        let stream: AsyncThrowingStream<SSDPService, any Error>
        do {
            stream = try scanDevicesContinually()
        } catch {
            Self.logger.error("Error getting async device stream \(error)")
            return
        }
        
        await withDiscardingTaskGroup { taskGroup in
            do {
                for try await device in stream {
                    Self.logger.info("Found SSDP service at \(device.location ?? "--")")
                    if let location = device.location {
                        taskGroup.addTask {
                            await self.addDevice(location: location)
                        }
                    }
                }
            } catch {
                Self.logger.error("Error in SSDP stream \(error)")
            }
        }
    }
}


