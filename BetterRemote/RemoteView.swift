import SwiftUI
import SwiftData
import os

struct RemoteView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )
    
    private var appLinks: [AppLink] = loadDefaultAppLinks()
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name, order: .reverse) private var devices: [Device]
    
    @State private var scanningActor: DeviceControllerActor!
    @State private var controllerActor: DeviceControllerActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardEntryText: String = ""
    
    enum FocusField: Hashable {
        case field
    }
    @FocusState private var focused: Bool
    
    private var selectedDevice: Device? {
        manuallySelectedDevice ?? devices.min { d1, d2 in
            d1.lastSelectedAt?.timeIntervalSince1970 ?? 0 < d2.lastSelectedAt?.timeIntervalSince1970 ?? 0
        }
    }
    
    var body: some View {
        NavigationStack {
            HStack {
                Spacer()
                VStack(spacing: 20) {
                    // Top row: Home, Back, Voice buttons
                    HStack {
#if os(macOS)
                        let buttonStyle = AccessoryBarButtonStyle()
#else
                        let buttonStyle = DefaultButtonStyle()
#endif
                        
                        // Power button
                        Button(action: {
                            showKeyboardEntry = true
                        }) {
                            Label("Keyboard", systemImage: "keyboard")
                                .controlSize(.large)
                                .labelStyle(.iconOnly)
                        }
                        .disabled(selectedDevice == nil)
                        .buttonStyle(buttonStyle)
#if os(macOS)
                        .focusable()
                        .focused($focused)
                        .onKeyPress { key in
                            if let device = selectedDevice {
                                Task {
                                    Self.logger.debug("Sending \(getKeypressForKey(key: key)) for \(key.key.character.unicodeScalars)")
                                    await self.controllerActor.sendKeyToDevice(location: device.location, key: getKeypressForKey(key: key))
                                }
                                return .handled
                            }
                            return .ignored
                        }
                        .onAppear {
                            focused = true
                        }
#endif
#if os(iOS)
                        .popover(isPresented: $showKeyboardEntry) {
                            Form {
                                TextField("Enter some text...", text: $keyboardEntryText)
                                    .frame(minWidth: 200)
                                    .focused($focused)
                                    .onAppear {
                                        focused = true
                                        keyboardEntryText = ""
                                    }
                                    .onKeyPress { key in
                                        if let device = selectedDevice {
                                            Task {
                                                Self.logger.debug("Sending \(getKeypressForKey(key: key)) for \(key.key.character.unicodeScalars)")
                                                await self.controllerActor.sendKeyToDevice(location: device.location, key: getKeypressForKey(key: key))
                                            }
                                        }
                                        return .ignored
                                    }
                            }
                        }
#endif
                        
                        Spacer()
                        
                        // Power button
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.powerToggleDevice(device: device)
                                }
                            }
                        }) {
                            Label("Power Off/On", systemImage: "power")
                                .controlSize(.large)
                                .foregroundColor(.red)
                                .labelStyle(.iconOnly)
                        }
                        .disabled(selectedDevice == nil)
                        .buttonStyle(buttonStyle)
                    }
#if os(macOS)
                    .padding(.top, 20)
#endif
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            HStack {
                                Spacer()
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
                                                chosenDevice.lastSelectedAt = Date.now
                                            }
                                        }
                                    } else {
                                        Text("No devices")
                                    }
                                    
                                    Divider()
#if os(macOS)
                                    SettingsLink {
                                        Label("Device Settings", systemImage: "gear")
                                    }
#else
                                    NavigationLink("Device Settings", value: SettingsDestination.Devices)
#endif
                                } label: {
                                    HStack{
                                        if let selectedDevice = selectedDevice {
                                            let color = selectedDevice.isOnline() ? Color.green : Color.secondary
                                            Image(systemName: "circle.fill").foregroundStyle(color, color).controlSize(.mini)
                                        }
                                        Text(selectedDevice?.name ?? "No devices").frame(maxWidth: 120)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Row with Back and Home buttons
                    HStack {
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "back")
                                }
                            }
                        }) {
                            Label("Back", systemImage: "arrow.left")
                                .controlSize(.large)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button(action: {
                            
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "home")
                                }
                            }
                        }) {
                            Label("Home", systemImage: "house")
                                .controlSize(.large)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                    }
#if os(macOS)
                    Spacer().frame(maxHeight: 20)
