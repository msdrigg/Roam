import os
import Foundation
import SwiftUI
import SwiftData

import Network


public actor DeviceControllerActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceControllerActor.self)
    )
    
    func wakeOnLAN(macAddress: String) async {
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
                Self.logger.error("Invalid MAC address")
                return nil
            }
            
            for _ in 0..<16 {
                packet.append(contentsOf: macBytes)
            }
            return packet
        }()
        
        guard let packet = packet else {
            return
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
                                Self.logger.error("Error sending WOL packet for MAC \(macAddress): \(error)")
                            } else {
                                Self.logger.info("Sent WOL packet")
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
            Self.logger.error("Unable to send WOL packet within 5 sec")
        }
    }

    public func openApp(location: String, app: String) {
        guard let url = URL(string: "\(location)launch/\(app)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Self.logger.info("Opened app \(app) to with location \(location)")
                } else {
                    Self.logger.error("Error opening app \(app) at \(location)launch/\(app): \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
        
    }
    
    public func powerToggleDevice(location: String, mac: String?) async {
        Self.logger.debug("Toggling power for device \(location)")
        
        let onlineAtFirst = await canConnectTCP(location: location, timeout: 0.5)
        
        // Attempt WOL if not already connected
        if !onlineAtFirst {
            if let mac = mac {
                Self.logger.debug("Sending wol packet to \(mac)")
                await wakeOnLAN(macAddress: mac)
            }
            Self.logger.debug("Not online initially, so not continuing")
        }
        
        // Attempt checking the device power mode
        Self.logger.debug("Attempting to power toggle device woth api")
        // Power has apiValue
        await internalSendKeyToDevice(location: location, rawKey: RemoteButton.power.apiValue!)
    }
    
    public func sendKeyPressTodevice(location: String, key: Character) async {
        await internalSendKeyToDevice(location: location, rawKey: getKeypressForKey(key: key))
    }
    
    public func sendKeyToDevice(location: String, mac: String?, key: RemoteButton) async {
        if key == .power {
            await self.powerToggleDevice(location: location, mac: mac)
        } else {
            if let apiValue = key.apiValue {
                await internalSendKeyToDevice(location: location, rawKey: apiValue)
            }
        }
    }
    
    public func sendKeyToDeviceRawNotRecommended(location: String, key: String, mac: String?) async {
        if key == RemoteButton.power.apiValue {
            await powerToggleDevice(location: location, mac: mac)
        } else {
            await internalSendKeyToDevice(location: location, rawKey: key)
        }
    }
        
    private func internalSendKeyToDevice(location: String, rawKey: String) async {
        let keypressURL = "\(location)/keypress/\(rawKey)"
        guard let url = URL(string: keypressURL) else {
            Self.logger.error("Unable to send key due to bad url url `\(keypressURL)`")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Self.logger.debug("Sent \(rawKey) to \(location)")
                } else {
                    Self.logger.error("Error sending \(rawKey) to \(location): \(httpResponse.statusCode)")
                }
            }
        } catch {
            Self.logger.error("Error sending \(rawKey) to \(location): \(error)")
        }
    }
}

private func getKeypressForKey(key: Character) -> String {
    // All of these keys are gauranteed to have api values
    #if !os(watchOS)
    let keyMap: [Character: String] = [
        "\u{7F}": RemoteButton.backspace.apiValue!,
        KeyEquivalent.delete.character: RemoteButton.backspace.apiValue!,
        KeyEquivalent.deleteForward.character: RemoteButton.backspace.apiValue!,
        KeyEquivalent.escape.character: RemoteButton.backspace.apiValue!,
        KeyEquivalent.space.character: "LIT_ ",
        KeyEquivalent.downArrow.character: RemoteButton.down.apiValue!,
        KeyEquivalent.upArrow.character: RemoteButton.up.apiValue!,
        KeyEquivalent.rightArrow.character: RemoteButton.right.apiValue!,
        KeyEquivalent.leftArrow.character: RemoteButton.left.apiValue!,
        KeyEquivalent.home.character: RemoteButton.home.apiValue!,
        KeyEquivalent.return.character: RemoteButton.select.apiValue!,
    ]
    #else
    let keyMap: [Character: String] = [
        "\u{7F}": RemoteButton.backspace.apiValue!,
    ]
    #endif
    
    if let mappedString = keyMap[key] {
        return mappedString
    }
    
    return "LIT_\(key)"
}
