import Foundation
import Network
import os

#if !os(watchOS)
public func tryConnectTCP(
    location: String,
    timeout: TimeInterval,
    interface: NWInterface? = nil
) async -> NWInterface? {
    guard let url = URL(string: location),
          let host = url.host,
          let port = url.port
    else {
        Log.scanning.error("Cannot connect to url \(location, privacy: .public) bc url not valid")
        return nil
    }

    return await tryConnectTCP(host: host, port: UInt16(port), timeout: timeout, interface: interface)
}

public func tryConnectTCP(
    host: String,
    port: UInt16,
    timeout: TimeInterval,
    interface: NWInterface? = nil
) async -> NWInterface? {
    Log.scanning.debug("Checking can connect to url (\(host, privacy: .public):\(port, privacy: .public)) with interface \(interface?.name ?? "--", privacy: .public)")
    let tcpParams = NWProtocolTCP.Options()
    let params = NWParameters(tls: nil, tcp: tcpParams)
    if let interface {
        params.requiredInterface = interface
    }

    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(integerLiteral: port),
        using: params
    )

    do {
        return try await withTimeout(delay: timeout) {
            await withTaskCancellationHandler {
                let stream = AsyncStream { continuation in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            Log.scanning
                                .debug(
                                    "Connected to \(host, privacy: .public):\(port, privacy: .public) with ifaces \(String(describing: connection.currentPath?.availableInterfaces), privacy: .public)"
                                )
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

                var iterator = stream.makeAsyncIterator()
                connection.start(queue: .network)
                return await iterator.next() ?? nil
            } onCancel: {
                connection.cancel()
            }
        }
    } catch {
        Log.scanning.warning("Cannot connect to \(host, privacy: .public):\(port, privacy: .public) on interface \(interface?.name ?? "--", privacy: .public) because of error \(error, privacy: .public)")
        return nil
    }
}

public func canConnectTCP(location: String, timeout: TimeInterval, interface: NWInterface? = nil) async -> Bool {
    await tryConnectTCP(location: location, timeout: timeout, interface: interface) != nil
}
#else
public func canConnectHTTP(location: String, timeout: TimeInterval) async -> Bool {
    let result = try? await withTimeout(delay: timeout) {
        guard let url = URL(string: location) else {
            throw APIError.badURLError(location)
        }
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )

        let stream = AsyncStream<Bool> { continuation in
            let task = URLSession.shared.dataTask(with: request) { _, response, _ in
                if let httpResponse = response as? HTTPURLResponse,
                   (200 ... 299).contains(httpResponse.statusCode)
                {
                    continuation.yield(true)
                } else {
                    continuation.yield(false)
                }
            }

            task.resume()
        }

        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? false
    } ?? false
    return result ?? false
}
#endif

enum APIError: Swift.Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .badURLError(let url):
            return "Invalid Device URL: \(url)"
        case .missingHeader(let header):
            return "Missing required header: \(header)"
        case .wrongContext(let message):
            return "Bad context: \(message)"
        case .badData(let message):
            return "Data error: \(message)"
        case .badStatus(let endpoint, let statusCode, _):
            if statusCode == 403 {
                return "Your Roku is blocking control from apps. On the Roku, open Settings > System > Advanced system settings > Control by mobile apps and set Network access to Default."
            }
            return "Device returned HTTP \(statusCode) for \(endpoint)"
        }
    }

    case badURLError(_ url: String)
    case missingHeader(_ header: String)
    case wrongContext(_ message: String)
    case badData(_ message: String)
    case badStatus(endpoint: String, statusCode: Int, body: String)

    /// A Roku answers 403 to keypress and query endpoints when "Control by mobile apps"
    /// is restricted in its network settings. It is the one failure here the user can fix
    /// themselves, so it is worth telling apart from an unreachable or broken device.
    var isControlBlockedByDevice: Bool {
        if case .badStatus(_, let statusCode, _) = self {
            return statusCode == 403
        }
        return false
    }
}

/// Longest response body recorded in a log line or a diagnostics report. Roku rejection
/// bodies are tiny; the cap only guards against a device answering with something huge.
private let maxLoggedBodyLength = 4096

func describeResponseBody(_ data: Data) -> String {
    guard let body = String(data: data, encoding: .utf8) else {
        return "<\(data.count) bytes of non-utf8 data>"
    }
    if body.count > maxLoggedBodyLength {
        return "\(body.prefix(maxLoggedBodyLength))... <truncated from \(body.count) characters>"
    }
    return body
}

func headerDictionary(_ response: HTTPURLResponse) -> [String: String] {
    var headers: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        if let keyString = key as? String, let valueString = value as? String {
            headers[keyString] = valueString
        }
    }
    return headers
}

/// Requires a 200 from an ECP endpoint, logging the full status, headers, and body when
/// the device refuses.
///
/// Roku rejection bodies are not XML, so callers that decode without checking the status
/// surface a misleading "data was corrupted / not valid XML" instead of the real reason.
func validateECPResponse(_ response: URLResponse, data: Data, endpoint: String) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.badData("Non-HTTP response from \(endpoint)")
    }

    guard httpResponse.statusCode != 200 else { return }

    let headers = headerDictionary(httpResponse)
        .sorted { $0.key < $1.key }
        .map { "\($0.key): \($0.value)" }
        .joined(separator: "\n")
    let body = describeResponseBody(data)

    Log.connection.error(
        """
        Error querying \(endpoint, privacy: .public): \(httpResponse.statusCode, privacy: .public)
        Headers:
        \(headers, privacy: .public)
        Body:
        \(body, privacy: .public)
        """
    )

    throw APIError.badStatus(endpoint: endpoint, statusCode: httpResponse.statusCode, body: body)
}
