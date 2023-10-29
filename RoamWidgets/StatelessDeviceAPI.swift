//  StatelessDeviceAPI.swift
//  RoamWidgets
//
//  Created by Scott Driggers on 10/27/23.
//

import Foundation
import Network
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: "StatelessAPI")
)

@discardableResult
func wakeOnLAN(macAddress: String) async -> Bool {
    let host = NWEndpoint.Host("255.255.255.255")
    let port = NWEndpoint.Port(rawValue: 9)!
    let parameters = NWParameters.udp
    let connection = NWConnection(host: host, port: port, using: parameters)
    
    let packet: Data? = {
        var packet = Data()
        // Create the header with 6 bytes of FF
        for _ in 0..<6 {
            packet.append(0xFF)
        }
        
        // Parse MAC address and append it 16 times to the packet
        let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else {
            logger.error("Invalid MAC address")
            return nil
        }
        
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }()
    
    guard let packet = packet else {
        return false
    }
    
    let timeout = DispatchTime.now() + .seconds(5) // Set a 5-second timeout
    let statusStream = AsyncStream { continuation in
        // Start a timer to handle timeout
        DispatchQueue.global().asyncAfter(deadline: timeout) {
            continuation.yield(false)
            connection.cancel()
        }
        
        connection.stateUpdateHandler = { state in
            if state == .ready {
                connection.send(content: packet, completion: NWConnection.SendCompletion.contentProcessed({ error in
                    if let error = error {
                        logger.error("Error sending WOL packet for MAC \(macAddress): \(error)")
                    } else {
                        logger.info("Sent WOL packet")
                    }
                    connection.cancel()
                    continuation.yield(true)
                }))
            } else {
                switch state {
                case .failed:
                    continuation.yield(false)
                case .cancelled:
                    continuation.yield(false)
                default:
                    return
                }
            }
        }
        connection.start(queue: .global())
    }
    
    var iterator = statusStream.makeAsyncIterator()
    let canSendPacket = await iterator.next() ?? false
    
    if !canSendPacket {
        logger.error("Unable to send WOL packet within 5 sec")
    }
    return canSendPacket
}

public func openApp(location: String, app: String) async throws {
    guard let url = URL(string: "\(location)launch/\(app)") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let (_, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 200 {
            logger.info("Opened app \(app) to with location \(location)")
        } else {
            logger.error("Error opening app \(app) at \(location)launch/\(app): \(httpResponse.statusCode)")
        }
    }
}

public func powerToggleDevice(location: String, mac: String?) async -> Bool {
    logger.debug("Toggling power for device \(location)")
    
    #if !os(watchOS)
    let onlineAtFirst = await canConnectTCP(location: location, timeout: 0.5)
    #else
    let onlineAtFirst = await canConnectHTTP(location: location, timeout: 2)
    #endif
    
    // Attempt WOL if not already connected
    if !onlineAtFirst {
        if let mac = mac {
            logger.debug("Sending wol packet to \(mac)")
            return await wakeOnLAN(macAddress: mac)
        }
        logger.debug("Not online initially, so not continuing")
        return false
    }
    
    // Attempt checking the device power mode
    logger.debug("Attempting to power toggle device with api")
    
    // SAFETY: Power has apiValue
    return await internalSendKeyToDevice(location: location, rawKey: RemoteButton.power.apiValue!)
}

public func sendKeyPressTodevice(location: String, key: Character) async -> Bool {
    return await internalSendKeyToDevice(location: location, rawKey: getKeypressForKey(key: key))
}

@discardableResult
public func sendKeyToDevice(location: String, mac: String?, key: RemoteButton) async -> Bool {
    if key == .power {
        return await powerToggleDevice(location: location, mac: mac)
    } else {
        if let apiValue = key.apiValue {
            return await internalSendKeyToDevice(location: location, rawKey: apiValue)
        }
    }
    
    return false
}

public func sendKeyToDeviceRawNotRecommended(location: String, key: String, mac: String?) async -> Bool {
    if key == RemoteButton.power.apiValue {
        return await powerToggleDevice(location: location, mac: mac)
    } else {
        return await internalSendKeyToDevice(location: location, rawKey: key)
    }
}

private func internalSendKeyToDevice(location: String, rawKey: String) async -> Bool {
    let keypressURL = "\(location)/keypress/\(rawKey)"
    guard let url = URL(string: keypressURL) else {
        logger.error("Unable to send key due to bad url url `\(keypressURL)`")
        return false
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                logger.debug("Sent \(rawKey) to \(location)")
                return true
            } else {
                logger.error("Error sending \(rawKey) to \(location): \(httpResponse.statusCode)")
                return false
            }
        }
        
        return false
    } catch {
        logger.error("Error sending \(rawKey) to \(location): \(error)")
        return false
    }
}
