//
//  Mute.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/16/23.
//

import Foundation
import AppIntents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct Mute: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "MuteIntent"

    static var title: LocalizedStringResource = "Mute"
    static var description = IntentDescription("Mute the device")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Mute \(\.$device)")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Mute \(device!)",
                subtitle: ""
            )
        }
        IntentPrediction(parameters: ()) {  in
            DisplayRepresentation(
                title: "Mute the current device",
                subtitle: ""
            )
        }
    }

    func perform() async throws -> some IntentResult {
        // TODO: Place your refactored intent handler code here.
        return .result()
    }
}


