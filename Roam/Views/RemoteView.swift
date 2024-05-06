import AppIntents
import AsyncAlgorithms
import AVFoundation
import Intents
import os
import StoreKit
import SwiftData
import SwiftUI

#if os(macOS) || os(visionOS)
    let globalButtonWidth: CGFloat = 44
    let globalButtonHeight: CGFloat = 36
    let globalButtonSpacing: CGFloat = 10
    let globalAppLinkShrinkWidth: CGFloat = 500
#elseif os(tvOS)
    let globalButtonWidth: CGFloat = 60
    let globalButtonSpacing: CGFloat = 30
    let globalButtonHeight: CGFloat = 50
    let globalAppLinkShrinkWidth: CGFloat = 600
#else
    let globalButtonSpacing: CGFloat = 10
    let globalButtonWidth: CGFloat = 28
    let globalButtonHeight: CGFloat = 20
    let globalAppLinkShrinkWidth = 700
#endif

let globalToolbarShrinkWidth: CGFloat = 300

let globalMajorActions: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name, order: .reverse)]
    )
    fd.relationshipKeyPathsForPrefetching = []
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]

    return fd
}()

private let messageFetchDescriptor: FetchDescriptor<Message> = {
    var fd = FetchDescriptor(
        predicate: #Predicate<Message> {
            !$0.viewed
        }
    )
    return fd
}()

