import Foundation
import Network
import os


let CheckConnectLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: canConnectTCP)
)

public func tryConnectTCP(location: String, timeout: TimeInterval, interface: NWInterface? = nil) async -> NWInterface? {
    CheckConnectLogger.debug("Checking can connect to url \(location)")
    guard let url = URL(string: location),
          let host = url.host,
          let port = url.port else {
        return nil
    }
    let tcpParams = NWProtocolTCP.Options()
    let params = NWParameters(tls: nil, tcp: tcpParams)
    if let interface = interface {
        params.requiredInterface = interface
    }
    
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: params)
    
    return try? await withTimeout(delay: timeout) {
        await withTaskCancellationHandler {
            let stream = AsyncStream { continuation in
                connection.stateUpdateHandler = { state in
                    CheckConnectLogger.debug("Received continuation for state \(String(describing: state))")
                    switch state {
                    case .ready:
                        CheckConnectLogger.debug("Ready with ifaces \(String(describing: connection.currentPath?.availableInterfaces))")
                        if let localIface = connection.currentPath?.availableInterfaces.first {
                            continuation.yield(Optional(localIface))
                            return
                        }
                    case .cancelled:
                        continuation.yield(nil)
                        return
                    case .failed, .waiting, .setup, .preparing:
                        return
                    @unknown default:
                        return
                    }
                }
            }
            
            var iterator =  stream.makeAsyncIterator()
            connection.start(queue: DispatchQueue.global())
            return await iterator.next() ?? nil
        } onCancel: {
            connection.cancel()
        }
    }
}

public func canConnectTCP(location: String, timeout: TimeInterval, interface: NWInterface? = nil) async -> Bool {
    return await tryConnectTCP(location: location, timeout: timeout, interface: interface) != nil
}
