import SwiftUI
import Intents
import SwiftData
import os
import AVFoundation
import AppIntents

#if os(macOS)
let BUTTON_WIDTH: CGFloat = 44
let BUTTON_HEIGHT: CGFloat = 36
#else
let BUTTON_WIDTH: CGFloat = 28
let BUTTON_HEIGHT: CGFloat = 20
#endif

struct RemoteView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    @Query(sort: \Device.name, order: .reverse) private var devices: [Device]
    
    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var controllerActor: DeviceControllerActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var navigationPath: NavigationPath = NavigationPath()
    @State private var privateListeningEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    
    @AppStorage("scanIPAutomatically") private var scanIpAutomatically: Bool = true
    @AppStorage("controlVolumeWithHWButtons") private var controlVolumeWithHWButtons: Bool = true
    
    enum FocusField: Hashable {
        case field
    }
    @FocusState private var focused: Bool
    
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
    @State var isSmallHeight: Bool = false
    
    private struct IsHorizontalKey: PreferenceKey {
        static var defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }
    private struct IsSmallHeight: PreferenceKey {
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
    
    let HORIZONTAL_MAX_HEIGHT: CGFloat = 400
    let HORIZONTAL_MIN_WIDTH: CGFloat = 400
    
    let TOOLBAR_SHRINK_WIDTH: CGFloat = 300
    
    @Namespace var animation
    
    var deviceStatusColor: Color {
        selectedDevice?.isOnline() ?? false ? Color.green : Color.secondary
    }
    
    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }
    
    func incrementButtonPressCount(_ key: RemoteButton) {
        buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
    }
    
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
    
    func donateAppLaunchIntent(_ link: AppLink) {
        let intent = LaunchAppIntent()
        intent.app = link.toAppEntity()
        intent.device = selectedDevice?.toAppEntity()
        intent.donate()
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
            .task(id: selectedDevice?.id, priority: .medium) {
                if let devId = selectedDevice?.id {
                    await self.scanningActor.refreshSelectedDeviceContinually(id: devId)
                }
            }
            .task(id: privateListeningEnabled) {
                if !privateListeningEnabled {
                    return
                }
                defer {
                    privateListeningEnabled = false
                }
                
                if let device = selectedDevice {
                    do {
                        try await listenContinually(location: device.location, rtcpPort: device.rtcpPort)
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
#if os(iOS)
            .task(id: inBackground || !controlVolumeWithHWButtons) {
                if inBackground || !controlVolumeWithHWButtons {
                    return
                }
                if let stream = await VolumeListener(session: AVAudioSession.sharedInstance()).events {
                    for await volumeEvent in stream {
                        let key: RemoteButton
                        switch volumeEvent.direction {
                        case .Up:
                            key = .volumeUp
                        case .Down:
                            key = .volumeDown
                        }
                        pressButton(key)
                    }
                } else {
                    Self.logger.error("Unable to get volume events stream")
                }
            }
#endif
        }
    }
    
    var remotePage: some View {
        ZStack {
            Color.clear
                .overlay(
                    GeometryReader { proxy in
                        let isHorizontal = proxy.size.width > proxy.size.height
                        let isSmallHeight = proxy.size.height <= 500
                        let isSmallWidth = proxy.size.width <= TOOLBAR_SHRINK_WIDTH
                        
                        Color.clear.preference(key: IsHorizontalKey.self, value: isHorizontal)
                        Color.clear.preference(key: IsSmallWidth.self, value: isSmallWidth)
                        Color.clear.preference(key: IsSmallHeight.self, value: isSmallHeight)
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
                .onPreferenceChange(IsSmallHeight.self) { value in
                    withAnimation {
                        isSmallHeight = value
                    }
                }
            HStack {
                Spacer()
                VStack(alignment: .center) {
                    if selectedDevice == nil {
                        // Banner Content Here
                        VStack(spacing: 2) {
                            HStack {
                                Label("Setup a device to get started :)", systemImage: "gear")
                            }
                            .padding(8)
                            .background(Color("AccentColor"))
                            .cornerRadius(6)
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                            Spacer().frame(maxHeight: 8)
                        }
                    }
                    
                    if isHorizontal {
                        horizontalBody(isSmallHeight: isSmallHeight)
#if os(iOS)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                keyboardLeaving = true
                                withAnimation {
                                    showKeyboardEntry = false
                                }
                            })
#endif
                    } else {
                        verticalBody(isSmallHeight: isSmallHeight)
#if os(iOS)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                keyboardLeaving = true
                                withAnimation {
                                    showKeyboardEntry = false
                                }
                            })
#endif
                    }
                    
#if os(iOS)
                    if showKeyboardEntry {
                        KeyboardEntry(str: $keyboardEntryText, onKeyPress: {char in
                            let _ = self.pressKey(char)
                        }, leaving: keyboardLeaving)
                        .zIndex(1)
                    }
#endif
                    
                }
                Spacer()
            }
            .disabled(selectedDevice == nil)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        keyboardLeaving = showKeyboardEntry
                        withAnimation {
                            showKeyboardEntry = !showKeyboardEntry
                        }
                    }) {
                        Label("Keyboard", systemImage: "keyboard")
                            .controlSize(.large)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedDevice == nil)
                    .font(.headline)
                }
#endif
                ToolbarItem(placement: .automatic) {
                    DevicePicker(
                        devices: devices,
                        device: $manuallySelectedDevice.withDefault(selectedDevice)
                    )
                    .font(.body)
                }
                