struct RemoteView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Query(deviceFetchDescriptor) private var devices: [Device]
    @Query(messageFetchDescriptor) private var unreadMessages: [Message]

    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    @State private var ecpSession: ECPSession?
    @StateObject private var networkMonitor = NetworkMonitor()
    var headphonesModeDisabled: Bool {
        !(selectedDevice?.supportsDatagram ?? true)
    }

    var hideUIForKeyboardEntry: Bool {
        #if os(iOS)
            return showKeyboardEntry
        #else
            return false
        #endif
    }

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true

    @Environment(\.verticalSizeClass) var verticalSizeClass

    private var appLinkRows: Int {
        #if os(macOS) || os(tvOS)
            return 2
        #else
            if verticalSizeClass == .compact {
                return 1
            } else {
                return 2
            }
        #endif
    }

    @FocusState private var focused: Bool

    #if os(iOS)
        @State var windowScene: UIWindowScene?
    #endif

    private var selectedDevice: Device? {
        manuallySelectedDevice ?? devices.min { d1, d2 in
            (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
        }
    }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State var isHorizontal: Bool = false
    @State var isSmallWidth: Bool = true

    @State var volume: Float = 0
    @State var lastVolumeChangeFromTv: Bool = false

    private struct IsHorizontalKey: PreferenceKey {
        static var defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    private struct IsSmallWidth: PreferenceKey {
        static var defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    @Namespace var animation

    var deviceActor: DeviceActor {
        DeviceActor(modelContainer: modelContext.container)
    }

    var deviceStatusColor: Color {
        selectedDevice?.isOnline() ?? false ? Color.green : Color.secondary
    }

    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }

    func incrementButtonPressCount(_ key: RemoteButton) {
        buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
    }

    #if !os(tvOS) && !APPCLIP
        func donateButtonIntent(_ key: RemoteButton) {
            switch key {
            case .power:
                let intent = PowerIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            case .select:
                let intent = OkIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            case .mute:
                let intent = MuteIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            case .volumeUp:
                let intent = VolumeUpIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            case .volumeDown:
                let intent = VolumeDownIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            case .playPause:
                let intent = PlayIntent()
                intent.device = selectedDevice?.toAppEntity()
                intent.donate()
            default:
                return
            }
        }

        func donateAppLaunchIntent(_ link: AppLinkAppEntity) {
            let intent = LaunchAppIntent()
            intent.app = link
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        }
    #endif

    var body: some View {
        if runningInPreview {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath) {
                remotePage
            }
        } else {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath) {
                remotePage
            }
            .task(priority: .userInitiated) {
                while true {
                    if Task.isCancelled {
                        return
                    }
                    Self.logger.info("Refreshing messages")
                    var descriptor = FetchDescriptor<Message>(
                        predicate: #Predicate {
                            $0.fetchedBackend == true
                        },
                        sortBy: [SortDescriptor(\.id, order: .reverse)]
                    )
                    descriptor.fetchLimit = 1

                    let lastMessage = try? modelContext.fetch(descriptor).last
                    let container = modelContext.container
                    Self.logger.info("Refreshing messages with last message \(String(describing: lastMessage?.id))")
                    if lastMessage != nil {
                        let results = await refreshMessages(
                            modelContainer: container,
                            latestMessageId: lastMessage?.id,
                            viewed: false
                        )
                        Self.logger.info("Sleeping for an hour after getting \(results) messages")
                    } else {
                        Self.logger.info("Not refreshing messages because no lastMessageId")
                    }
                    try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000 * 3600)
                }
            }

            #if os(iOS) && !APPCLIP
            .task(id: devices.count, priority: .background) {
                    // Send devices to connected watch
                    WatchConnectivity.shared.transferDevices(devices: devices.map { $0.toAppEntity() })

                    for await _ in AsyncTimerSequence.repeating(every: .seconds(60 * 10)) {
                        WatchConnectivity.shared.transferDevices(devices: devices.map { $0.toAppEntity() })
                    }
                }
            #endif
                .onAppear {
                    networkMonitor.startMonitoring()
                }
                .onDisappear {
                    networkMonitor.stopMonitoring()
                }
                .task(priority: .background) {
                    await withDiscardingTaskGroup { taskGroup in
                        taskGroup.addTask {
                            await scanningActor.scanSSDPContinually()
                        }

                        if scanIpAutomatically {
                            taskGroup.addTask {
                                await scanningActor.scanIPV4Once()
                            }
                        }
                    }
                }
                .task(id: selectedDevice?.location, priority: .medium) {
                    Self.logger
                        .info("Creating ecp session with location \(String(describing: selectedDevice?.location))")
                    let oldECP = ecpSession
                    Task.detached {
                        await oldECP?.close()
                    }
                    ecpSession = nil
                    if let device = selectedDevice?.toAppEntity() {
                        do {
                            ecpSession = try ECPSession(device: device)
                            try await ecpSession?.configure()
                        } catch {
                            Self.logger.error("Error creating ECPSession: \(error)")
                        }
                    } else {
                        ecpSession = nil
                    }
                }
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    if let devId = selectedDevice?.persistentModelID {
                        await scanningActor.refreshSelectedDeviceContinually(id: devId)
                    }
                }
                .task(id: "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")") {
                    if !headphonesModeEnabled {
                        return
                    }
                    defer {
                        headphonesModeEnabled = false
                    }

                    if let device = selectedDevice, let ecpSession {
                        do {
                            try await listenContinually(
                                ecpSession: ecpSession,
                                location: device.location,
                                rtcpPort: device.rtcpPort
                            )
                            Self.logger.info("Listencontinually returned")
                        } catch {
                            Self.logger.warning("Catching error in pl handler \(error)")
                            // Increment errorTrigger if the error is anything but a cancellation error
                            if !(error is CancellationError) {
                                Self.logger.debug("Non-cancellation error in PL")
                                errorTrigger += 1
                            }
                        }
                    }
                }
        }
    }

    var remotePage: some View {
        ZStack {
            Color.clear
                .overlay(
                    GeometryReader { proxy in
                        let isHorizontal = proxy.size.width > proxy.size.height
                        let isSmallWidth = proxy.size.width <= globalToolbarShrinkWidth

                        Color.clear.preference(key: IsHorizontalKey.self, value: isHorizontal)
                        Color.clear.preference(key: IsSmallWidth.self, value: isSmallWidth)
                    }
                )
                .onPreferenceChange(IsHorizontalKey.self) { value in
                    withAnimation {
                        isHorizontal = value
                    }
                }
                .onPreferenceChange(IsSmallWidth.self) { value in
                    withAnimation {
                        isSmallWidth = value
                    }
                }

            HStack {
                Spacer()
                VStack(alignment: .center, spacing: 10) {
                    #if os(tvOS)
                        HStack {
                            HStack {
                                Button(action: {
                                    keyboardLeaving = showKeyboardEntry
                                    withAnimation {
                                        showKeyboardEntry = !showKeyboardEntry
                                    }
                                }, label: {
                                    Label("", systemImage: "keyboard")
                                })
                                .labelStyle(.iconOnly)
                                .disabled(selectedDevice == nil)
                                .font(.headline)
                                Spacer()
                            }
                            .focusSection()
                            HStack {
                                Spacer()
                                DevicePicker(
                                    devices: devices,
                                    device: $manuallySelectedDevice.withDefault(selectedDevice)
                                )
                                .font(.body)
                            }
                            .focusSection()
                        }

                    #endif

                    if verticalSizeClass == .compact, !hideUIForKeyboardEntry {
                        if unreadMessages.count > 0 {
                            NotificationBanner(message: "Scott chatted you back", onClick: {
                                #if os(macOS)
                                    openWindow(id: "messages")
                                #else
                                    appDelegate.navigationPath.append(NavigationDestination.messageDestination)
                                #endif
                            }, level: .info)
                                .offset(y: -20)
                                .padding(.bottom, -16)
                        }
                        networkConnectivityBanner
                            .offset(y: -20)
                            .padding(.bottom, -16)
                    }

                    if isHorizontal {
                        horizontalBody()
                    } else {
                        verticalBody()
                    }

                    if hideUIForKeyboardEntry {
                        Spacer()
                    } else {
                        if verticalSizeClass != .compact {
                            if unreadMessages.count > 0 {
                                NotificationBanner(message: "Scott chatted you back", onClick: {
                                    #if os(macOS)
                                        openWindow(id: "messages")
                                    #else
                                        appDelegate.navigationPath.append(NavigationDestination.messageDestination)
                                    #endif
                                }, level: .info)
                            }
                            networkConnectivityBanner
                            Spacer().frame(maxHeight: 10)
                        }
                    }
                }
                Spacer()
            }
            #if !os(macOS)
            .overlay {
                #if os(iOS)
                    if controlVolumeWithHWButtons, !headphonesModeEnabled {
                        CustomVolumeSliderOverlay(volume: $volume) { volumeEvent in
                            let key: RemoteButton = switch volumeEvent.direction {
                            case .up:
                                .volumeUp
                            case .down:
                                .volumeDown
                            }
                            Self.logger
                                .info(
                                    "Pressing button \(String(describing: key)) with volume \(volume) after volume event \(String(describing: volumeEvent))"
                                )
                            pressButton(key)
                        }.id("VolumeOverlay")
                            .frame(maxWidth: 1)
                    }
                #endif

                if showKeyboardEntry {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack {
                                Button(action: {
                                    keyboardLeaving = true
                                    withAnimation {
                                        showKeyboardEntry = false
                                    }

                                }, label: {
                                    ZStack {
                                        Rectangle().foregroundColor(.clear)
                                        VStack {
                                            Spacer()
                                        }
                                    }.contentShape(Rectangle())
                                })
                                .frame(maxHeight: .infinity)
                                .buttonStyle(.plain)

                                KeyboardEntry(
                                    str: $keyboardEntryText,
                                    showing: $showKeyboardEntry,
                                    onKeyPress: { char in
                                        pressKey(char)
                                    },
                                    leaving: keyboardLeaving
                                )
                                .padding(.bottom, 10)
                                .padding(.horizontal, 10)
                                .zIndex(1)
                            }.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        }
                        .scrollIndicators(.never)
                        #if !os(visionOS)
                            .scrollDismissesKeyboard(.immediately)
                        #endif
                    }
                }
            }
            #endif
            .onKeyDown({ key in pressKey(key) }, enabled: !showKeyboardEntry)
            .disabled(selectedDevice == nil)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            #if !os(tvOS)
                .toolbar {
                    #if !os(macOS)
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                keyboardLeaving = showKeyboardEntry
                                withAnimation {
                                    showKeyboardEntry = !showKeyboardEntry
                                }
                            }) {
                                Label("Keyboard", systemImage: "keyboard")
                                    .controlSize(.large)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(selectedDevice == nil)
                            .font(.headline)
                        }
                    #endif
                    #if os(macOS)
                        ToolbarItem(placement: .navigation) {
                            DevicePicker(
                                devices: devices,
                                device: $manuallySelectedDevice.withDefault(selectedDevice)
                            )
                            .font(.body)
                        }
                    #else
                        ToolbarItem(placement: .topBarTrailing) {
                            DevicePicker(
                                devices: devices,
                                device: $manuallySelectedDevice.withDefault(selectedDevice)
                            )
                            .font(.body)
                        }
                    #endif
                }
            #endif
            #if !APPCLIP
                .overlay {
                    if selectedDevice == nil {
                        VStack(spacing: 2) {
                            Spacer()
                            #if os(macOS)
                                SettingsLink {
                                    Label("Setup a device to get started :)", systemImage: "gear")
                                        .frame(maxWidth: .infinity)
                                        .font(.callout)
                                        .padding(16)
                                        .background(Color("AccentColor"))
                                        .cornerRadius(6)
                                        .padding(.horizontal, 40)
                                }
                                .shadow(radius: 4)

                            #else
                                NavigationLink(value: NavigationDestination.settingsDestination(.global)) {
                                    Label("Setup a device to get started :)", systemImage: "gear")
                                        .frame(maxWidth: .infinity)
                                        .font(.callout)
                                        .padding(16)
                                        .background(Color("AccentColor"))
                                        .cornerRadius(6)
                                        .padding(.horizontal, 40)
                                }
                                .shadow(radius: 4)
                            #endif

                            Spacer()
                            Spacer()
                            Spacer()
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.titleAndIcon)
                    }
                }
            #endif
                .onAppear {
                    modelContext.processPendingChanges()
                }
                .onAppear {
                    let modelContainer = modelContext.container
                    scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
                }
            #if !os(visionOS)
                .sensoryFeedback(.error, trigger: errorTrigger)
            #endif
                .onChange(of: scenePhase) { _, newPhase in
                    inBackground = newPhase != .active
                }
            #if os(macOS)
                .onChange(of: appDelegate.messagingWindowOpenTrigger) { _, new in
                    if new != nil {
                        openWindow(id: "messages")
                    }
                }
            #endif
        }
        .font(.title2)
        .fontDesign(.rounded)
        #if !os(tvOS)
            .controlSize(.extraLarge)
        #endif
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .labelStyle(.iconOnly)
            .onOpenURL { incomingURL in
                Self.logger.info("App was opened via URL: \(incomingURL)")
                handleIncomingURL(incomingURL)
            }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.host == "roam.msd3.io" else {
            return
        }

        var path = url.pathComponents
        path.removeFirst()
        guard let dlpath = path.first, dlpath == "deep-link" || dlpath == "appclip" else {
            Self.logger.error("Getting Invalid URL path")
            return
        }
        let firstPath = path.first
        path.removeFirst()
        guard let action = path.first ?? firstPath else {
            Self.logger.warning("Getting url deep link with no action")
            return
        }
        Self.logger.info("Getting action \(action)")

        if action == "add-device" || action == "appclip" || action == "scan" {
            let queryParams = URLComponents(string: url.absoluteString)?.queryItems
            let name = queryParams?.first(where: { $0.name == "name" })?.value ?? "New device"
            // Get location param as location=IP or p=IPV4Hex
            guard let location = queryParams?.first(where: { $0.name == "location" })?.value ??
                queryParams?.first(where: { $0.name == "p" })?.value.flatMap({ hex in
                    let ipComponents = stride(from: 0, to: hex.count, by: 2).compactMap { index -> UInt8? in
                        let start = hex.index(hex.startIndex, offsetBy: index)
                        let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                        return UInt8(hex[start ..< end], radix: 16)
                    }
                    guard ipComponents.count == 4 else { return nil }
                    return ipComponents.map(String.init).joined(separator: ".")
                })
            else {
                Self.logger.error("Trying to add device with no location")
                return
            }

            let udn = queryParams?.first(where: { $0.name == "udn" })?.value ?? "roam:newdevice-\(UUID().uuidString)"

            let newDevice = Device(
                name: name,
                location: location,
                lastSelectedAt: Date.now,
                udn: udn
            )

            Task {
                modelContext.insert(newDevice)
                do {
                    try modelContext.save()
                } catch {
                    Self.logger.error("Error inserting new device \(error)")
                    return
                }

                await saveDevice(
                    existingDeviceId: newDevice.persistentModelID,
                    existingUDN: newDevice.udn,
                    newIP: location,
                    newDeviceName: name,
                    deviceActor: DeviceActor(
                        modelContainer: modelContext.container
                    )
                )
            }
        }
        #if !APPCLIP
            if action == "feedback" {
                Self.logger.info("Attempting to open app debugging")
                appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.debugging))
            } else if action == "settings" {
                Self.logger.info("Attempting to open app settings")
                appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.global))
            } else if action == "about" {
                Self.logger.info("Attempting to open about page")
                appDelegate.navigationPath.append(NavigationDestination.aboutDestination)
            } else if action == "messages" {
                Self.logger.info("Attempting to open messages page")
                appDelegate.navigationPath.append(NavigationDestination.messageDestination)
            }
        #endif
    }

    @ViewBuilder
    var networkConnectivityBanner: some View {
        if networkMonitor.networkConnection == .none {
            NotificationBanner(message: "No network connection")
        } else if networkMonitor.networkConnection == .remote || networkMonitor.networkConnection == .other {
            NotificationBanner(message: "No WiFi connection detected", level: .warning)
        }
    }

    func horizontalBody() -> some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: globalButtonSpacing * 2) {
                if !hideUIForKeyboardEntry {
                    Spacer()
                    VStack {
                        Spacer().frame(maxHeight: 100)
                        // Center Controller with directional buttons
                        CenterController(pressCounter: buttonPressCount, action: pressButton)
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "centerController", in: animation)
                        Spacer().frame(maxHeight: 100)
                    }
                    #if os(macOS) || os(tvOS)
                    .focusSection()
                    #endif
                }
                Spacer()

                VStack(alignment: .center) {
                    // Row with Back and Home buttons
                    TopBar(pressCounter: buttonPressCount, action: pressButton)
                        .matchedGeometryEffect(id: "topBar", in: animation)
                    #if os(macOS) || os(tvOS)
                        .focusSection()
                    #endif

                    if !hideUIForKeyboardEntry {
                        Spacer().frame(maxHeight: 60)

                        // Grid of 9 buttons
                        ButtonGrid(
                            pressCounter: buttonPressCount,
                            action: pressButton,
                            enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                            disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                        )
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "buttonGrid", in: animation)
#if os(macOS) || os(tvOS)
.focusSection()
#endif
                    }
                }
                #if os(macOS) || os(tvOS)
                .focusSection()
                #endif
                Spacer()
            }
            #if os(macOS) || os(tvOS)
            .focusSection()
            #endif
            .frame(maxWidth: 600)

            if !showKeyboardEntry {
                Spacer()
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if os(macOS) || os(tvOS)
                    .focusSection()
                #endif
                #if !os(visionOS)
                .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif
            } else {
                Spacer()
            }
            Spacer()
        }
    }

    func shouldRequestReview() -> Bool {
        let userActionCount = UserDefaults.standard.integer(forKey: UserDefaultKeys.userMajorActionCount)
        let lastVersionAsked = UserDefaults.standard.string(forKey: UserDefaultKeys.appVersionAtLastReviewRequest)
        let lastDateAsked = UserDefaults.standard.object(forKey: UserDefaultKeys.dateOfLastReviewRequest) as? Date

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else {
            return false
        }

        if userActionCount < 10 {
            return false
        }

        if currentVersion == lastVersionAsked {
            return false
        }

        if let lastDate = lastDateAsked, Calendar.current.date(byAdding: .month, value: 1, to: lastDate)! > Date() {
            return false
        }

        return true
    }

    func handleMajorUserAction() {
        // Increment user action count
        var count = UserDefaults.standard.integer(forKey: UserDefaultKeys.userMajorActionCount)
        count += 1
        UserDefaults.standard.set(count, forKey: UserDefaultKeys.userMajorActionCount)

        if shouldRequestReview() {
            #if os(iOS)
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
            #endif

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                #if os(iOS)
                    SKStoreReviewController.requestReview(in: windowScene)
                #elseif !os(visionOS) && !os(tvOS)
                    SKStoreReviewController.requestReview()
                #endif
            }

            UserDefaults.standard.set(
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
                forKey: UserDefaultKeys.appVersionAtLastReviewRequest
            )
            UserDefaults.standard.set(Date(), forKey: UserDefaultKeys.dateOfLastReviewRequest)
        }
    }

    func verticalBody() -> some View {
        VStack(alignment: .center, spacing: 20) {
            #if os(macOS) || os(visionOS)
                Spacer()
            #endif

            // Row with Back and Home buttons
            TopBar(pressCounter: buttonPressCount, action: pressButton)
                .matchedGeometryEffect(id: "topBar", in: animation)

            Spacer()

            // Center Controller with directional buttons
            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "centerController", in: animation)

            if !hideUIForKeyboardEntry {
                Spacer()
                // Grid of 9 buttons
                ButtonGrid(
                    pressCounter: buttonPressCount,
                    action: pressButton,
                    enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                    disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                )
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "buttonGrid", in: animation)
            }

            if !showKeyboardEntry {
                Spacer()
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if !os(visionOS)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif

                Spacer()
            } else {
                Spacer()
            }
        }
    }

    func launchApp(_ app: AppLinkAppEntity) {
        #if !os(tvOS) && !APPCLIP
            donateAppLaunchIntent(app)
        #endif
        incrementButtonPressCount(.inputAV1)
        Task {
            do {
                try await ecpSession?.openApp(app)
            } catch {
                Self.logger.error("Error opening app \(app.id): \(error)")
            }
        }
        Task {
            do {
                try await DeviceActor(modelContainer: modelContext.container).setSelectedApp(app.modelId)
            } catch {
                Self.logger.error("Error marking app \(app.id) as selected")
            }
        }
    }

    func pressButton(_ button: RemoteButton) {
        incrementButtonPressCount(button)
        if globalMajorActions.contains(button) {
            handleMajorUserAction()
        }
        #if !os(tvOS) && !APPCLIP
            donateButtonIntent(button)
        #endif
        if button == .headphonesMode {
            headphonesModeEnabled.toggle()
            return
        }

        Task {
            do {
                try await ecpSession?.pressButton(button)
            } catch {
                Self.logger.info("Error sending button to device via ecp: \(error)")
            }
        }
    }

    func pressKey(_ key: KeyEquivalent) {
        Self.logger.trace("Getting keyboard press \(key.character)")
        if let button = RemoteButton.fromCharacter(character: key.character) {
            incrementButtonPressCount(button)
            if globalMajorActions.contains(button) {
                handleMajorUserAction()
            }
            #if !os(tvOS) && !APPCLIP
                donateButtonIntent(button)
            #endif
        }

        if let ecpSession {
            Self.logger.info("Getting ecp session to send data to")
            Task {
                do {
                    try await ecpSession.pressCharacter(key.character)
                } catch {
                    Self.logger.error("Error pressing character \(key.character) on device \(error)")
                }
            }
            return
        }
    }
}

#Preview("Remote horizontal") {
    RemoteView()
        .modelContainer(previewContainer)
}
