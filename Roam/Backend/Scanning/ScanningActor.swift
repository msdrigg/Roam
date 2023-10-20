import SwiftData
import NIO
import Foundation
import os
import XMLCoder
import Network
import SwiftUI

// Only refresh every 1 hour
let MIN_RESCAN_TIME: TimeInterval = 3600

@ModelActor
actor DeviceScanningActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceScanningActor.self)
    )
    
    var bootstrap: DatagramBootstrap? = nil
    
    func findDeviceById(id: String) -> Device? {
        return Device.findById(id: id, context: modelContext)
    }
    
    func refreshDevice(id: String) async {
        let existingDevice = findDeviceById(id: id)
        if let device = existingDevice {
            guard let deviceInfo = await fetchDeviceInfo(location: device.location) else {
                Self.logger.info("Failed to get device info \(device.location)")
                return
            }
            if deviceInfo.udn != id {
                return
            }
            
            device.lastOnlineAt = Date.now
            
            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000 > -MIN_RESCAN_TIME && (device.apps?.allSatisfy { $0.icon != nil} ?? true) {
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
                device.apps = device.apps?.filter { app in
                    apps.contains { $0.id == app.id }
                }
                
                // Add new apps to device
                var deviceApps = device.apps ?? []
                for app in apps {
                    if !deviceApps.contains(where: { $0.id == app.id }) {
                        deviceApps.append(app)
                    }
                }
                // Fetch icons for apps in deviceApps
                for (index, app) in deviceApps.enumerated() {
                    if app.icon == nil {
                        do {
                            let iconData = try await fetchAppIcon(location: device.location, appId: app.id)
                            deviceApps[index].icon = iconData
                        } catch {
                            Self.logger.error("Error getting device app icon \(error)")
                        }
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
                    Self.logger.debug("Got icon!")
                    device.deviceIcon = iconData
                } catch {
                    Self.logger.warning("Error getting device icon \(error)")
                }
            }
        }
    }
    
    func addDevice(location: String) async {
        Self.logger.debug("Discovered device! \(location)")

        guard let deviceInfo = await self.fetchDeviceInfo(location: location) else {
            Self.logger.error("Error getting device info for found device \(location)")
            return
        }
        
        if findDeviceById(id: deviceInfo.udn) != nil{
            Self.logger.info("Trying to add device that already exists with UDN \(deviceInfo.udn)")
            return
        }
        
        let modelContext = ModelContext(modelContainer)
        modelContext.insert(Device(
            name: deviceInfo.friendlyDeviceName ?? "New device",
            location: location,
            lastOnlineAt: Date.now,
            id: deviceInfo.udn
        ))

        
        do {
            try modelContext.save()
            Self.logger.info("Saved new device \(deviceInfo.udn), \(location)")
            await self.refreshDevice(id: deviceInfo.udn)
        } catch {
            Self.logger.error("Error saving device with id \(deviceInfo.udn) \(location): \(error)")
        }
    }
    
    func fetchDeviceInfo(location: String) async -> DeviceInfo? {
        let deviceInfoURL = "\(location)/query/device-info"
        guard let url = URL(string: deviceInfoURL) else {
            Self.logger.error("Unable to get device info due to bad url \(deviceInfoURL)")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let xmlString = String(data: data, encoding: .utf8) {
                let decoder = XMLDecoder()
                decoder.keyDecodingStrategy = .convertFromKebabCase
                do {
                    Self.logger.debug("Trying to decode DeviceInfo from:\n\(xmlString.prefix(20))...")
                    let info = try decoder.decode(DeviceInfo.self, from: Data(xmlString.utf8))
                    Self.logger.debug("Decoded DeviceInfo from: \(String(describing: info).prefix(20))...")
                    return info
                } catch {
                    Self.logger.error("Error decoding DeviceInfo response \(error)")
                }
            }
        } catch {
            Self.logger.error("Error getting device info: \(error)")
        }
        return nil
    }
    
    func refreshSelectedDeviceContinually(id: String) async {
        let timeout: TimeAmount = .seconds(30)
        
        while !Task.isCancelled {
            Self.logger.debug("Refreshing device \(id)")
            await self.refreshDevice(id: id)
        
            let jitter = Int64.random(in: 0..<500 * 100_000) // Random jitter
            let timeoutNanos = UInt64(timeout.nanoseconds + jitter)
            try? await Task.sleep(nanoseconds: timeoutNanos)
        }
    }
    
    func scanIPV4Once() async {
        // Don't scan IPV4 in previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }

        
        let MAX_CONCURRENT_SCANNED = 67
        
        let scannableInterfaces = await getAllInterfaces().filter{ $0.isIPV4 && $0.isEthernetLike }
        let sem = AsyncSemaphore(value: MAX_CONCURRENT_SCANNED)
        
        await withDiscardingTaskGroup { taskGroup in
            for iface in scannableInterfaces {
                guard let range = iface.scannableIPV4NetworkRange else {
                    continue
                }
                if range.count > 1024 {
                    Self.logger.error("IPV4 range has \(range.count) items. Max is 1024")
                } else {
                    Self.logger.debug("Manually scanning \(range.count) devices in network range \(range)")
                }
                
                for ipInt in range {
                    print("Scanning \(uInt32ToIP(ipInt))")
                    taskGroup.addTask {
                        try? await sem.waitUnlessCancelled()
                        if Task.isCancelled {
                            return
                        }
                        defer {
                            sem.signal()
                        }
                        
                        let ipAddr = uInt32ToIP(ipInt)
                        let location = "http://\(ipAddr):8060/"
                        print("Scanning address \(ipAddr)")
                        
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
        if self.bootstrap == nil {
            self.bootstrap = DatagramBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_BROADCAST), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(DatagramHandler(scanner: self))
                }
        }
        while !Task.isCancelled {
            var channel: Channel? = nil
            do {
                channel = try await bootstrap?
                    .bind(to: .init(ipAddress: "0.0.0.0", port: 0))
                    .get()
            } catch {
                Self.logger.error("Error getting channel: \(error)")
            }
            guard let channel = channel else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            var timeout: TimeAmount = .seconds(2)
            while !Task.isCancelled {
                let jitter = Int64.random(in: 0..<500 * 100_000) // Random jitter
                let timeoutNanos = UInt64(timeout.nanoseconds + jitter)
                try? await Task.sleep(nanoseconds: timeoutNanos)
                timeout = max(min(.seconds(30), .nanoseconds(timeout.nanoseconds * 2)), .seconds(2))
                do {
                    let destAddress = try SocketAddress(ipAddress: "239.255.255.250", port: 1900)
                    
                    let message = "M-SEARCH * HTTP/1.1\r\n" +
                    "Host: 239.255.255.250:1900\r\n" +
                    "Man: \"ssdp:discover\"\r\n" +
                    "ST: roku:ecp\r\n\r\n"
                    var buffer = channel.allocator.buffer(capacity: message.utf8.count)
                    buffer.writeString(message)
                    try await channel.writeAndFlush(AddressedEnvelope(remoteAddress: destAddress, data: buffer)).get()
                    Self.logger.debug("Sent discovery packet")
                } catch {
                    Self.logger.error("Error sending discovery packet: \(error)")
                    continue
                }
            }
            do {
                try await channel.close(mode: .all)
            } catch {
                Self.logger.error("Error closing channel \(error)")
            }
        }
    }
}


struct DeviceInfo: Codable {
    let powerMode: String?
    let networkType: String?
    let ethernetMac: String?
    let wifiMac: String?
    let friendlyDeviceName: String?
    let udn: String
    
    func isPowerOn() -> Bool {
        return powerMode == "PowerOn"
    }
}

class DatagramHandler: ChannelInboundHandler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DatagramHandler.self)
    )
    
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    let scanner: DeviceScanningActor
    
    init(scanner: DeviceScanningActor) {
        self.scanner = scanner
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let buffer = envelope.data
        guard let response = buffer.getString(at: 0, length: buffer.readableBytes) else {
            Self.logger.error("Error parsing discovery packet into string")
            return
        }
        
        // We are searching for a packet like this:
        // HTTP/1.1 200 OK
        // Cache-Control: max-age=3600
        // ST: roku:ecp
        // Location: http://192.168.1.134:8060/
        // USN: uuid:roku:ecp:P0A070000007
        Self.logger.debug("Got discovery packet \(response.prefix(20))...")
        var parsedResponse = [String: String]()
        
        let headerRegex = try! Regex<(Substring, Substring, Substring)>("^([^\r\n:]+): (.*)$").anchorsMatchLineEndings()
        
        for match in response.matches(of: headerRegex) {
            let (_, key, value) = match.output
            parsedResponse[key.uppercased()] = value.lowercased()
        }
        
        Self.logger.debug("Found discovery responses \(parsedResponse.keys)")
        
        guard let location = parsedResponse["LOCATION"] else {
            return
        }
        
        Task {
            await scanner.addDevice(location: location)
        }
    }
}

