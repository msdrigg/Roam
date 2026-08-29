import Darwin
import Foundation
import Network
import os
import System

enum SSDPError: Swift.Error, LocalizedError {
    case socketCreationFailed
    case connectionGroupFailed
    case interfaceNotFound(String?)
}

/// SSDP discovery for UPnP devices on the LAN.
/// Closes a file descriptor exactly once, however many callers ask.
///
/// `withTaskCancellationHandler` can run `onCancel` concurrently with the
/// operation body, so a socket closed on both paths gets `close(2)`d twice. The
/// kernel may have reissued that descriptor by then, and closing a guarded one
/// kills the process with `EXC_GUARD`, which `try?` cannot catch.
private final class CloseOnceFileDescriptor: @unchecked Sendable {
    private let fileDescriptor: FileDescriptor
    private let closed = OSAllocatedUnfairLock(initialState: false)

    init(_ fileDescriptor: FileDescriptor) {
        self.fileDescriptor = fileDescriptor
    }

    var wrapped: FileDescriptor { fileDescriptor }

    func close() {
        let shouldClose = closed.withLock { alreadyClosed -> Bool in
            if alreadyClosed { return false }
            alreadyClosed = true
            return true
        }
        guard shouldClose else {
            Log.scanning.notice("Skipping redundant SSDP socket close")
            return
        }
        try? fileDescriptor.close()
    }
}

/// Created using BSD sockets do to this bug: https://developer.apple.com/forums/thread/716339?page=1#769355022
/// Code using Network framework shown below
func scanDevicesContinually(
    interface: String?,
    onService: @Sendable @escaping (SSDPService) async -> Void
) async throws {
    Log.scanning.notice("Starting scan with interface \(interface ?? "nil", privacy: .public)")
    let socket = try FileDescriptor.socket(AF_INET, SOCK_DGRAM, 0)
    let socketCloser = CloseOnceFileDescriptor(socket)
    // Setting nosigpipe due to https://developer.apple.com/forums/thread/773307
    try socket.setSocketOption(SOL_SOCKET, SO_NOSIGPIPE, 1 as CInt)
    try socket.setSocketOption(SOL_SOCKET, SO_REUSEPORT, 1 as CInt)

    _ = try QSockAddr.withSockAddr(address: "0.0.0.0", port: 0) { sa, saLen in
        Log.scanning.notice("Binding SSDP search socket to 0.0.0.0:0")
        _ = try socket.bind(sa, saLen)
    }
    let localSocketAddress = try socket.getSockName()
    Log.scanning.notice(
        "Bound SSDP search socket to \(localSocketAddress.address, privacy: .public):\(localSocketAddress.port, privacy: .public)"
    )

    if let interface {
        let iface = try QSockAddr.interfaceIndex(interface)
        Log.scanning.notice("Setting bound interface \(interface, privacy: .public) (\(iface, privacy: .public))")
        try socket.setSocketOption(IPPROTO_IP, IP_BOUND_IF, UInt32(iface))
    }

    let groupAddress = "239.255.255.250"
    let groupPort: UInt16 = 1900

    let message =
        """
        M-SEARCH * HTTP/1.1\r\n\
        Host: 239.255.255.250:1900\r\n\
        Man: "ssdp:discover"\r\n\
        MX: 2\r\n\
        ST: roku:ecp\r\n\r\n
        """

    try await withTaskCancellationHandler {
        var sendingHandle: Task<Void, Never>?
        defer {
            Log.scanning.notice("Terminating ssdp")
            sendingHandle?.cancel()
            socketCloser.close()
        }

        Log.scanning.notice(
            "Sending initial SSDP request from \(localSocketAddress.address, privacy: .public):\(localSocketAddress.port, privacy: .public) to \(groupAddress, privacy: .public):\(groupPort, privacy: .public)"
        )
        try socket.send(data: Data(message.utf8), to: (address: groupAddress, port: groupPort))
        Log.scanning.notice("Sent initial SSDP request successfully")

        sendingHandle = Task.detached(priority: .background) {
            for await _ in exponentialBackoff(min: 2, max: 30) {
                if Task.isCancelled {
                    return
                }
                do {
                    Log.scanning.notice(
                        "Sending SSDP request from \(localSocketAddress.address, privacy: .public):\(localSocketAddress.port, privacy: .public) to \(groupAddress, privacy: .public):\(groupPort, privacy: .public)"
                    )
                    try socket.send(data: Data(message.utf8), to: (address: groupAddress, port: groupPort))
                    Log.scanning.notice("Sent SSDP request successfully")
                } catch {
                    Log.scanning.warning("Error sending SSDP request: \(error, privacy: .public)")
                }
            }
        }

        while !Task.isCancelled {
            do {
                Log.scanning.notice(
                    "Trying to receive SSDP data on \(localSocketAddress.address, privacy: .public):\(localSocketAddress.port, privacy: .public)"
                )
                let received = try await Task.detached(priority: .background) {
                    try socket.receiveFrom(maxCount: 16384)
                }.value
                let data = received.data
                let from = received.from
                Log.scanning.notice("Receiving SSDP data with len \(data.count, privacy: .public) from \(from.0, privacy: .public):\(from.1, privacy: .public)")
                if let response = String(data: data, encoding: .utf8) {
                    let service = SSDPService(host: from.address, response: response)
                    Log.scanning.notice(
                        "Decoded SSDP response from \(from.0, privacy: .public):\(from.1, privacy: .public) location=\(service.location ?? "nil", privacy: .public) usn=\(service.uniqueServiceName ?? "nil", privacy: .public)"
                    )
                    Log.scanning.notice("Handling SSDP service from \(from.0, privacy: .public):\(from.1, privacy: .public)")
                    await onService(service)
                } else {
                    Log.scanning.warning(
                        "Failed to decode SSDP response as UTF-8 from \(from.0, privacy: .public):\(from.1, privacy: .public)"
                    )
                }
            } catch {
                if Task.isCancelled {
                    Log.scanning.notice("Error receiving from cancelled SSDP: \(error, privacy: .public)")
                    return
                } else {
                    Log.scanning.warning("Error receiving SSDP: \(error, privacy: .public)")
                }
            }
        }
    } onCancel: {
        // This close interrupts the blocking `receiveFrom` above, and the
        // body's `defer` closes again as it unwinds. `socketCloser` makes sure
        // only one reaches `close(2)`.
        socketCloser.close()
    }
}
