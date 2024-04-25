import AppIntents
import Foundation
import Intents

#if !os(tvOS)
    @available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
    public struct LaunchAppIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent,
        PredictableIntent
    {
        public static let intentClassName = "LaunchAppIntent"

        public static var title: LocalizedStringResource = "Launch App"
        static var description = IntentDescription("Launch app on the device")

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

            IntentPrediction(parameters: \.$app) { app in
                DisplayRepresentation(
                    title: "Launch \(app) on the current device"
                )
            }
        }

        public func perform() async throws -> some IntentResult {
            try await launchApp(app: app, device: device)
            return .result()
        }

        public init() {}

        public init(_ app: AppLinkAppEntity, device: DeviceAppEntity?) {
            self.app = app
            self.device = device
        }
    }
#endif
