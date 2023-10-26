import Foundation
import SwiftData
import os

@Model
public final class Device: Identifiable, Hashable {
    @Attribute(.unique) public var id: String
    public var name: String
    public var location: String
    
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    public var lastScannedAt: Date?
    
    // DisplayOff or PowerOn or Suspend
    public var powerMode: String?
    public var networkType: String?
    public var wifiMAC: String?
    public var ethernetMAC: String?
    
    public var rtcpPort: UInt16?
    public var supportsDatagram: Bool?
    
    @Attribute(.externalStorage) public var deviceIcon: Data?
    // Associate 0..n Apps with Device
    @Relationship(deleteRule: .nullify)
    public var apps: [AppLink] = [AppLink]()
    
    public var appsSorted: [AppLink] {
       apps.sorted(by: {
           if $0.lastSelected ?? .distantPast == $1.lastSelected ?? .distantPast {
               return $0.name < $1.name
           }
          return ($0.lastSelected ?? Date.distantPast) > ($1.lastSelected ?? Date.distantPast)
        })
    }
    
    public init(name: String, location: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, id: String, apps: [AppLink] = []) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.id = id
        self.location = location
    
        self.apps = apps
    }
    
    public func powerModeOn() -> Bool {
        return self.powerMode == "PowerOn"
    }
    
    public func isOnline() -> Bool {
        guard let lastOnlineAt = self.lastOnlineAt else {
             return false
         }
        return Date().timeIntervalSince(lastOnlineAt) < 60
    }
    
    func usingMac() -> String? {
        if networkType == "ethernet" {
            return ethernetMAC
        } else {
            return wifiMAC
        }
    }
}