struct Root: Codable {
    let device: DeviceIconDescription
}

struct DeviceIconDescription: Codable {
    let iconList: IconList
}

struct IconList: Codable {
    let icon: [Icon]
}

struct Icon: Codable {
    let url: String
}

enum FetchDeviceIconError: Error {
    case badURL(String)
    case badIconURL(String)
    case noIconsListed
}

func tryFetchDeviceIcon(location: String) async throws -> Data {
    // Fetch device details
    guard let url = URL(string: location) else {
        throw FetchDeviceIconError.badURL(location)
    }
    let (data, _) = try await URLSession.shared.data(from: url)
    
    // Decode XML to Root object
    let decoder = XMLDecoder()
    let root = try decoder.decode(Root.self, from: data)
    
    // Fetch device icon data
    if let iconURL = root.device.iconList.icon.first?.url {
        guard let fullIconURL = URL(string: "\(location)/\(iconURL)") else {
            throw FetchDeviceIconError.badIconURL("\(location)/\(iconURL)")
        }
        let (iconData, _) = try await URLSession.shared.data(from: fullIconURL)
        return iconData
    } else {
        throw FetchDeviceIconError.noIconsListed
    }
}

struct AudioDevice: Codable {
    let capabilities: Capabilities
    let rtpInfo: RtpInfo?
    
