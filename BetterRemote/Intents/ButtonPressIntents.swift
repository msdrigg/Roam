//
//  Select.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/16/23.
//

import Foundation
import AppIntents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct PlayIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "PlayIntent"

    static var title: LocalizedStringResource = "Press play"
    static var description = IntentDescription("Play or pause the media on the connected device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?


    static var parameterSummary: some ParameterSummary {
        Summary("Press play on \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Press play on \(device!)"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await clickButton(button: .power, device: device)
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct OkIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "OkIntent"

    static var title: LocalizedStringResource = "Click Ok"
    static var description = IntentDescription("Click Ok on the device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?


    static var parameterSummary: some ParameterSummary {
        Summary("Click on on \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Click Ok on \(device!)"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await clickButton(button: .select, device: device)
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct MuteIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "MuteIntent"

    static var title: LocalizedStringResource = "Toggle Mute"
    static var description = IntentDescription("Mute or unmote the device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?


    static var parameterSummary: some ParameterSummary {
        Summary("Toggle volume mute on \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Toggle volume mute on \(device!)"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await clickButton(button: .select, device: device)
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct PowerIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "PowerIntent"

    static var title: LocalizedStringResource = "Toggle Power"
    static var description = IntentDescription("Power on or off the device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?


    static var parameterSummary: some ParameterSummary {
        Summary("Power on or off \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Power on or off \(device!)"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await clickButton(button: .playPause, device: device)
    }
}


@MainActor
func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws -> some IntentResult {
    let modelContainer = try getSharedModelContainer()
    let deviceController = DeviceControllerActor(modelContainer: modelContainer)
    let context = modelContainer.mainContext
    
    guard let targetDevice = device ?? fetchSelectedDevice(context: context)?.toAppEntity() else {
        return .result()
    }
    
    await deviceController.sendKeyToDevice(location: targetDevice.location, key: button)
    
    return .result()
}
