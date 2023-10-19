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
    
    @State private var scanningActor: DeviceScanningActor!
    @State private var controllerActor: DeviceControllerActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var screenSize: CGSize = .zero
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var navigationPath: NavigationPath = NavigationPath()
    
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
        SettingsNavigationWrapper(path: $navigationPath) {
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
                        if selectedDevice == nil {
                            // Banner Content Here
                            VStack(spacing: 2) {
                                HStack {
                                    Label("Setup a device to get started :)", systemImage: "gear")
                                }
                                .padding(8)
                                .background(Color("AccentColor"))
                                .tint(Color("AccentColor"))
                                .cornerRadius(6)
                                .frame(maxWidth: .infinity)
                                .font(.subheadline)
                                .labelStyle(.titleAndIcon)
                                Spacer().frame(maxHeight: 8)
                            }
                        }
                        
                        if isHorizontal {
                            horizontalBody
#if os(iOS)
                                .contentShape(Rectangle())
                                .simultaneousGesture(TapGesture().onEnded {
                                    showKeyboardEntry = false
                                })
#endif
                        } else {
                            verticalBody
#if os(iOS)
                                .contentShape(Rectangle())
                                .simultaneousGesture(TapGesture().onEnded {
                                    showKeyboardEntry = false
                                })
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
                .disabled(selectedDevice == nil)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
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
                        .buttonStyle(.borderless)
                        .disabled(selectedDevice == nil)
                        .font(.headline)
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
                                    .labelStyle(.titleAndIcon)
                            }
#else
                            NavigationLink(value: SettingsDestination.Global) {
                                Label("Settings", systemImage: "gear")
                            }
                            .labelStyle(.titleAndIcon)
#endif
                        } label: {
                            if let device = selectedDevice {
                                Group {
                                    Text(Image(systemName: "circle.fill") ).font(.system(size: 8))
                                        .foregroundColor(deviceStatusColor)
                                        .baselineOffset(2) +
                                    Text(" ") +
                                    Text(device.name)
                                }.multilineTextAlignment(.center)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 180)
                            } else {
                                Text("No devices")
                                    .multilineTextAlignment(.center)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 180)
                            }
                        }
                        .font(.body)
                        
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
                                .font(.headline)
                        }
                        .keyboardShortcut(.return)
                        .sensoryFeedback(.impact, trigger: buttonPressCount(.power))
                        .symbolEffect(.bounce, value: buttonPressCount(.power))
                        .disabled(selectedDevice == nil)
                    }
#endif
                }
                
                .onAppear {
                    let modelContainer = modelContext.container
                    self.scanningActor = DeviceScanningActor(modelContainer: modelContainer)
                    self.controllerActor = DeviceControllerActor(modelContainer: modelContainer)
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
                
            }
            .font(.title2)
            .fontDesign(.rounded)
            .controlSize(.extraLarge)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .labelStyle(.iconOnly)
            
        }       
        .task(priority: .low) {
            await self.scanningActor.scanSSDPContinually()
        }
    }
    
    var horizontalBody: some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: 20) {
                if !showKeyboardEntry {
                    Spacer()
                    // Center Controller with directional buttons
                    centerController
                        .frame(maxWidth: .infinity)
                }
                Spacer()
                
                VStack(alignment: .center) {
                    // Row with Back and Home buttons
                    topBar
                        .frame(maxWidth: .infinity)
                    
                    
                    
                    if !showKeyboardEntry {
                        Spacer().frame(maxHeight: 60)
                        
                        // Grid of 9 buttons
                        buttonGrid
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: 600)
            
            if !showKeyboardEntry && (selectedDevice?.appsSorted?.count ?? 0) > 0 {
                Spacer()
                appLinks
            }
            Spacer()
        }
    }
    
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
        .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
    }
    
    var buttonGrid: some View {
        let buttonRows: [[(String, String, RemoteButton, KeyEquivalent?, Bool)]] = [
            [("Replay", "arrow.uturn.backward", .instantReplay, nil, false),
             ("Options", "asterisk", .options, nil, false),
             ("Private Listening", "headphones", .enter, nil, true)],
            [("Rewind", "backward", .rewind, nil, false),
             ("Play/Pause", "playpause", .playPause, nil, false),
             ("Fast Forward", "forward", .fastForward, nil, false)],
            [("Volume Down", "speaker.minus", .volumeDown, .downArrow, false),
             ("Mute", "speaker.slash", .mute, "m", false),
             ("Volume Up", "speaker.plus", .volumeUp, .upArrow, false)]
        ]
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
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
                                .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                        }
                            .disabled(button.4)
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
        }
    }
    
    var centerController: some View {
        let buttons: [(String?, RemoteButton, String)?] = [
            nil, ("chevron.up", .up, "Up"), nil,
            ("chevron.left", .left, "Left"), (nil, .select, "Ok"), ("chevron.right", .right, "Right"),
            nil, ("chevron.down", .down, "Down"), nil
        ]
        return VStack(alignment: .center) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
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
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                    } else {
                                        Text(button.2)
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                        
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .sensoryFeedback(.impact, trigger: buttonPressCount(button.1))
                                .symbolEffect(.bounce, value: buttonPressCount(button.1))
                            } else {
                                Spacer()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: BUTTON_WIDTH * 3 + 6, maxHeight: BUTTON_HEIGHT * 3 + 6)
        }
    }
    
    var topBar: some View {
        HStack(spacing: isHorizontal ? 10 : nil) {
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
                    .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
            }
            .sensoryFeedback(.impact, trigger: buttonPressCount(.back))
            .symbolEffect(.bounce, value: buttonPressCount(.back))
            if !isHorizontal {
                Spacer()
                    .frame(maxWidth: 30)
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
            // Do this so the focus outline on macOS matches
            .offset(y: 7)
            
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
            .font(.title)
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .sensoryFeedback(.impact, trigger: buttonPressCount(.power))
            .symbolEffect(.bounce, value: buttonPressCount(.power))
#endif
            if !isHorizontal {
                Spacer()
                    .frame(maxWidth: 30)
                
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
                    .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                
            }
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
                .labelStyle(.iconOnly)
        }
        .font(.headline)
        // Do this so the focus outline on macos matches
        .offset(y: -7)
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
        TextField("Enter some text...", text: $str)
            .focused($keyboardFocused)
            .onKeyPress{ key in onKeyPress(key)}
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary))
        .frame(height: 60)
        .onAppear {
            keyboardFocused = true
            str = ""
        }
        
    }
}
#endif


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