    enum CodingKeys: String, CodingKey {
        case capabilities
        case rtpInfo = "rtp-info"
    }
}

struct Capabilities: Codable {
    let allDestinations: String?
    
    enum CodingKeys: String, CodingKey {
        case allDestinations = "all-destinations"
    }
}

struct RtpInfo: Codable {
    let rtcpPort: UInt16?
    
    enum CodingKeys: String, CodingKey {
        case rtcpPort = "rtcp-port"
    }
}

struct DeviceCapabilities {
    let supportsDatagram: Bool
    let rtcpPort: UInt16?
}

func fetchDeviceCapabilities(location: String) async throws -> DeviceCapabilities {
    let url = URL(string: "\(location)/query/audio-device")!
    let (data, _) = try await URLSession.shared.data(from: url)
    
    let decoder = XMLDecoder()
    let audioDevice = try decoder.decode(AudioDevice.self, from: data)
    
    let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
    let rtcpPort = audioDevice.rtpInfo?.rtcpPort
    
    return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
}

struct Apps: Codable {
    let app: [AppLink]
}

func fetchDeviceApps(location: String) async throws -> [AppLink] {
    let url = URL(string: "\(location)/query/apps")!
    let (data, _) = try await URLSession.shared.data(from: url)
    
    let decoder = XMLDecoder()
    let apps = try decoder.decode(Apps.self, from: data)
    
    return apps.app
}

func fetchAppIcon(location: String, appId: String) async throws -> Data {
    let url = URL(string: "\(location)/query/icon/\(appId)")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}
