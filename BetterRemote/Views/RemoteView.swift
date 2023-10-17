import SwiftUI
import Intents
import SwiftData
import os
import AVFoundation
import AppIntents

struct RemoteView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    @Query(sort: \Device.name, order: .reverse) private var devices: [Device]
    
    @State private var scanningActor: DeviceControllerActor!
    @State private var controllerActor: DeviceControllerActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var showSettingsView: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var screenSize: CGSize = .zero
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    
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
    
    private struct SizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }
    
    let HORIZONTAL_MAX_HEIGHT: CGFloat = 400
    let HORIZONTAL_MIN_WIDTH: CGFloat = 400
    
    var isHorizontal: Bool {
        return screenSize.width > screenSize.height
    }
    
    let TOOLBAR_SHRINK_WIDTH: CGFloat = 300
    
    var isSmallWidth: Bool {
        screenSize.width <= TOOLBAR_SHRINK_WIDTH
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
        NavigationStack {
            ZStack {
                Color.clear
                    .overlay(
                        GeometryReader { proxy in
                            Color.clear.preference(key: SizePreferenceKey.self, value: proxy.size)
                        }
                    )
                    .onPreferenceChange(SizePreferenceKey.self) { value in
                        screenSize = value
                    }
                HStack {
                    Spacer()
                    VStack(alignment: .center) {
                        if isHorizontal {
                            horizontalBody
                            #if os(iOS)
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .global) { _ in
                                    showKeyboardEntry = false
                                }
                            #endif
                        } else {
                            verticalBody
                            #if os(iOS)
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .global) { _ in
                                    showKeyboardEntry = false
                                }
                            #endif
                        }
                        
#if os(iOS)
                        if showKeyboardEntry {
                            KeyboardEntry(str: $keyboardEntryText, onKeyPress: { key in
                                if let device = selectedDevice {
                                    Task {
                                        await self.controllerActor.sendKeyPressTodevice(location: device.location, key: key)
                                    }
                                }
                                return .ignored
                            })
                        }
#endif
                        
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            .task(priority: .low) {
                await self.scanningActor.scanSSDPContinually()
            }
            .task(priority: .low) {
                if !scanIpAutomatically {
                    return
                }
                await self.scanningActor.scanIPV4Once()
            }
            .task(id: selectedDevice?.id, priority: .medium) {
                if let devId = selectedDevice?.id {
                    await self.scanningActor.refreshSelectedDeviceContinually(id: devId)
                }
            }
            .onAppear {
                let modelContainer = modelContext.container
                self.scanningActor = DeviceControllerActor(modelContainer: modelContainer)
                self.controllerActor = DeviceControllerActor(modelContainer: modelContainer)
            }
#if os(iOS)
            .task(id: inBackground || !controlVolumeWithHWButtons) {
                if inBackground || !controlVolumeWithHWButtons {
                    return
                }
                if let stream = VolumeListener(session: AVAudioSession.sharedInstance()).events {
                    for await volumeEvent in stream {
                        let key: RemoteButton
                        switch volumeEvent.direction {
                        case .Up:
                            key = .volumeUp
                        case .Down:
                            key = .volumeDown
                        }
                        Task {
                            if let device = selectedDevice {
                                await controllerActor.sendKeyToDevice(location: device.location, key: key)
                            }
                        }
                    }
                } else {
                    Self.logger.error("Unable to get volume events stream")
                }
            }
#endif
            .onChange(of: scenePhase) { _oldPhase, newPhase in
                inBackground = newPhase != .active
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showKeyboardEntry = !showKeyboardEntry
                    }) {
                        Label("Keyboard", systemImage: "keyboard")
                            .controlSize(.large)
                            .labelStyle(.iconOnly)
                    }
                    .disabled(selectedDevice == nil)
                }
#endif
                ToolbarItem(placement: .automatic) {
                    Menu {
                        if !devices.isEmpty {
                            Picker("Device", selection: $manuallySelectedDevice.withDefault(selectedDevice)) {
                                ForEach(devices) { device in
                                    Text(device.name).tag(device as Device?)
                                }
                            }.pickerStyle(.inline).onChange(of: manuallySelectedDevice) { _oldSelected, selected in
                                if let chosenDevice = devices.first(where: { d in
                                    d.id == selected?.id
                                }) {
                                    Self.logger.debug("Setting last selected at")
                                    chosenDevice.lastSelectedAt = Date.now
                                }
                                do {
                                    try modelContext.save()
                                } catch {
                                    Self.logger.error("Error saving device selection: \(error)")
                                }
                            }
                        } else {
                            Text("No devices")
                        }
                        
                        Divider()
#if os(macOS)
                        SettingsLink {
                            Label("Settings", systemImage: "gear")
                        }
#else
                        Button("Settings", systemImage: "gear") {
                            showSettingsView = true
                        }
#endif
                    } label: {
                        Group {
                            Text(Image(systemName: "circle.fill") ).font(.system(size: 8))
                                .foregroundColor(deviceStatusColor)
                                .baselineOffset(2) +
                            Text(" ") +
                            Text(selectedDevice?.name ?? "No devices")
                        }.multilineTextAlignment(.center)
                            .truncationMode(.tail)
                            .frame(maxWidth: 180)
                    }
                }
                
#if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: {
                        incrementButtonPressCount(.power)
                        donateButtonIntent(.power)
                        Task {
                            if let device = selectedDevice {
                                await controllerActor.powerToggleDevice(device: device)
                            }
                        }
                    }) {
                        Label("Power Off/On", systemImage: "power")
                            .foregroundStyle(Color.red, Color.red)
                            .labelStyle(.iconOnly)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedDevice == nil)
                    .keyboardShortcut(.return)
                    .sensoryFeedback(.impact, trigger: buttonPressCount(.power))
                    .symbolEffect(.bounce, value: buttonPressCount(.power))
                }
