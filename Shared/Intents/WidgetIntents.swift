import AppIntents
import Foundation
import os

#if !os(tvOS)
    @available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
    public struct DeviceChoiceIntent: AppIntent, WidgetConfigurationIntent {
        public static var title: LocalizedStringResource = LocalizedStringResource("Choose a device", comment: "Configuration title for a settings page")
        public static var description = IntentDescription(LocalizedStringResource("Choose which device to target", comment: "Configuration description for a settings page"))

        public init() {}

        @Parameter(title: LocalizedStringResource("Manually select which device to remote control", comment: "Configuration field title controlling whether or not devices are manually selected"), default: false)
        public var manuallySelectDevice: Bool

        @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
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
        public static var title: LocalizedStringResource = LocalizedStringResource("Choose a device and apps", comment: "Configuration title for a settings page")
        public static var description = IntentDescription(LocalizedStringResource("Choose which device to target and select apps to view", comment: "Configuration description for a settings page"))

        public init() {}

        @Parameter(title: LocalizedStringResource("Manually select which device to remote control", comment: "Configuration field title controlling whether or not devices are manually selected"), default: false)
        public var manuallySelectDevice: Bool

        @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
        public var device: DeviceAppEntity?

        @Parameter(title: LocalizedStringResource("Manually select which apps to show", comment: "Configuration field title controlling whether or not apps are manually selected"), default: false)
        public var manuallySelectApps: Bool

        @Parameter(title: LocalizedStringResource("App 1", comment: "Configuration field title for selecting the first app"))
        public var app1: AppLinkAppEntity?

        @Parameter(title: LocalizedStringResource("App 2", comment: "Configuration field title for selecting the second app"))
        public var app2: AppLinkAppEntity?

        @Parameter(title: LocalizedStringResource("App 3", comment: "Configuration field title for selecting the third app"))
        public var app3: AppLinkAppEntity?

        @Parameter(title: LocalizedStringResource("App 4", comment: "Configuration field title for selecting the fourth app"))
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
        
        public static var title: LocalizedStringResource = LocalizedStringResource("Press a button", comment: "Configuration title for a button press action")
        public static var description = IntentDescription(LocalizedStringResource("Press a button on the connected device", comment: "Configuration description for a button press action"))

        public init() {}

        @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
        var device: DeviceAppEntity?

        @Parameter(title: LocalizedStringResource("Button", comment: "Configuration field title for a button selection field"))
        var button: RemoteButtonAppEnum

        public static var parameterSummary: some ParameterSummary {
            Summary("Press \(\.$button) on \(\.$device)")
        }

        public static var predictionConfiguration: some IntentPredictionConfiguration {
            IntentPrediction(parameters: (\.$button, \.$device)) { button, device in
                DisplayRepresentation(
                    title: LocalizedStringResource("Press \(button) on \(device!)", comment: "Title for a shortcut action")
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
