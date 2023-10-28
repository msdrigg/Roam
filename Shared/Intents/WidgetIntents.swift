import Foundation
import AppIntents
import os

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct DeviceChoiceIntent: AppIntent, WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "Choose a device"
    public static var description = IntentDescription("Choose which device to target")
    
    public init() {}
    
    @Parameter(title: "Device")
    public var device: DeviceAppEntity?
    
    @Parameter(title: "Ignore this setting and use app's selection instead", default: true)
    public var useDefaultDevice: Bool
}


@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct ButtonPressIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ButtonPressIntent.self)
    )
    
    public static let intentClassName = "ButtonPressIntent"

    public static var title: LocalizedStringResource = "Press a button"
    public static var description = IntentDescription("Press a button on the connected device")
    
    public init() {}

    @Parameter(title: "Device")
    var device: DeviceAppEntity?
    
    @Parameter(title: "Button")
    var button: RemoteButtonAppEnum


    public static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$button) on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$button, \.$device)) { button, device in
            DisplayRepresentation(
                title: "Press \(button) on \(device!)"
            )
        }
    }
    
    public init(_ button: RemoteButton, device: DeviceAppEntity?) {
        self.button = RemoteButtonAppEnum(button)
        self.device = device
    }

    public func perform() async throws -> some IntentResult {
        Self.logger.debug("Pressing widget button \(button.button.apiValue ?? "nil") on device \(device?.name ?? "nil")")
        
        try await clickButton(button: button.button, device: device)
        
        return .result()
    }
}

public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
    let modelContainer = getSharedModelContainer()
    
    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await fetchSelectedDevice(modelContainer: modelContainer)
    }
    
    if let deviceKey = button.apiValue, let targetDevice = targetDevice {
        await sendKeyToDeviceRawNotRecommended(location: targetDevice.location, key: deviceKey, mac: targetDevice.mac)
    }
    
    return
}
