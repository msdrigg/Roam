import Foundation
import XMLCoder
import os

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

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "FetchDevice"
)


func fetchDeviceInfo(location: String) async -> DeviceInfo? {
    let deviceInfoURL = "\(location)query/device-info"
    guard let url = URL(string: deviceInfoURL) else {
        logger.error("Unable to get device info due to bad url \(deviceInfoURL)")
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
//                logger.debug("Trying to decode DeviceInfo from:\n\(xmlString.prefix(20))...")
                let info = try decoder.decode(DeviceInfo.self, from: Data(xmlString.utf8))
//                logger.debug("Decoded DeviceInfo from: \(String(describing: info).prefix(20))...")
                return info
            } catch {
                logger.error("Error decoding DeviceInfo response \(error)")
            }
        }
    } catch {
        logger.error("Error getting device info: \(error)")
    }
    return nil
}

func fetchDeviceApps(location: String) async throws -> [AppLinkAppEntity] {
    let url = URL(string: "\(location)/query/apps")!
    let (data, _) = try await URLSession.shared.data(from: url)
    
    let decoder = XMLDecoder()
    let apps = try decoder.decode(Apps.self, from: data)
    
    return apps.app.map{$0.toAppEntity()}
}

func fetchAppIcon(location: String, appId: String) async throws -> Data {
    let url = URL(string: "\(location)/query/icon/\(appId)")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}
