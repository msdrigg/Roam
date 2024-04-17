//
//  Debugger.swift
//  Roam
//
//  Created by Scott Driggers on 3/10/24.
//

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
    let osPlatform: String?
    let osVersion: String?
    
    init(entry: OSLogEntry) {
        self.message = entry.composedMessage
        self.timestamp = entry.date
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
        
        if let logEntry = entry as? OSLogEntryLog {
            switch logEntry.level {
            case .info:
                self.level = "Info"
            case .debug:
                self.level = "Debug"
            case .error:
                self.level = "Error"
            case .fault:
                self.level = "Fault"
            case .notice:
                self.level = "Notice"
            case .undefined:
                self.level = "Undefined"
            default:
                self.level = "Unknown"
            }
        } else {
            self.level = nil
        }
        
        if let payloadEntry = entry as? OSLogEntryWithPayload {
            self.category = payloadEntry.category
            self.subsystem = payloadEntry.subsystem
        } else {
            self.category = nil
            self.subsystem = nil
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

public struct DebugInfo: Encodable {
    let message: String?
    let id: String
    let date: Date
    let buildVersion: String?
    let logs: [LogEntry]
    let devices: [DeviceDebugInfo]
    let debugErrors: [String]
    let interfaces: [Addressed4NetworkInterface]
}

func getDebugInfo(container: ModelContainer, message: String?) async -> DebugInfo {
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
                deviceDebugInfos.append(DeviceDebugInfo(device: device, successResponse: responseData, errorResponse: nil))
            } else {
                throw BadResponseError(message: "Got non-http response trying to query device info \(String(describing: response))")
            }
        } catch {
            deviceDebugInfos.append(DeviceDebugInfo(device: device, successResponse: nil, errorResponse: "\(error)"))
        }
    }
    
    let localInterfaces = await allAddressedInterfaces()
    
    var buildVersion: String? = nil
    if let infoPlist = Bundle.main.infoDictionary,
       let currentProjectVersion = infoPlist["CURRENT_PROJECT_VERSION"] as? String {
        buildVersion = currentProjectVersion
    } else {
        debugErrors.append("AppVersion not found")
    }
    
    
    return DebugInfo(message: message, id: getSystemInstallID(), date: Date.now, buildVersion: buildVersion, logs: entries, devices: deviceDebugInfos, debugErrors: debugErrors, interfaces: localInterfaces)
    
}

private func getLogEntries(limit: Int = 100000) throws -> [LogEntry] {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let date = Date.now.addingTimeInterval(-24 * 3600)
    let position = logStore.position(date: date)
    
    var logEntries: [LogEntry] = []
    
    do {
        let sequence = try logStore.getEntries(at: position);
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

