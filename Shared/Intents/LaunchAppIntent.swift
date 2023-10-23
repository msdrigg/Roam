import Foundation
import AppIntents
import Intents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct LaunchAppIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "LaunchAppIntent"

    public static var title: LocalizedStringResource = "Launch App"
    static var description = IntentDescription("Launch app on the device")
    
    public init() {}

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?
    
    @Parameter(title: "App")
    public var app: AppLinkAppEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("App \(\.$app) on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$app, \.$device)) { app, device in
            DisplayRepresentation(
                title: "Launch \(app) on \(device!)"
            )
        }
        
        IntentPrediction(parameters: (\.$app)) { app in
            DisplayRepresentation(
                title: "Launch \(app) on the current device"
            )
        }
    }
    
    public func perform() async throws -> some IntentResult {
        let modelContainer = try getSharedModelContainer()
        let deviceController = DeviceControllerActor()
        
        var targetDevice = device
        if targetDevice == nil {
             targetDevice = await fetchSelectedDevice(modelContainer: modelContainer)
        }
        
        if let targetDevice = targetDevice {
            await deviceController.openApp(location: targetDevice.location, app: app.id)
        }
        
        return .result()
    }
}


