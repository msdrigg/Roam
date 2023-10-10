import SwiftData
import NIO
import Foundation
import os

final actor DeviceControllerActor: ModelActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceControllerActor.self)
    )
    
    let modelContainer: ModelContainer
    let modelExecutor: any ModelExecutor
    let group: MultiThreadedEventLoopGroup
    var bootstrap: DatagramBootstrap? = nil
    var timeout: TimeAmount = .seconds(1)
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    func itemFound(location: String, id: String) async {
        Self.logger.debug("Discovered device! \(location) \(id)")
        let modelContext = ModelContext(modelContainer)
        
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate { $0.id == id }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        
        let existingDevices: [Device] = (try? modelContext.fetch(matchingIds)) ?? []
        
        
        
        if let device = existingDevices.first {
            device.location = location
            device.lastOnlineAt = Date.now
            
            if let deviceInfo = await self.fetchDeviceInfo(location: location) {
                device.ethernetMAC = deviceInfo.ethernetMAC
                device.wifiMAC = deviceInfo.wifiMAC
                device.networkType = deviceInfo.networkType
                device.powerMode = deviceInfo.powerMode
            }
        } else {
            let deviceInfo = await self.fetchDeviceInfo(location: location)
            
            let newDevice = Device(
                name: deviceInfo?.deviceName ?? "New device",
                location: location,
                lastOnlineAt: Date.now,
                id: id
            )
            if let deviceInfo = deviceInfo {
                newDevice.ethernetMAC = deviceInfo.ethernetMAC
                newDevice.wifiMAC = deviceInfo.wifiMAC
                newDevice.networkType = deviceInfo.networkType
                newDevice.powerMode = deviceInfo.powerMode
            }
            Self.logger.info("Discovered new device \(newDevice.id), \(newDevice.location)")
            modelContext.insert(newDevice)
        }
        
        try? modelContext.save()
    }
    
    
    deinit {
        self.group.shutdownGracefully {_ in
            Self.logger.info("Shutdown group gracefully")
        }
    }
    
    func wakeOnLAN(macAddress: String) async {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_BROADCAST), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(WOLHandler(macAddress: macAddress))
            }
        var channel: Channel
        do {
            channel = try await bootstrap
                .bind(to: .init(ipAddress: "0.0.0.0", port: 0))
                .get()
        } catch {
            Self.logger.error("Error getting channel for wol with mac \(macAddress): \(error)")
            return;
        }
        var buffer = channel.allocator.buffer(capacity: 102)
        let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else { return }
        
        for _ in 0..<6 {
            buffer.writeInteger(UInt8(0xFF))
        }
        
        for _ in 0..<16 {
            buffer.writeBytes(macBytes)
        }
        
        guard let address = try? SocketAddress(ipAddress: "255.255.255.255", port: 9) else {
            return
        }
        do {
            try await channel.writeAndFlush(AddressedEnvelope(remoteAddress: address, data: buffer))
            Self.logger.info("Sent wol packet")
            try await channel.close(mode: .all)
        } catch {
            Self.logger.error("Error sending wol packet for mac \(macAddress): \(error)")
            return
        }
    }
    
    func openApp(location: String, app: AppLink) {
        guard let url = URL(string: "\(location)/launch/\(app.id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Self.logger.info("Opened app \(app.name) to with location \(location)")
                } else {
                    Self.logger.error("Error opening app \(app.name), \(app.id) at location \(location): \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
        
    }
    
    func powerToggleDevice(device: Device) async {
        Self.logger.debug("Toggling power for device \(device.id)")
        // Attempt WOL
        if let mac = device.usingMac() {
            Self.logger.debug("Sending wol packet to \(mac)")
            await wakeOnLAN(macAddress: mac)
        }
        // Attempt checking the device power mode
        if let deviceInfo = await fetchDeviceInfo(location: device.location) {
            if deviceInfo.isPowerOn() {
                Self.logger.debug("Attempting to wakeup device")
                await sendKeyToDevice(location: device.location, key: "poweroff")
            } else {
                Self.logger.debug("Attempting to turn off device")
                await sendKeyToDevice(location: device.location, key: "poweron")
            }
        }
    }
    
    func fetchDeviceInfo(location: String) async -> DeviceInfo? {
        let url = URL(string: "\(location)/query/device-info")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let xmlString = String(data: data, encoding: .utf8) {
                let powerModeValue = extractValue(from: xmlString, tag: "power-mode")
                let networkTypeValue = extractValue(from: xmlString, tag: "network-type")
                let ethernetMACValue = extractValue(from: xmlString, tag: "ethernet-mac")
                let wifiMACValue = extractValue(from: xmlString, tag: "wifi-mac")
                let deviceName = extractValue(from: xmlString, tag: "friendly-device-name")
                
                return DeviceInfo(powerMode: powerModeValue, networkType: networkTypeValue, ethernetMAC: ethernetMACValue, wifiMAC: wifiMACValue, deviceName: deviceName)
            }
        } catch {
            Self.logger.error("Error getting device info: \(error)")
        }
        return nil
    }
    
    
    func sendKeyToDevice(location: String, key: String) async {
        let url = URL(string: "\(location)/keypress/\(key)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Self.logger.debug("Sent \(key) to \(location)")
                } else {
                    Self.logger.error("Error sending \(key) to \(location): \(httpResponse.statusCode)")
                }
            }
        } catch {
            Self.logger.error("Error sending \(key) to \(location): \(error)")
        }
    }
    
    
    
    func scanContinually() async {
        if self.bootstrap == nil {
            self.bootstrap = DatagramBootstrap(group: group)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_BROADCAST), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(DatagramHandler(scanner: self))
                }
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            var channel: Channel? = nil
            do {
                channel = try await bootstrap?
                    .bind(to: .init(ipAddress: "0.0.0.0", port: 0))
                    .get()
            } catch {
                Self.logger.error("Error getting channel: \(error)")
            }
            guard let channel = channel else {
                continue
            }
            
            
            let message = """
M-SEARCH * HTTP/1.1
Host: 239.255.255.250:1900
Man: "ssdp:discover"
ST: roku:ecp

"""
            var buffer = channel.allocator.buffer(capacity: message.utf8.count)
            buffer.writeString(message)
            
            while !Task.isCancelled {
                timeout = min(.seconds(30), .nanoseconds(timeout.nanoseconds * 2))
                do {
                    let destAddress = try SocketAddress(ipAddress: "239.255.255.250", port: 1900)
                    try await channel.writeAndFlush(AddressedEnvelope(remoteAddress: destAddress, data: buffer)).get()
                    Self.logger.debug("Sent discovery packet")
                } catch {
                    Self.logger.error("Error writing and flusing channel: \(error)")
                    continue
                }
                let jitter = Int64.random(in: 0..<500 * 100_000) // Random jitter
                let timeoutNanos = UInt64(timeout.nanoseconds + jitter)
                Self.logger.debug("Waiting \(timeoutNanos) nanoseconds")
                try? await Task.sleep(nanoseconds: timeoutNanos)
            }
            do {
                try await channel.close(mode: .all)
            } catch {
                Self.logger.error("Error closing channel \(error)")
            }
        }
    }
}

