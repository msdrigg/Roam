import Foundation
import SwiftData
import os

typealias Device = SchemaV1.Device

extension Device: Identifiable {
    public var id: PersistentIdentifier {
        self.persistentModelID
    }
}


extension Device {
    public func powerModeOn() -> Bool {
        return self.powerMode == "PowerOn"
    }
    
    public var displayHash: String {
        "\(name)-\(udn)-\(isOnline())-\(location)-\(String(describing: supportsDatagram))"
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

func getHost(from urlString: String) -> String {
    guard let url = URL(string: addSchemeAndPort(to: urlString)), let host = url.host else {
        return urlString
    }
    return host
}

func addSchemeAndPort(to urlString: String, scheme: String = "http", port: Int = 8060) -> String {
    let urlString = "http://" + urlString.replacing(/^.*:\/\//, with: { _ in "" })
    
    guard let url = URL(string: urlString), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return urlString
    }
    components.scheme = scheme
    components.port = url.port ?? port // Replace the port only if it's not already specified
    
    return (components.string ?? urlString).replacing(/\/*$/, with: {_ in ""}) + "/"
}


func saveDevice(existingDeviceId modelId: PersistentIdentifier, existingUDN: String, newIP deviceIP: String, newDeviceName deviceName: String, deviceActor: DeviceActor) async {
    // Try to get device id
    // Watchos can't check tcp connection, so just do the request
    let cleanedString = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
    let deviceUrl = addSchemeAndPort(to: cleanedString)
    Device.logger.info("Getting device url \(deviceUrl)")
    // Save device id and location early
    do {
        try await deviceActor.updateDevice(
            modelId, name: deviceName, location: deviceUrl, udn: existingUDN
        )
    } catch {
        Device.logger.error("Error early saving device with location \(deviceUrl): \(error)")
    }
    
    let deviceInfo = await fetchDeviceInfo(location: deviceUrl)
    
    // If we get a device with a different UDN, replace the device
    if let udn = deviceInfo?.udn, udn != existingUDN {
        do {
            try await deviceActor.delete(modelId)
            let _ = try await deviceActor.addOrReplaceDevice(
                location: deviceUrl, friendlyDeviceName: deviceName, udn: udn
            )
            
        } catch {
            Device.logger.error("Error saving device \(error)")
        }
        return
    }
    
    do {
        Device.logger.info("Saving device \(deviceUrl) with id \(String(describing: modelId))")
        try await deviceActor.updateDevice(
            modelId,
            name: deviceName,
            location: deviceUrl,
            udn: existingUDN
        )
        Device.logger.info("Saved device \(deviceUrl)")
    } catch {
        Device.logger.error("Error saving device \(error)")
    }
}


func getTestingDevices() -> [Device] {
    return [
        Device(name: "Living Room TV", location: "http://192.168.0.1:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), udn: "TD1"),
        Device(name: "2nd Living Room", location: "http://192.168.0.2:8060/", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), udn: "TD2")
    ]
}


public let devicePreviewContainer: ModelContainer = {
    do {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        Task { @MainActor in
            let context = container.mainContext
            
            let models = getTestingDevices()
            for model in models {
                context.insert(model)
            }
            
            let appLinks = getTestingAppLinks()
            for appLink in appLinks {
                context.insert(appLink)
            }
            
            let messages = getTestingMessages()
            for message in messages {
                context.insert(message)
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


public func fetchSelectedAppLinks(modelContainer: ModelContainer, deviceId: String) async -> [AppLinkAppEntity] {
    let appActor = AppLinkActor(modelContainer: modelContainer)
    do {
        return try await appActor.entities(deviceUid: deviceId)
    } catch {
        os_log("Error getting selected app entities for widget \(error)")
        return []
    }
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
    
    public func allDevices() throws -> [Device] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            })
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        let links = try modelContext.fetch(
            descriptor
        )
        return links
    }

    
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
    
    public func allDeviceEntitiesIncludingDeleted() throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { _ in 
                true
            })
        descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
        let links = try modelContext.fetch(
            descriptor
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
    
    func setSelectedApp(_ appId: PersistentIdentifier) throws {
        Self.logger.info("Updating selectedAt for app with id \(String(describing: appId))")
        
        if let appLink = try? modelContext.existingApp(for: appId) {
            Self.logger.info("Setting appId selected to now")
            appLink.lastSelected = Date.now
            try modelContext.save()
        }
    }

    
    func setSelectedDevice(_ id: PersistentIdentifier) throws {
        Self.logger.info("Updating selectedAt for device with id \(String(describing: id))")
        if let device = try? modelContext.existingDevice(for: id) {
            Self.logger.info("Found device to update with location \(device.location)")
            device.lastSelectedAt = Date.now
            try modelContext.save()
        }
    }

    
    func updateDevice(_ id: PersistentIdentifier, name: String, location: String, udn: String) throws {
        Self.logger.info("Updating device at \(location)")
        if let device = try? modelContext.existingDevice(for: id) {
            Self.logger.info("Found device to update with id \(String(describing: id))")
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
    
    
    func deleteInPast() async throws {
        Self.logger.info("Hard deleting devices")
        let future = Date.now + 60 * 3600
        let distantFuture = Date.distantFuture
        let models = try modelContext.fetch(
            FetchDescriptor<Device>(predicate: #Predicate {
            $0.deletedAt ?? distantFuture < future
        }))
        
        for model in models {
            try await AppLinkActor(modelContainer: modelContainer).deleteEntities(deviceUid: model.udn)
            modelContext.delete(model)
        }
                                                    
        try modelContext.save()
    }
    
    func delete(_ id: PersistentIdentifier) async throws {
        Self.logger.info("Soft deleting device \(String(describing: id))")
        if let device = try? modelContext.existingDevice(for: id) {
            device.deletedAt = .now
            try modelContext.save()
        }
        
        try await deleteInPast()
    }
    
    func existingDevice(id: String) -> DeviceAppEntity? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.udn == id
            }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        matchingIds.propertiesToFetch = []
        do {
            let matchingIds = try self.modelContext.fetchIdentifiers(matchingIds)
            
            if let matchingPid = matchingIds.first {
                 if let device = try self.modelContext.existingDevice(for: matchingPid) {
                     return device.toAppEntity()
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
            
            let udn: String? = device.udn
            let deviceApps = (try? modelContext.fetch(
                FetchDescriptor<AppLink>(
                    predicate: #Predicate {
                        $0.deviceUid == udn
                    }
                )
            )) ?? []
            
            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000 > -MIN_RESCAN_INTERVAL && deviceApps.allSatisfy({ $0.icon != nil}) && deviceApps.count > 0 {
                try? modelContext.save()
                Self.logger.info("Returning early from refresh")
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
        
        Self.logger.info("Refreshing capabilities and apps")
        
        
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
            
            let udn: String = device.udn
            let deviceApps = (try? modelContext.fetch(
                FetchDescriptor<AppLink>(
                    predicate: #Predicate {
                        $0.deviceUid == udn
                    }
                )
            )) ?? []

            if let apps = apps {
                // Remove apps from device that aren't in fetchedApps
                var deviceApps = deviceApps.filter { app in
                    apps.contains { $0.id == app.id }
                }
                
                // Add new apps to device
                for app in apps {
                    if !deviceApps.contains(where: { $0.id == app.id }) {
                        let al = AppLink(id: app.id, type: app.type, name: app.name, deviceUid: device.udn)
                        modelContext.insert(al)
                        deviceApps.append(al)
                    }
                }
                
                // Fetch icons for apps in deviceApps
                for (_, app) in deviceApps.enumerated() {
                    if app.icon == nil {
                        appsNeedingIcons.append(app.id)
                    }
                }
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
                Self.logger.error("Getting device app icon for id \(appId)")
                let iconData = try await fetchAppIcon(location: location, appId: appId)
                appIcons[appId] = iconData
            } catch {
                Self.logger.error("Error getting device app icon \(error)")
            }
        }
        
        
        if let device = try? modelContext.existingDevice(for: id){
            let udn: String? = device.udn

            let deviceApps = (try? modelContext.fetch(
                FetchDescriptor<AppLink>(
                    predicate: #Predicate {
                        $0.deviceUid == udn
                    }
                )
            )) ?? []
            
            if let icon = deviceIcon {
                device.deviceIcon = icon
            }
            for app in appIcons {
                if let deviceApp = deviceApps.first(where: {$0.id == app.key}) {
                    deviceApp.icon = app.value
                }
            }
            try? modelContext.save()
        }
    }
}

private extension ModelContext {
    func existingDevice(for objectID: PersistentIdentifier) throws -> Device? {
        if let registered: Device = registeredModel(for: objectID) {
            return registered
        }
        
        var fetchDescriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.persistentModelID == objectID && $0.deletedAt == nil
            })
        fetchDescriptor.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]
        
        return try fetch(fetchDescriptor).first
    }
    
    func existingApp(for objectID: PersistentIdentifier) throws -> AppLink? {
        if let registered: AppLink = registeredModel(for: objectID) {
            return registered
        }
        
        var fetchDescriptor = FetchDescriptor<AppLink>(
            predicate: #Predicate {
                $0.persistentModelID == objectID
            })
        fetchDescriptor.propertiesToFetch = [\.name, \.lastSelected, \.id, \.deviceUid]
        
        return try fetch(fetchDescriptor).first
    }

}
