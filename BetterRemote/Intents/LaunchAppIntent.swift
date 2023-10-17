import Foundation
import AppIntents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct LaunchAppIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "LaunchAppIntent"

    static var title: LocalizedStringResource = "Launch App"
    static var description = IntentDescription("Launch app on the device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?
    
    @Parameter(title: "App")
    var app: AppLinkAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("App \(\.$app) on \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
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
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let modelContainer = try getSharedModelContainer()
        let deviceController = DeviceControllerActor(modelContainer: modelContainer)
        let context = modelContainer.mainContext
        
        guard let targetDevice = device ?? fetchSelectedDevice(context: context)?.toAppEntity() else {
            return .result()
        }
        
        await deviceController.openApp(location: targetDevice.location, app: app.id)
        
        return .result()
    }
}


