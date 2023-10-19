import Foundation
import Network
import os


let CheckConnectLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: canConnectTCP)
)

public func canConnectTCP(location: String, timeout: TimeInterval, interface: NWInterface? = nil) async -> Bool {
    CheckConnectLogger.debug("Checking can connect to url \(location)")
    guard let url = URL(string: location),
          let host = url.host,
          let port = url.port else {
        return false
    }
    let tcpParams = NWProtocolTCP.Options()
    let params = NWParameters(tls: nil, tcp: tcpParams)
    if let interface = interface {
        params.requiredInterface = interface
    }
    
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: params)
    
    let result = await withTaskGroup(of: Bool.self) { taskGroup in
        taskGroup.addTask {
            let stream = AsyncStream { continuation in
                connection.stateUpdateHandler = { state in
                    CheckConnectLogger.debug("Received continuation for state \(String(describing: state))")
                    switch state {
                    case .ready:
                        continuation.yield(true)
                        return
                    case .cancelled:
                        continuation.yield(false)
                        return
                    case .failed, .waiting, .setup, .preparing:
                        return
                    @unknown default:
                        return
                    }
                }
            }
            
            var iterator =  stream.makeAsyncIterator()
            return await iterator.next() ?? false
        }
        connection.start(queue: DispatchQueue.global())
        
        taskGroup.addTask {
            CheckConnectLogger.trace("Waiting to sleep for timeout \(timeout) secs")
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                connection.cancel()
                CheckConnectLogger.trace("Slept for \(timeout) secs")
            } catch {
                CheckConnectLogger.trace("Cancelled before \(timeout) secs elapsed")
            }
            return false
        }
        var didConnect = false
        for await result in taskGroup {
            CheckConnectLogger.trace("Got task result \(result)")
            taskGroup.cancelAll()
            didConnect = didConnect || result
        }
        
        return didConnect
    }
    CheckConnectLogger.trace("Got couldConnect result \(result)")
    return result
}
