import Foundation
import SwiftData
import os

@Model
public final class Device: Identifiable, Hashable {
    @Attribute(.unique, originalName: "id") public var udn: String
    public var name: String
    public var location: String
    
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    public var lastScannedAt: Date?
    public var lastSentToWatch: Date?
    public var deletedAt: Date?
    
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
    public var apps: [AppLink]?
    
    public var appsSorted: [AppLink] {
        apps?.sorted(by: {
            if $0.lastSelected ?? .distantPast == $1.lastSelected ?? .distantPast {
                return $0.name < $1.name
            }
            return ($0.lastSelected ?? Date.distantPast) > ($1.lastSelected ?? Date.distantPast)
        }) ?? []
    }
    
    public var id: PersistentIdentifier {
        self.persistentModelID
    }
    
    public init(name: String, location: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, udn: String, apps: [AppLink] = []) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.udn = udn
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
        Device(name: "Living Room TV", location: "http://192.168.0.1:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), udn: "TD1", apps: apps),
        Device(name: "2nd Living Room", location: "http://192.168.0.2:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), udn: "TD2", apps: [])
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
                identifiers.contains($0.udn) && $0.deletedAt == nil
            })
        )
        
        return links.map {$0.toAppEntity()}
    }
    
    public func entities(matching string: String) throws -> [DeviceAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<Device>(predicate: #Predicate {
                $0.name.contains(string) && $0.deletedAt == nil
            })
        )
        return links.map {$0.toAppEntity()}
    }
    
    public func allDeviceEntities() throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            })
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        let links = try modelContext.fetch(
            descriptor
        )
        return links.map {$0.toAppEntity()}
    }
    
    
    func updateDevice(_ id: PersistentIdentifier, name: String, location: String, udn: String) throws {
        Self.logger.info("Updating device at \(location)")
        if let device = try? modelContext.existingDevice(for: id) {
            Self.logger.info("Found device to pudate with id \(String(describing: id))")
            device.location = location
            device.name = name
            device.udn = udn
            device.lastSentToWatch = nil
            try modelContext.save()
        }
        Self.logger.info("Updated device at \(location)")
    }
    
    func addOrReplaceDevice(location: String, friendlyDeviceName: String, udn: String) throws -> PersistentIdentifier {
        Self.logger.info("Adding device at \(location)")
        let device = Device(
            name: friendlyDeviceName,
            location: location,
            lastOnlineAt: Date.now,
            udn: udn
        )
        modelContext.insert(device)
        
        try modelContext.save()
        
        Self.logger.info("Added device \(String(describing: device.persistentModelID))")
        
        return device.persistentModelID
    }
    
    func sentToWatch(deviceId: PersistentIdentifier) {
        do {
            if let device = try modelContext.existingDevice(for: deviceId) {
                device.lastSentToWatch = Date.now
                try modelContext.save()
            }
        } catch {
            Self.logger.warning("Error marking device \(String(describing: deviceId)) as sent to watch \(error)")
        }
    }
    
    func watchPossiblyDead() {
        let entities = (try? self.allDeviceEntities()) ?? []
        for entity in entities {
            do {
                if let device = try modelContext.existingDevice(for: entity.modelId) {
                    device.lastSentToWatch = Date.now
                    try modelContext.save()
                }
            } catch {
                Self.logger.warning("Error marking device \(String(describing: entity.modelId)) as not sent to watch")
            }
        }
    }
    
    
    func deleteInPast() throws {
        Self.logger.info("Hard deleting devices")
        let future = Date.now + 60 * 3600
        let distantFuture = Date.distantFuture
        try modelContext.delete(model: Device.self, where: #Predicate {
            $0.deletedAt ?? distantFuture < future
        }, includeSubclasses: true)
        
        try modelContext.save()
    }
    
    func delete(_ id: PersistentIdentifier) throws {
        Self.logger.info("Soft deleting device \(String(describing: id))")
        if let device = try? modelContext.existingDevice(for: id) {
            device.deletedAt = .now
            try modelContext.save()
        }
        
        try deleteInPast()
    }
    
    func existingDevice(id: String) -> DeviceAppEntity? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        do {
            let matchingIds = try self.modelContext.fetchIdentifiers(matchingIds)
            
            for pid in matchingIds {
                if let device = try self.modelContext.existingDevice(for: pid) {
                    if device.udn == id {
                        return device.toAppEntity()
                    }
                }
            }
            
            return nil
        } catch {
            Self.logger.error("Error checking if device exists \(id): \(error)")
            return nil
        }
        
    }
    
    
    func deviceExists(id: String) -> Bool {
        return self.existingDevice(id: id) != nil
    }
    
    
    func fetchSelectedDeviceAppEntity() -> DeviceAppEntity? {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        descriptor.relationshipKeyPathsForPrefetching = [\.apps]
        descriptor.fetchLimit = 1
        
        let selectedDevice: Device? = try? modelContext.fetch(descriptor).first
        
        return selectedDevice?.toAppEntity()
    }
    
    func refreshDevice(_ id: PersistentIdentifier) async {
        guard let location = (try? modelContext.existingDevice(for: id))?.location  else {
            Self.logger.error("Trying to refresh device that doeesn't exist \(String(describing: id))")
            return
        }
        
        guard let deviceInfo = await fetchDeviceInfo(location: location) else {
            Self.logger.info("Failed to get device info \(location)")
            return
        }
        
        if let device = try? modelContext.existingDevice(for: id) {
            if device.udn.starts(with: "roam:newdevice-") {
                device.udn = deviceInfo.udn
            } else if deviceInfo.udn != device.udn {
                return
            }
            
            device.lastOnlineAt = Date.now
            
            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000 > -MIN_RESCAN_INTERVAL && (device.apps?.allSatisfy { $0.icon != nil} ?? true) {
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
            
            try? modelContext.save()
        }
        
        
        
        var capabilities: DeviceCapabilities? = nil
        do {
            capabilities = try await fetchDeviceCapabilities(location: location)
        } catch {
            Self.logger.error("Error getting capabilities \(error)")
        }
        
        var apps: [AppLinkAppEntity]? = nil
        do {
            apps = try await fetchDeviceApps(location: location)
        } catch {
            Self.logger.error("Error getting device apps \(error)")
        }
        
        var deviceNeedsIcon = false
        var appsNeedingIcons: [String] = []
        if let device = try? modelContext.existingDevice(for: id) {
            deviceNeedsIcon = device.deviceIcon == nil
            if let capabilities = capabilities {
                device.rtcpPort = capabilities.rtcpPort
                device.supportsDatagram = capabilities.supportsDatagram
            }
            
            if let apps = apps {
                // Remove apps from device that aren't in fetchedApps
                var deviceApps = device.apps?.filter { app in
                    apps.contains { $0.id == app.id }
                } ?? []
                
                // Add new apps to device
                for app in apps {
                    if !deviceApps.contains(where: { $0.id == app.id }) {
                        deviceApps.append(AppLink(id: app.id, type: app.type, name: app.name))
                    }
                }
                
                // Fetch icons for apps in deviceApps
                for (_, app) in deviceApps.enumerated() {
                    if app.icon == nil {
                        appsNeedingIcons.append(app.id)
                    }
                }
                
                // Set apps to the new apps
                device.apps = deviceApps
            }
            
            try? modelContext.save()
        }
        
        var deviceIcon: Data? = nil
        if deviceNeedsIcon {
            Self.logger.info("Getting icon for device \(location)")
            do {
                deviceIcon = try await tryFetchDeviceIcon(location: location)
            } catch {
                Self.logger.warning("Error getting device icon \(error)")
            }
        }
        
        
        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                Self.logger.error("Getting device app icon ")
                let iconData = try await fetchAppIcon(location: location, appId: appId)
                appIcons[appId] = iconData
            } catch {
                Self.logger.error("Error getting device app icon \(error)")
            }
        }
        
        
        if let device = try? modelContext.existingDevice(for: id){
            if let icon = deviceIcon {
                device.deviceIcon = icon
            }
            for app in appIcons {
                if let deviceApp = device.apps?.first(where: {$0.id == app.key}) {
                    deviceApp.icon = app.value
                }
            }
            try? modelContext.save()
        }
    }
}

private extension ModelContext {
    func existingDevice(for objectID: PersistentIdentifier)
    throws -> Device? {
        if let registered: Device = registeredModel(for: objectID) {
            return registered
        }
        
        var fetchDescriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.persistentModelID == objectID && $0.deletedAt == nil
            })
        fetchDescriptor.relationshipKeyPathsForPrefetching = [\.apps]
        fetchDescriptor.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]
        
        return try fetch(fetchDescriptor).first
    }
}
