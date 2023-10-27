import Foundation
import os    
import Darwin
import Network

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: "SSDPDiscovery")
)

enum SSDPError: Error, LocalizedError {
    case SocketCreationFailed
    case ConnectionGroupFailed
}

func htons(_ value: CUnsignedShort) -> CUnsignedShort {
    return (value << 8) + (value >> 8)
}

/// SSDP discovery for UPnP devices on the LAN.
/// Created using BSD sockets do to this bug: https://developer.apple.com/forums/thread/716339?page=1#769355022
/// Code using Network framework shown below
func scanDevicesContinually() throws -> AsyncThrowingStream<SSDPService, Error> {
    return AsyncThrowingStream { continuation in
        var group = sockaddr_in()
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 16384)
        let sockfd: Int32 = socket(AF_INET, SOCK_DGRAM, 0)
        
        if sockfd < 0 {
            let errorString = String(cString: strerror(errno))
            logger.error("Error creating socket with message: \(errorString)")
            
            continuation.finish(throwing: SSDPError.SocketCreationFailed)
            buffer.deallocate()
            return
        }
        
        let group_addr = inet_addr("239.255.255.250")
        if group_addr == INADDR_NONE {
            let errorString = String(cString: strerror(errno))
            logger.error("Error group address with message: \(errorString)")
            continuation.finish(throwing: SSDPError.SocketCreationFailed)
            
            close(sockfd)
            buffer.deallocate()
            return
        }
        
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = htons(1900)
        group.sin_addr.s_addr = group_addr
        
        let message = "M-SEARCH * HTTP/1.1\r\nHost: 192.168.8.133:10505\r\nMan: \"ssdp:discover\"\r\nST: roku:ecp\r\n\r\n"
        
        let sendingHandle = Task { [group] in
            for await _ in exponentialBackoff(min: 2, max: 30) {
                if Task.isCancelled {
                    return
                }
                var tmpGroup = group
                withUnsafePointer(to: &tmpGroup) { groupPointer in
                    let sent = sendto(sockfd, message, message.utf8.count, 0, groupPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }, socklen_t(MemoryLayout<sockaddr_in>.size))
                    if sent < 0 {
                        let errorString = String(cString: strerror(errno))
                        logger.warning("Error sending SSDP request with message \(errorString)")
                    } else {
                        logger.debug("Sent SSDP request successfully")
                    }
                }
            }
        }
        
        let receivingHandle = Task {
            while !Task.isCancelled {
                let received = recv(sockfd, buffer, 16384, 0)
                if received > 0 {
                    let dataCopy = Data(bytes: buffer, count: received)
                    if let response = String(data: dataCopy, encoding: .utf8) {
                        continuation.yield(SSDPService(host: "239.255.255.250", response: response))
                    }
                } else {
                    let errorString = String(cString: strerror(errno))
                    logger.warning("Error receiving from socket with message: \(errorString)")
                }
            }
        }

        continuation.onTermination = { @Sendable _ in
            receivingHandle.cancel()
            sendingHandle.cancel()
            close(sockfd)
            buffer.deallocate()
        }
    }
}



func scanDevicesContinuallyNetwork() throws -> AsyncThrowingStream<SSDPService, any Error> {
    let multicastGroup = try NWMulticastGroup(for: [.hostPort(host: "239.255.255.250", port: 1900)])
    
    return AsyncThrowingStream { continuation in
        let ssdpRequest = "M-SEARCH * HTTP/1.1\r\nHost: 192.168.8.133:10505\r\nMan: \"ssdp:discover\"\r\nST: roku:ecp\r\n\r\n"
        let ssdpRequestData: Data = ssdpRequest.data(using: .utf8)!
        
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        let connectionGroup = NWConnectionGroup(with: multicastGroup, using: params)
        connectionGroup.setReceiveHandler(maximumMessageSize: 16384, rejectOversizedMessages: true) { (_, data, _) in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                continuation.yield(SSDPService(host: "239.255.255.250", response: message))
            }
        }
        connectionGroup.stateUpdateHandler = { newState in
            switch newState {
            case .failed(let error):
                logger.error("ConnectionGroup failed with error: \(error)")
                continuation.finish(throwing: SSDPError.ConnectionGroupFailed)
            default:
                logger.info("ConnectionGroup entered state: \(String(describing: newState))")
            }
        }

        connectionGroup.start(queue: .global(qos: .userInitiated))
        
        let handle = Task {
            for await _ in exponentialBackoff(min: 2, max: 30) {
                connectionGroup.send(content: ssdpRequestData) { error in
                    if let error = error {
                        logger.warning("Error sending SSDP request: \(error)")
                    }
                }
            }
        }
        
        continuation.onTermination = { @Sendable _ in
            handle.cancel()
            connectionGroup.cancel()
        }
    }
}
