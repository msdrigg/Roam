import AppIntents
import Foundation
import os

#if !os(tvOS)
    @available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
    public struct DeviceChoiceIntent: AppIntent, WidgetConfigurationIntent {
        public static var title: LocalizedStringResource = "Choose a device"
        public static var description = IntentDescription("Choose which device to target")

        public init() {}

        @Parameter(title: "Manually select which device to remote control", default: false)
        public var manuallySelectDevice: Bool

        @Parameter(title: "Device")
        public var device: DeviceAppEntity?

        public static var parameterSummary: some ParameterSummary {
            When(\.$manuallySelectDevice, .equalTo, true) {
                Summary {
                    \.$manuallySelectDevice
                    \.$device
                }
            } otherwise: {
                Summary {
                    \.$manuallySelectDevice
                }
            }
        }
        
        public var selectedDevice: DeviceAppEntity? {
            if (!manuallySelectDevice) {
                return nil
            }
            
            return device
        }
    }

    @available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
    public struct DeviceAndAppChoiceIntent: AppIntent, WidgetConfigurationIntent {
        public static var title: LocalizedStringResource = "Choose a device and apps"
        public static var description = IntentDescription("Choose which device to target, and select apps to view")

        public init() {}

        @Parameter(title: "Manually select which device to remote control", default: false)
        public var manuallySelectDevice: Bool

        @Parameter(title: "Device")
        public var device: DeviceAppEntity?

        @Parameter(title: "Manually select which apps to show", default: false)
        public var manuallySelectApps: Bool

        @Parameter(title: "App 1")
        public var app1: AppLinkAppEntity?

        @Parameter(title: "App 2")
        public var app2: AppLinkAppEntity?

        @Parameter(title: "App 3")
        public var app3: AppLinkAppEntity?

        @Parameter(title: "App 4")
        public var app4: AppLinkAppEntity?

        public static var parameterSummary: some ParameterSummary {
            When(\.$manuallySelectDevice, .equalTo, true) {
                When(\.$manuallySelectApps, .equalTo, true) {
                    Summary {
                        \.$manuallySelectDevice
                        \.$device
                        \.$manuallySelectApps
                        \.$app1
                        \.$app2
                        \.$app3
                        \.$app4
                    }
                } otherwise: {
                    Summary {
                        \.$manuallySelectDevice
                        \.$device
                        \.$manuallySelectApps
                    }
                }
            } otherwise: {
                When(\.$manuallySelectApps, .equalTo, true) {
                    Summary {
                        \.$manuallySelectDevice
                        \.$manuallySelectApps
                        \.$app1
                        \.$app2
                        \.$app3
                        \.$app4
                    }
                } otherwise: {
                    Summary {
                        \.$manuallySelectDevice
                        \.$manuallySelectApps
                    }
                }
            }
        }
        
        public var selectedDevice: DeviceAppEntity? {
            if (!manuallySelectDevice) {
                return nil
            }
            
            return device
        }
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
            Self.logger
                .debug("Pressing widget button \(button.button.apiValue ?? "nil") on device \(device?.name ?? "nil")")

            try await clickButton(button: button.button, device: device)

            return .result()
        }
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "SimpleClicker"
    )

    public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
        logger.debug("Pressing widget button \(button.apiValue ?? "nil") on device \(device?.name ?? "nil")")
        let modelContainer = getSharedModelContainer()
        
        let dataHandler = DataHandler(modelContainer: modelContainer)

        var targetDevice = device
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        guard let targetDevice else {
            logger.warning("Trying to press button with no device available")
            throw ApiError.noSavedDevices
        }

        if let deviceKey = button.apiValue {
            let success = await sendKeyToDeviceRawNotRecommended(
                location: targetDevice.location,
                key: deviceKey,
                mac: targetDevice.usingMac()
            )
            if !success {
                logger.warning("Error sending key to device")
                throw ApiError.deviceNotConnectable
            }
        }
    }
#endif