#if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: {pressButton(.power)}) {
                        Label("Power Off/On", systemImage: "power")
                            .foregroundStyle(Color.red, Color.red)
                            .labelStyle(.iconOnly)
                            .font(.headline)
                    }
                    .keyboardShortcut(.return)
                    .sensoryFeedback(.impact, trigger: buttonPressCount(.power))
                    .symbolEffect(.bounce, value: buttonPressCount(.power))
                    .disabled(selectedDevice == nil)
                }
#endif
            }
            .animation(.default, value: selectedDevice?.appsSorted?.count)
            .onAppear {
                let modelContainer = modelContext.container
                self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
                self.controllerActor = DeviceControllerActor()
            }
            .sensoryFeedback(.error, trigger: errorTrigger)
            .onChange(of: scenePhase) { _oldPhase, newPhase in
                inBackground = newPhase != .active
            }
        }
        .font(.title2)
        .fontDesign(.rounded)
        .controlSize(.extraLarge)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .labelStyle(.iconOnly)
    }
    
    func horizontalBody(isSmallHeight: Bool) -> some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: 20) {
                if !showKeyboardEntry {
                    Spacer()
                    // Center Controller with directional buttons
                    CenterController(pressCounter: buttonPressCount, action: pressButton)
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "centerController", in: animation)
                    
                }
                Spacer()
                
                VStack(alignment: .center) {
                    // Row with Back and Home buttons
                    TopBar(pressCounter: buttonPressCount, action: pressButton, onKeyPress: pressKey)
                        .matchedGeometryEffect(id: "topBar", in: animation)
                    
                    
                    if !showKeyboardEntry {
                        Spacer().frame(maxHeight: 60)
                        
                        // Grid of 9 buttons
                        ButtonGrid(pressCounter: buttonPressCount, action: pressButton, enabled: privateListeningEnabled ? Set([.privateListening]) : Set([]))
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "buttonGrid", in: animation)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: 600)
            
            if !showKeyboardEntry && (selectedDevice?.appsSorted?.count ?? 0) > 0 {
                Spacer()
                AppLinksView(appLinks: selectedDevice?.appsSorted?.map{$0.toAppEntity()} ?? [], rows: isSmallHeight ? 1 : 2, handleOpenApp: launchApp)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                
            }
            Spacer()
        }
    }
    
    func verticalBody(isSmallHeight: Bool) -> some View {
        VStack(alignment: .center, spacing: 10) {
            // Row with Back and Home buttons
            TopBar(pressCounter: buttonPressCount, action: pressButton, onKeyPress: pressKey)
                .matchedGeometryEffect(id: "topBar", in: animation)
            
            
            
            Spacer()
            
            // Center Controller with directional buttons
            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .matchedGeometryEffect(id: "centerController", in: animation)
            
            
            
            if !showKeyboardEntry {
                
                Spacer()
                // Grid of 9 buttons
                ButtonGrid(pressCounter: buttonPressCount, action: pressButton, enabled: privateListeningEnabled ? Set([.privateListening]) : Set([]))
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "buttonGrid", in: animation)
                
            }
            
            
            if !showKeyboardEntry && (selectedDevice?.appsSorted?.count ?? 0) > 0 {
                Spacer()
                AppLinksView(appLinks: selectedDevice?.appsSorted?.map{$0.toAppEntity()} ?? [], rows: isSmallHeight ? 1 : 2, handleOpenApp: launchApp)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                
            }
            Spacer()
        }
    }
    
    
    func launchApp(_ app: AppLinkAppEntity) {
        if let app = selectedDevice?.appsSorted?.first(where: { $0.id == app.id}) {
            
            donateAppLaunchIntent(app)
            incrementButtonPressCount(.inputAV1)
            app.lastSelected = Date.now
            let appId = app.id
            if let location = selectedDevice?.location {
                Task {
                    await controllerActor.openApp(location: location, app: appId)
                }
            }
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("Error saving app link \(error)")
            }
        }
    }
    
    func pressButton(_ button: RemoteButton) {
        incrementButtonPressCount(button)
        donateButtonIntent(button)
        if button == .privateListening {
            privateListeningEnabled.toggle()
            return
        }
        Task {
            if let device = selectedDevice {
                await controllerActor.sendKeyToDevice(location: device.location, mac: device.usingMac(), key: button)
            }
        }
    }
    
    func pressKey(_ key: KeyEquivalent) -> KeyPress.Result {
        let _ = Self.logger.trace("Getting keyboard press \(key.character)")
        if let device = selectedDevice {
            let location = device.location
            Task {
                await self.controllerActor.sendKeyPressTodevice(location: location, key: key)
            }
            return .handled
        }
        return .ignored
    }
}

extension Binding {
    func withDefault<T>(_ defaultValue: Optional<T>) -> Binding<Optional<T>> where Value == Optional<T> {
        return Binding<Optional<T>>(get: {
            self.wrappedValue ?? defaultValue
        }, set: { newValue in
            self.wrappedValue = newValue
        })
    }
    
    func withDefault<T>(_ defaultValue: T) -> Binding<T> where Value == Optional<T> {
        return Binding<T>(get: {
            self.wrappedValue ?? defaultValue
        }, set: { newValue in
            self.wrappedValue = newValue
        })
    }
}

#Preview("Remote horizontal") {
    RemoteView()
        .modelContainer(devicePreviewContainer)
}