func extractValue(from xmlString: String, tag: String) -> String? {
    let pattern: String = "<\(tag)>(.+?)</\(tag)>"
    if let range = xmlString.range(of: pattern, options: .regularExpression) {
        let tagLength = tag.count
        let start = xmlString.index(range.lowerBound, offsetBy: tagLength + 2)
        let end = xmlString.index(range.upperBound, offsetBy: -(tagLength + 3))
        return String(xmlString[start..<end])
    }
    return nil
}


struct DeviceInfo {
    let powerMode: String?
    let networkType: String?
    let ethernetMAC: String?
    let wifiMAC: String?
    let deviceName: String?
    
    func isPowerOn() -> Bool {
        return powerMode == "PowerOn"
    }
}

final class WOLHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    let macAddress: String
    
    init(macAddress: String) {
        self.macAddress = macAddress
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Handle inbound data if needed
    }
}

class DatagramHandler: ChannelInboundHandler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DatagramHandler.self)
    )
    
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    let scanner: DeviceControllerActor
    
    init(scanner: DeviceControllerActor) {
        self.scanner = scanner
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let buffer = envelope.data
        guard let string = buffer.getString(at: 0, length: buffer.readableBytes) else {
            Self.logger.error("Error parsing discovery packet into string")
            return
        }
        // We are searching for a packet like this:
        // HTTP/1.1 200 OK
        // Cache-Control: max-age=3600
        // ST: roku:ecp
        // Location: http://192.168.1.134:8060/
        // USN: uuid:roku:ecp:P0A070000007
        
        Self.logger.debug("Got discovery packet \(string)")
        
        let lines = string.split(separator: "\r\n")
        var locationValue: String? = nil
        var idValue: String? = nil
        
        for line in lines {
            let locRegex = try! Regex("Location: ").ignoresCase()
            let usnRegex = try! Regex("USN: ").ignoresCase()
            if line.starts(with: locRegex) {
                locationValue = String(line.dropFirst("Location: ".count))
            } else if line.starts(with: usnRegex) {
                idValue = String(line.dropFirst("USN: ".count))
            }
        }
        Self.logger.debug("Found USN \(idValue ?? "") and location \(locationValue ?? "")")
        
        guard let id = idValue else {
            return
        }
        guard let location = locationValue else {
            return
        }
        Task {
            await scanner.itemFound(location: location, id: id)
        }
    }
}