public func getTestingDevices() -> [Device] {
    let apps = getTestingAppLinks()
    
    return [
        Device(name: "Living Room TV", location: "http://192.168.0.1:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), id: "TD1", apps: apps),
        Device(name: "2nd Living Room", location: "http://192.168.0.2:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), id: "TD2", apps: [])
    ]
}

public let devicePreviewContainer: ModelContainer = {
    do {
        let container = try ModelContainer(for: Device.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        Task { @MainActor in
            let context = container.mainContext
            
            let models = getTestingDevices()
            for model in models {
                context.insert(model)
            }
        }
        return container
    } catch {
        fatalError("Failed to create container with error: \(error.localizedDescription)")
    }
}()

public func getSharedModelContainer() throws -> ModelContainer {
    let schema = Schema([
        AppLink.self,
        Device.self,
    ])
    
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.com.msdrigg.roam"))
    
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}

public func fetchSelectedDevice(modelContainer: ModelContainer) async -> DeviceAppEntity? {
    let deviceActor = DeviceActor(modelContainer: modelContainer)
    return await deviceActor.fetchSelectedDeviceAppEntity()
}

// Models shouldn't be sendable
@available(*, unavailable)
extension Device: Sendable {}


@ModelActor
actor DeviceActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceActor.self)
    )
    
    // Only refresh every 1 hour
    private let MIN_RESCAN_INTERVAL: TimeInterval = 3600

    
    public func entities(for identifiers: [DeviceAppEntity.ID]) throws -> [DeviceAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<Device>(predicate: #Predicate {
                identifiers.contains($0.id)
            })
        )
        
        return links.map {$0.toAppEntity()}
    }
    
    public func entities(matching string: String) throws -> [DeviceAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<Device>(predicate: #Predicate {
                $0.name.contains(string)
            })
        )
        return links.map {$0.toAppEntity()}
    }
    
    public func suggestedEntities() throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>()
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        let links = try modelContext.fetch(
            descriptor
        )
        return links.map {$0.toAppEntity()}
    }


    func addDevice(location: String, friendlyDeviceName: String, id: String) throws {
        modelContext.insert(Device(
            name: friendlyDeviceName,
            location: location,
            lastOnlineAt: Date.now,
            id: id
        ))

        try modelContext.save()
    }
    
    func updateDevice(_ id: PersistentIdentifier, name: String, location: String) throws {
        if let device = self[id, as: Device.self] {
            device.location = location
            device.name = name
            try modelContext.save()
        }
    }
    
    func delete(_ id: PersistentIdentifier) throws {
        if let device = self[id, as: Device.self] {
            modelContext.delete(device)
            try modelContext.save()
        }
    }
    
    
    func deviceExists(id: String) -> Bool {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate<Device> { $0.id == id }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        
        return (try? modelContext.fetchCount(matchingIds)) ?? 0 >= 1
    }

    
    func findDeviceById(id: String) -> DeviceAppEntity? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate<Device> { $0.id == id }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        matchingIds.relationshipKeyPathsForPrefetching = [\.apps]
        
        let existingDevices: [Device]? = try? modelContext.fetch(matchingIds)
        
        return existingDevices?.first?.toAppEntity()
    }
    
    func fetchSelectedDeviceAppEntity() -> DeviceAppEntity? {
        var descriptor = FetchDescriptor<Device>()
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        descriptor.relationshipKeyPathsForPrefetching = [\.apps]
        descriptor.fetchLimit = 1
        
        let selectedDevice: Device? = try? modelContext.fetch(descriptor).first
        
        return selectedDevice?.toAppEntity()
    }
    
    func refreshDevice(_ id: String) async {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate { $0.id == id }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        matchingIds.relationshipKeyPathsForPrefetching = [\.apps]
        
        let existingDevice: Device? = try? modelContext.fetch(matchingIds).first
        
        if let device = existingDevice {
            guard let deviceInfo = await fetchDeviceInfo(location: device.location) else {
                Self.logger.info("Failed to get device info \(device.location)")
                return
            }
            if deviceInfo.udn != id {
                return
            }
            
            device.lastOnlineAt = Date.now
            
            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000 > -MIN_RESCAN_INTERVAL && (device.apps.allSatisfy { $0.icon != nil}) {
                try? modelContext.save()
                return
            }
            device.lastScannedAt = Date.now
            
            device.ethernetMAC = deviceInfo.ethernetMac
            device.wifiMAC = deviceInfo.wifiMac
            device.networkType = deviceInfo.networkType
            device.powerMode = deviceInfo.powerMode
            if device.name == "New device" {
                if let newName = deviceInfo.friendlyDeviceName {
                    device.name = newName
                }
            }
            
            do {
                let capabilities = try await fetchDeviceCapabilities(location: device.location)
                device.rtcpPort = capabilities.rtcpPort
                device.supportsDatagram = capabilities.supportsDatagram
                
            } catch {
                Self.logger.error("Error getting capabilities \(error)")
            }
            
            do {
                let apps = try await fetchDeviceApps(location: device.location)
                
                // Remove apps from device that aren't in fetchedApps
                device.apps = device.apps.filter { app in
                    apps.contains { $0.id == app.id }
                }
                
                // Add new apps to device
                var deviceApps = device.apps
                for app in apps {
                    if !deviceApps.contains(where: { $0.id == app.id }) {
                        deviceApps.append(AppLink(id: app.id, type: app.type, name: app.name))
                    }
                }
                // Fetch icons for apps in deviceApps
                for (index, app) in deviceApps.enumerated() {
                    if app.icon == nil {
                        do {
                            Self.logger.error("getting device app icon ")
                            let iconData = try await fetchAppIcon(location: device.location, appId: app.id)
                            deviceApps[index].icon = iconData
                        } catch {
                            Self.logger.error("Error getting device app icon \(error)")
                        }
                    } else {
                        
                        Self.logger.error("Not getting icon for app \(app.id) because icon exists \(String(describing: app.icon))")
                    }
                }
                
                device.apps = deviceApps
            } catch {
                Self.logger.error("Error getting device apps \(error)")
            }
            if device.deviceIcon == nil {
                Self.logger.info("Getting icon for device \(device.id)")
                do {
                    let iconData = try await tryFetchDeviceIcon(location: device.location)
                    device.deviceIcon = iconData
                } catch {
                    Self.logger.warning("Error getting device icon \(error)")
                }
            }
        } else {
            Self.logger.error("Trying to refresh device that doeesn't exist \(id)")
        }
    }
}