#endif
                
            }
        }
#if os(iOS)
        .sheet(isPresented: $showSettingsView) {
            SettingsView()
        }
#endif
    }
    
    @ViewBuilder
    var horizontalBody: some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: 20) {
                if !showKeyboardEntry {
                    Spacer()
                    // Center Controller with directional buttons
                    centerController
                }
                Spacer()
                
                VStack(alignment: .center) {
                    // Row with Back and Home buttons
                    topBar
                    
                    
                    if !showKeyboardEntry {
                        Spacer().frame(maxHeight: 60)
                        
                        // Grid of 9 buttons
                        buttonGrid
                    }
                }
                Spacer()
            }
            
            if !showKeyboardEntry && (selectedDevice?.appsSorted?.count ?? 0) > 0 {
                Spacer()
                appLinks
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    var verticalBody: some View {
        VStack(alignment: .center, spacing: 10) {
            // Row with Back and Home buttons
            topBar
            
            Spacer()
            
            // Center Controller with directional buttons
            centerController
            
            if !showKeyboardEntry {
                
                Spacer()
                // Grid of 9 buttons
                buttonGrid
                
            }
            
            
            if !showKeyboardEntry && (selectedDevice?.appsSorted?.count ?? 0) > 0 {
                Spacer()
                appLinks
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    var appLinks: some View {
        AppLinksView(appLinks: selectedDevice?.appsSorted ?? [], rows: screenSize.height > 500 ? 2 : 1) { app in
            
            donateAppLaunchIntent(app)
            incrementButtonPressCount(.inputAV1)
            Task {
                if let location = selectedDevice?.location {
                    await controllerActor.openApp(location: location, app: app.id)
                }
            }
        }
        .sensoryFeedback(.impact, trigger: buttonPressCount(.inputAV1))
    }
    
    @ViewBuilder
    var buttonGrid: some View {
        let buttons: [(String, String, RemoteButton, KeyEquivalent?, Bool)] = [
            ("Replay", "arrow.uturn.backward", .instantReplay, nil, false),
            ("Options", "asterisk", .options, nil, false),
            ("Private Listening", "headphones", .enter, nil, true),
            ("Rewind", "backward.end.fill", .rewind, nil, false),
            ("Play/Pause", "playpause.fill", .playPause, nil, false),
            ("Fast Forward", "forward.end.fill", .fastForward, nil, false),
            ("Mute", "speaker.slash.fill", .mute, "m", false),
            ("Volume Down", "speaker.wave.1.fill", .volumeDown, .downArrow, false),
            ("Volume Up", "speaker.wave.2.fill", .volumeUp, .upArrow, false)
        ]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 48, maximum: 160)), count: 3), spacing: 10) {
            ForEach(buttons, id: \.0) { button in
                let view = Button(action: {
                    incrementButtonPressCount(button.2)
                    donateButtonIntent(button.2)
                    Task {
                        if let device = selectedDevice {
                            await controllerActor.sendKeyToDevice(location: device.location, key: button.2)
                        }
                    }
                }) {
                    Label(button.0, systemImage: button.1)
                        .frame(width: 26, height: 20)
                }
                    .disabled(button.4)
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .clipShape(.rect(cornerSize: CGSize(width: 8, height: 8)))
                    .sensoryFeedback(.impact, trigger: buttonPressCount(button.2))
                    .symbolEffect(.bounce, value: buttonPressCount(button.2))
                if let ks = button.3 {
                    view
                        .keyboardShortcut(ks)
                } else {
                    view
                }
            }
        }
        
    }
    
    @ViewBuilder
    var centerController: some View {
        let buttons: [(String?, RemoteButton, String)?] = [
            nil, ("chevron.up", .up, "Up"), nil,
            ("chevron.left", .left, "Left"), (nil, .select, "OK"), ("chevron.right", .right, "Right"),
            nil, ("chevron.down", .down, "Down"), nil
        ]
        Grid {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(0..<3) { col in
                        if let button = buttons[row * 3 + col] {
                            Button(action: {
                                incrementButtonPressCount(button.1)
                                donateButtonIntent(button.1)
                                Task {
                                    if let device = selectedDevice {
                                        await controllerActor.sendKeyToDevice(location: device.location, key: button.1)
                                    }
                                }
                            }) {
                                if let systemImage = button.0 {
                                    Label(button.2, systemImage: systemImage)
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 2)
                                        .labelStyle(.iconOnly)
                                } else {
                                    Text(button.2)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle)
                            .controlSize(.extraLarge)
                            .fixedSize()
                            .shadow(radius: 2)
                            .sensoryFeedback(.impact, trigger: buttonPressCount(button.1))
                            .symbolEffect(.bounce, value: buttonPressCount(button.1))
                        } else {
                            Text("")
                        }
                    }
                }
            }
        }.fixedSize()
    }
    
    @ViewBuilder
    var topBar: some View {
        HStack(spacing: isHorizontal ? 30 : nil) {
            if !isHorizontal {
                Spacer()
            }
            Button(action: {
                incrementButtonPressCount(.back)
                donateButtonIntent(.back)
                Task {
                    if let device = selectedDevice {
                        await controllerActor.sendKeyToDevice(location: device.location, key: .back)
                    }
                }
            }) {
                Label("Back", systemImage: "arrow.left")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .sensoryFeedback(.impact, trigger: buttonPressCount(.back))
            .symbolEffect(.bounce, value: buttonPressCount(.back))
            if !isHorizontal {
                Spacer()
            }
            
#if os(macOS)
            KeyboardMonitor(disabled: selectedDevice == nil) { key in
                let _ = print("Getting key \(key)")
                if let device = selectedDevice {
                    Task {
                        await self.controllerActor.sendKeyPressTodevice(location: device.location, key: key)
                    }
                    return .handled
                }
                return .ignored
            }
#elseif os(iOS)
            Button("Power On/Off", systemImage: "power", role: .destructive, action: {
                incrementButtonPressCount(.power)
                donateButtonIntent(.power)
                Task {
                    if let device = selectedDevice {
                        await controllerActor.powerToggleDevice(device: device)
                    }
                }
            })
            .font(.system(size: 24, weight: .bold))
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .sensoryFeedback(.impact, trigger: buttonPressCount(.power))
            .symbolEffect(.bounce, value: buttonPressCount(.power))
#endif
            if !isHorizontal {
                Spacer()
            }
            
            Button(action: {
                incrementButtonPressCount(.home)
                donateButtonIntent(.home)
                Task {
                    if let device = selectedDevice {
                        await controllerActor.sendKeyToDevice(location: device.location, key: .home)
                    }
                }
            }) {
                Label("Home", systemImage: "house")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .sensoryFeedback(.impact, trigger: buttonPressCount(.home))
            .symbolEffect(.bounce, value: buttonPressCount(.home))
            if !isHorizontal {
                Spacer()
            }
        }
    }
}

#if os(macOS)
struct KeyboardMonitor: View {
    @FocusState private var keyboardMonitorFocused: Bool
    let disabled: Bool
    let onKeyPress: (KeyPress) -> KeyPress.Result
    
    var body: some View {
        Button(action: {}) {
            Label("Keyboard", systemImage: "keyboard")
                .controlSize(.large)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.accessoryBar)
        .disabled(disabled)
        .focusable()
        .focused($keyboardMonitorFocused)
        .onKeyPress { key in
            return onKeyPress(key)
        }
        .onAppear {
            keyboardMonitorFocused = true
            print("Appearing \(keyboardMonitorFocused)")
        }
    }
}
#endif

#if os(iOS)
struct KeyboardEntry: View {
    @Binding var str: String
    @FocusState private var keyboardFocused: Bool
    let onKeyPress:  (_ press: KeyPress) -> KeyPress.Result
    
    var body: some View {
        Form {
            TextField("Enter some text...", text: $str)
                .focused($keyboardFocused)
                .onKeyPress{ key in onKeyPress(key)}
        }
        .frame(height: 100)
        .onAppear {
            keyboardFocused = true
            str = ""
        }
        
    }
}
#endif

enum SettingsDestination {
    case Devices
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

#Preview("Remote vertical", traits: .fixedLayout(width: 300, height: 600)) {
    RemoteView()
        .modelContainer(devicePreviewContainer)
}


#Preview("Remote horizontal", traits: .fixedLayout(width: 700, height: 600)) {
    RemoteView()
        .modelContainer(devicePreviewContainer)
}
