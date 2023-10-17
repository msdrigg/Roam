//
//  Select.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/16/23.
//

import Foundation
import AppIntents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct Select: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let intentClassName = "SelectIntent"

    static var title: LocalizedStringResource = "Select"
    static var description = IntentDescription("Confirm selection on the device ")

    @Parameter(title: "Device")
    var device: DeviceAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Confirm selection on \(\.$device) ")
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device)) { device in
            DisplayRepresentation(
                title: "Confirm selection on \(device!) ",
                subtitle: ""
            )
        }
        IntentPrediction(parameters: ()) {  in
            DisplayRepresentation(
                title: "Confirm selection on the current device",
                subtitle: ""
            )
        }
    }

    func perform() async throws -> some IntentResult {
        // TODO: Place your refactored intent handler code here.
        return .result()
    }
}


