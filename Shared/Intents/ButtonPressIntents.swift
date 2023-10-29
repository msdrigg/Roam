import Foundation
import AppIntents
import SwiftData

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct PlayIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PlayIntent"

    public static var title: LocalizedStringResource = "Press play"
    public static var description = IntentDescription("Play or pause the media on the connected device")
    
    public init() {}

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Press play on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Press play on \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .playPause, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct OkIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "OkIntent"

    public static var title: LocalizedStringResource = "Click Ok"
    public static var description = IntentDescription("Click Ok on the device")
    public init() {}


    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Click on on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Click Ok on \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .select, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct MuteIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public var value: Never?
    
    public static let intentClassName = "MuteIntent"

    public static var title: LocalizedStringResource = "Toggle Mute"
    public static var description = IntentDescription("Mute or unmote the device")
    public init() {}


    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Toggle volume mute on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Toggle volume mute on \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .mute, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct VolumeUpIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "VolumeUpIntent"

    public static var title: LocalizedStringResource = "Increase volume"
    public static var description = IntentDescription("Increase the volume on the device")
    public init() {}


    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Increase the volume on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Increase the volume on \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeUp, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct VolumeDownIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "VolumeDownIntent"

    public static var title: LocalizedStringResource = "Lower volume"
    public static var description = IntentDescription("Lower the volume on the device")
    public init() {}


    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Lower the volume on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Lower the volume on \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeDown, device: device)
        return .result()
    }
}


@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct PowerIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PowerIntent"

    public static var title: LocalizedStringResource = "Toggle Power"
    public static var description = IntentDescription("Power on or off the device")
    public init() {}


    @Parameter(title: "Device")
    public var device: DeviceAppEntity?


    public static var parameterSummary: some ParameterSummary {
        Summary("Power on or off \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Power on or off \(device!)"
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .power, device: device)
        return .result()
    }
}