#else
                    Spacer().frame(maxHeight: 5)
#endif
                    
                    // Center Controller with directional buttons
                    VStack(spacing: 10) {
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "up")
                                }
                            }
                        }) {
                            Label("Up", systemImage: "chevron.up")
                                .controlSize(.extraLarge)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                Task {
                                    if let device = selectedDevice {
                                        await controllerActor.sendKeyToDevice(location: device.location, key: "left")
                                    }
                                }
                            }) {
                                Label("Left", systemImage: "chevron.left")
                                    .controlSize(.extraLarge)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            
                            Button(action: {
                                Task {
                                    if let device = selectedDevice {
                                        await controllerActor.sendKeyToDevice(location: device.location, key: "select")
                                    }
                                }
                            }) {
                                Text("OK")
                                    .controlSize(.extraLarge)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            
                            Button(action: {
                                Task {
                                    if let device = selectedDevice {
                                        await controllerActor.sendKeyToDevice(location: device.location, key: "right")
                                    }
                                }
                            }) {
                                Label("Right", systemImage: "chevron.right")
                                    .controlSize(.extraLarge)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                        }
                        
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "down")
                                }
                            }
                        }) {
                            Label("Down", systemImage: "chevron.down")
                                .controlSize(.extraLarge)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                    }
                    
#if os(macOS)
                    Spacer().frame(maxHeight: 20)
#else
                    Spacer().frame(maxHeight: 5)
#endif
                    
                    // Grid of 9 buttons
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "instantreplay")
                                }
                            }
                        }) {
                            Label("Replay", systemImage: "arrow.uturn.backward")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "info")
                                }
                            }
                        }) {
                            Label("Options", systemImage: "asterisk")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {}) {
                            Label("Private Listening", systemImage: "headphones")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                            .disabled(true)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "rev")
                                }
                            }
                        }) {
                            Label("Rewind", systemImage: "backward.end.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "play")
                                }
                            }
                        }) {
                            Label("Play/Pause", systemImage: "playpause.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "fwd")
                                }
                            }
                        }) {
                            Label("Fast Forward", systemImage: "forward.end.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "volumemute")
                                }
                            }
                        }) {
                            Label("Mute", systemImage: "speaker.slash.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "volumedown")
                                }
                            }
                        }) {
                            Label("Volume Down", systemImage: "speaker.wave.1.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Button(action: {
                            Task {
                                if let device = selectedDevice {
                                    await controllerActor.sendKeyToDevice(location: device.location, key: "volumeup")
                                }
                            }
                        }) {
                            Label("Volume Up", systemImage: "speaker.wave.2.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                    }
                    
#if os(macOS)
                    Spacer().frame(maxHeight: 20)
#else
                    Spacer().frame(maxHeight: 5)
#endif
                    AppLinksView(appLinks: appLinks) { app in
                        Task {
                            if let location = selectedDevice?.location {
                                await controllerActor.openApp(location: location, app: app)
                            }
                        }
                    }
#if os(macOS)
                    Spacer().frame()
#endif
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(minWidth: 220.0)
            .task {
                await self.scanningActor.scanContinually()
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                SettingsView()
            }
        }
        .onAppear {
            let modelContainer = modelContext.container
            self.scanningActor = DeviceControllerActor(modelContainer: modelContainer)
            self.controllerActor = DeviceControllerActor(modelContainer: modelContainer)
        }
    }
}

func getKeypressForKey(key: KeyPress) -> String {
    let keyMap: [Character: String] = [
        KeyEquivalent.delete.character: "backspace",
        KeyEquivalent.deleteForward.character: "backspace",
        "\u{7F}": "backspace",
        KeyEquivalent.escape.character: "back",
        KeyEquivalent.space.character: "LIT_ ",
        KeyEquivalent.downArrow.character: "down",
        KeyEquivalent.upArrow.character: "up",
        KeyEquivalent.rightArrow.character: "right",
        KeyEquivalent.leftArrow.character: "left",
        KeyEquivalent.home.character: "home",
        KeyEquivalent.return.character: "enter",
    ]
    
    if let mappedString = keyMap[key.key.character] {
        return mappedString
    }
    
    return "LIT_\(key.characters)"
}

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

#Preview {
    RemoteView()
#if os(macOS)
        .previewLayout(.fixed(width: 100.0, height: 300.0))
#endif
        .modelContainer(for: Device.self, inMemory: true)
}
