import Foundation
import os
import OSLog
import SwiftData

struct DebugError: Error {
    let message: String
}

struct BadResponseError: Error {
    let message: String
}

struct LogEntry: Encodable {
    let message: String
    let timestamp: Date
    let level: String?
    let category: String?
    let subsystem: String?

    init(entry: OSLogEntry) {
        message = entry.composedMessage
        timestamp = entry.date

        if let logEntry = entry as? OSLogEntryLog {
            switch logEntry.level {
            case .info:
                level = "Info"
            case .debug:
                level = "Debug"
            case .error:
                level = "Error"
            case .fault:
                level = "Fault"
            case .notice:
                level = "Notice"
            case .undefined:
                level = "Undefined"
            default:
                level = "Unknown"
            }
        } else {
            level = nil
        }

        if let payloadEntry = entry as? OSLogEntryWithPayload {
            category = payloadEntry.category
            subsystem = payloadEntry.subsystem
        } else {
            category = nil
            subsystem = nil
        }
    }
}

struct ResponseData: Encodable {
    let headers: [String: String]
    let statusCode: Int
    let data: String
}

struct DeviceDebugInfo: Encodable {
    let device: DeviceAppEntity
    let successResponse: ResponseData?
    let errorResponse: String?
}

public struct InstallationInfo: Encodable {
    let userId: String
    let buildVersion: String?
    let osPlatform: String?
    let osVersion: String?

    init() {
        osVersion = ProcessInfo().operatingSystemVersionString
        #if os(iOS)
            osPlatform = "iOS"
        #elseif os(macOS)
            osPlatform = "macOS"
        #elseif os(watchOS)
            osPlatform = "watchOS"
        #elseif os(tvOS)
            osPlatform = "tvOS"
        #elseif os(visionOS)
            osPlatform = "visionOS"
        #endif

        if let infoPlist = Bundle.main.infoDictionary,
           let currentProjectVersion = infoPlist["CURRENT_PROJECT_VERSION"] as? String
        {
            buildVersion = currentProjectVersion
        } else {
            buildVersion = nil
        }
        userId = getSystemInstallID()
    }
}

public struct DebugInfo: Encodable {
    let installationInfo: InstallationInfo
    let devices: [DeviceDebugInfo]
    let appLinks: [AppLinkAppEntity]
    let interfaces: [Addressed4NetworkInterface]
    let logs: [LogEntry]
    let debugErrors: [String]
}

func getDebugInfo(container: ModelContainer) async -> DebugInfo {
    var debugErrors: [String] = []
    var entries: [LogEntry] = []
    do {
        entries = try getLogEntries()
    } catch {
        debugErrors.append("Error Getting Log Entries: \n\(error)")
    }

    var devices: [DeviceAppEntity] = []
    do {
        devices = try await DeviceActor(modelContainer: container).allDeviceEntitiesIncludingDeleted()
    } catch {
        debugErrors.append("Error Getting Devices: \n\(error)")
    }
    var deviceDebugInfos: [DeviceDebugInfo] = []

    for device in devices {
        do {
            let deviceInfoURL = "\(device.location)query/device-info"
            guard let url = URL(string: deviceInfoURL) else {
                throw DebugError(message: "Bad URL \(deviceInfoURL)")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5
            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                let dataString = String(decoding: data, as: UTF8.self)

                var headers: [String: String] = [:]

                for (key, value) in httpResponse.allHeaderFields {
                    if let keyString = key as? String, let valueString = value as? String {
                        headers[keyString] = valueString
                    }
                }
                let responseData = ResponseData(headers: headers, statusCode: statusCode, data: dataString)
                deviceDebugInfos.append(DeviceDebugInfo(
                    device: device,
                    successResponse: responseData,
                    errorResponse: nil
                ))
            } else {
                throw BadResponseError(
                    message: "Got non-http response trying to query device info \(String(describing: response))"
                )
            }
        } catch {
            deviceDebugInfos.append(DeviceDebugInfo(device: device, successResponse: nil, errorResponse: "\(error)"))
        }
    }

    let localInterfaces = await allAddressedInterfaces()

    var appLinks: [AppLinkAppEntity] = []
    do {
        appLinks = try await AppLinkActor(modelContainer: container).allEntities()
    } catch {
        debugErrors.append("Error Getting AppLinks: \n\(error)")
    }

    return DebugInfo(
        installationInfo: InstallationInfo(),
        devices: deviceDebugInfos,
        appLinks: appLinks,
        interfaces: localInterfaces,
        logs: entries,
        debugErrors: debugErrors
    )
}

private func getLogEntries(limit: Int = 50000) throws -> [LogEntry] {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let date = Date.now
    let position = logStore.position(date: date)

    var logEntries: [LogEntry] = []

    do {
        let sequence = try logStore.getEntries(with: .reverse, at: position)
        for entry in sequence.prefix(limit) {
            if let logEntry = entry as? OSLogEntryLog, logEntries.count < limit {
                logEntries.append(LogEntry(entry: logEntry))
            }
        }
    } catch {
        os_log(.error, "Error fetching log entries: \(error)")
    }

    return logEntries
}
