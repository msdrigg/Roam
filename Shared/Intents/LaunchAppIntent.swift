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
        static var description = IntentDescription(LocalizedStringResource("Launch app on the device", comment: "Description on a siri shortcut"))

        @Parameter(title: LocalizedStringResource("Device", comment: "Description on a configuration field"))
        public var device: DeviceAppEntity?

        @Parameter(title: LocalizedStringResource("App", comment: "Description on a configuration field"))
        public var app: AppLinkAppEntity

        public static var parameterSummary: some ParameterSummary {
            Summary("App \(\.$app) on \(\.$device)")
        }

        public static var predictionConfiguration: some IntentPredictionConfiguration {
            IntentPrediction(parameters: (\.$app, \.$device)) { app, device in
                DisplayRepresentation(
                    title: LocalizedStringResource("Launch \(app) on \(device!)", comment: "Title on a siri shortcut")
                )
            }

            IntentPrediction(parameters: \.$app) { app in
                DisplayRepresentation(
                    title: LocalizedStringResource("Launch \(app) on the current device", comment: "Title on a siri shortcut")
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
