import SwiftUI
import AsyncAlgorithms
import Intents
import SwiftData
import os
import AVFoundation
import AppIntents
import StoreKit


#if os(macOS) || os(visionOS)
let BUTTON_WIDTH: CGFloat = 44
let BUTTON_HEIGHT: CGFloat = 36
let BUTTON_SPACING: CGFloat = 10
let APP_LINK_SHRINK_WIDTH: CGFloat = 500
#elseif os(tvOS)
let BUTTON_WIDTH: CGFloat = 60
let BUTTON_SPACING: CGFloat = 30
let BUTTON_HEIGHT: CGFloat = 50
let APP_LINK_SHRINK_WIDTH: CGFloat = 600
#else
let BUTTON_SPACING: CGFloat = 10
let BUTTON_WIDTH: CGFloat = 28
let BUTTON_HEIGHT: CGFloat = 20
let APP_LINK_SHRINK_WIDTH = 700
#endif

let HORIZONTAL_MAX_HEIGHT: CGFloat = 400
let HORIZONTAL_MIN_WIDTH: CGFloat = 400

let TOOLBAR_SHRINK_WIDTH: CGFloat = 300


let MAJOR_ACTIONS: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

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

struct RemoteView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    @Query(deviceFetchDescriptor) private var devices: [Device]
    
    @Binding var showKeyboardShortcuts: Bool
    
    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var navigationPath: NavigationPath = NavigationPath()
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    @State private var ecpSession: ECPSession? = nil
    @StateObject private var networkMonitor = NetworkMonitor()
    var headphonesModeDisabled: Bool {
        return !(selectedDevice?.supportsDatagram ?? true)
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
    @State var windowScene: UIWindowScene? = nil
#endif
    
    private var selectedDevice: Device? {
        return manuallySelectedDevice ?? devices.min { d1, d2 in
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
    
#if !os(tvOS)
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
    
    private func openAppSettings() {
        Self.logger.info("Attempting to open app settings")
        #if os(macOS)
        if let settingsUrl = URL(string: "x-apple.systempreferences:com.msdrigg.roam") {
            NSWorkspace.shared.open(settingsUrl)
        }
        #else
        navigationPath.append(SettingsDestination.Global)
        #endif
    }
    
    var body: some View {
        if runningInPreview {
            SettingsNavigationWrapper(path: $navigationPath) {
                remotePage
            }
        } else {
            SettingsNavigationWrapper(path: $navigationPath) {
                remotePage
            }
#if os(iOS)
            .task(id: devices.count, priority: .background) {
                // Send devices to connected watch
                WatchConnectivity.shared.transferDevices(devices: devices.map{$0.toAppEntity()})
                
                for await _ in AsyncTimerSequence.repeating(every: .seconds(60 * 10)) {
                    WatchConnectivity.shared.transferDevices(devices: devices.map{$0.toAppEntity()})
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
                        await self.scanningActor.scanSSDPContinually()
                    }
                    
                    if scanIpAutomatically {
                        taskGroup.addTask {
                            await self.scanningActor.scanIPV4Once()
                        }
                    }
                }
            }
            .task(id: selectedDevice?.location, priority: .medium) {
                Self.logger.info("Creating ecp session with location \(String(describing: selectedDevice?.location))")
                let oldECP = self.ecpSession
                Task.detached {
                    await oldECP?.close()
                }
                self.ecpSession = nil
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
                    await self.scanningActor.refreshSelectedDeviceContinually(id: devId)
                }
            }
            .task(id: "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")") {
                if !headphonesModeEnabled {
                    return
                }
                defer {
                    headphonesModeEnabled = false
                }
                
                if let device = selectedDevice, let ecpSession = ecpSession {
                    do {
                        try await listenContinually(ecpSession: ecpSession, location: device.location, rtcpPort: device.rtcpPort)
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
                        let isSmallWidth = proxy.size.width <= TOOLBAR_SHRINK_WIDTH
                        
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
                VStack(alignment: .center) {
#if os(tvOS)
                    HStack{
                        HStack {
                            Button(action: {
                                keyboardLeaving = showKeyboardEntry
                                withAnimation {
                                    showKeyboardEntry = !showKeyboardEntry
                                }
                            }) {
                                Label("", systemImage: "keyboard")
                            }
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
                    
                    
                    if verticalSizeClass == .compact && !hideUIForKeyboardEntry {
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
                            networkConnectivityBanner
                                .padding(.bottom, 12)
                        }
                    }
                }
                Spacer()
            }
#if !os(macOS)
            .overlay {
#if os(iOS)
                if controlVolumeWithHWButtons && !headphonesModeEnabled {
                    CustomVolumeSliderOverlay(volume: $volume) { volumeEvent in
                        let key: RemoteButton
                        switch volumeEvent.direction {
                        case .Up:
                            key = .volumeUp
                        case .Down:
                            key = .volumeDown
                        }
                        Self.logger.info("Pressing button \(String(describing: key)) with volume \(volume) after volume event \(String(describing: volumeEvent))")
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
                                    
                                }) {
                                    ZStack {
                                        Rectangle() .foregroundColor(.clear)
                                        VStack {
                                            Spacer()
                                        }
                                    }            .contentShape(Rectangle())
                                }
                                .frame(maxHeight: .infinity)
                                .buttonStyle(.plain)
                                
                                KeyboardEntry(str: $keyboardEntryText, showing: $showKeyboardEntry, onKeyPress: {char in
                                    let _ = self.pressKey(char)
                                }, leaving: keyboardLeaving)
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
            .onKeyDown({key in pressKey(key)}, enabled: !showKeyboardEntry)
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
                        NavigationLink(value: SettingsDestination.Global) {
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
            .onAppear {
                modelContext.processPendingChanges()
            }
            .onAppear {
                let modelContainer = modelContext.container
                self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
            }
#if !os(visionOS)
            .sensoryFeedback(.error, trigger: errorTrigger)
#endif
            .onChange(of: scenePhase) { _oldPhase, newPhase in
                inBackground = newPhase != .active
            }
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutPanel()
        }
        .font(.title2)
        .fontDesign(.rounded)
#if !os(tvOS)
        .controlSize(.extraLarge)
#endif
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .labelStyle(.iconOnly)
        /// Responds to any URLs opened with our app. In this case, the URLs
        /// defined inside the URL Types section.
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
        guard let dlpath = path.first, dlpath == "deep-link" else {
            Self.logger.error("Getting Invalid URL path")
            return
        }
        path.removeFirst()

        guard let action = path.first else {
            Self.logger.warning("Getting url deep link with no action")
            return
        }
        Self.logger.info("Getting action \(action)")
        
        if action == "add-device" {
            // Need to parse device info from query parameters
        } else if action == "feedback" {
            //
        } else if action == "settings" {
            openAppSettings()
        } else {
            Self.logger.warning("Trying to open app with back action \(action)")
        }
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
            HStack(alignment: .center, spacing: BUTTON_SPACING * 2) {
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
#if os(macOS) || os(tvOS)
                        .focusSection()
#endif
                        .matchedGeometryEffect(id: "topBar", in: animation)
                    
                    if !hideUIForKeyboardEntry {
                        Spacer().frame(maxHeight: 60)
                        
                        // Grid of 9 buttons
                        ButtonGrid(pressCounter: buttonPressCount, action: pressButton, enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]), disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([]) )
#if os(macOS) || os(tvOS)
                            .focusSection()
#endif
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "buttonGrid", in: animation)
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
#if os(macOS) || os(tvOS)
                    .focusSection()
#endif
#if !os(visionOS)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
#endif
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                
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
        
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
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
            guard let windowScene =  UIApplication.shared.connectedScenes.first as? UIWindowScene else {
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
            
            UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"), forKey: UserDefaultKeys.appVersionAtLastReviewRequest)
            UserDefaults.standard.set(Date(), forKey: UserDefaultKeys.dateOfLastReviewRequest)
        }
    }
    
    func verticalBody() -> some View {
        VStack(alignment: .center, spacing: 10) {
            // Row with Back and Home buttons
            Spacer().frame(maxHeight: 60)
            TopBar(pressCounter: buttonPressCount, action: pressButton)
                .matchedGeometryEffect(id: "topBar", in: animation)
            
            
            
            Spacer().frame(maxHeight: 60)
            
            // Center Controller with directional buttons
            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "centerController", in: animation)
            
            
            
            if !hideUIForKeyboardEntry {
                Spacer().frame(maxHeight: 60)
                // Grid of 9 buttons
                ButtonGrid(pressCounter: buttonPressCount, action: pressButton, enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]), disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([]) )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "buttonGrid", in: animation)
                
            }
            
            
            if !showKeyboardEntry {
                Spacer().frame(maxHeight: 60)
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
#if !os(visionOS)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
#endif
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                
            } else {
                Spacer()
            }
            Spacer().frame(maxHeight: 60)
        }
    }
    
    
    func launchApp(_ app: AppLinkAppEntity) {
#if !os(tvOS)
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
        if MAJOR_ACTIONS.contains(button) {
            handleMajorUserAction()
        }
#if !os(tvOS)
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
    
    func pressKey(_ key: KeyEquivalent) -> Void {
        Self.logger.trace("Getting keyboard press \(key.character)")
        if let button = RemoteButton.fromCharacter(character: key.character){
            
            incrementButtonPressCount(button)
            if MAJOR_ACTIONS.contains(button) {
                handleMajorUserAction()
            }
#if !os(tvOS)
            donateButtonIntent(button)
#endif
        }

        
        if let ecpSession = ecpSession {
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
        return
    }
}


#Preview("Remote horizontal") {
    RemoteView(showKeyboardShortcuts: Binding.constant(false))
        .modelContainer(devicePreviewContainer)
}
