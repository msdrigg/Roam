import SwiftUI
import SwiftData

struct RokuRemoteView: View {
    private var appLinks: [AppLink] = loadDefaultAppLinks()
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name, order: .reverse) private var devices: [Device]

    // @State private var scanningActor: BackgroundScanningActor!
    @State private var manuallySelectedDevice: Device?
    
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
                        Spacer()
                        
                        // Power button
                        Button(action: {}) {
                            Label("Power Off/On", systemImage: "power")
                                .frame(width: 28, height: 22)
                                .foregroundColor(.red)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.accessoryBar)
                    }.overlay {
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
                                
                                NavigationLink("Device Settings", value: SettingsDestination.Devices)
                            } label: {
                                Label{
                                    Text(selectedDevice?.name ?? "No devices")
                                } icon: {
                                    if let selectedDevice = selectedDevice {
                                        let color = selectedDevice.isOnline() ? Color.green : Color.secondary
                                        Image(systemName: "circle.fill").foregroundStyle(color, color)
                                    }
                                }
                                

                            }.menuStyle(.borderlessButton)
                                .frame(maxWidth: 100)
                            
                            Spacer()
                        }
                    }
                    
                    // Row with Back and Home buttons
                    HStack {
                        Button(action: {}) {
                            Label("Back", systemImage: "arrow.left")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Label("Home", systemImage: "house")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                    }
                    
                    // Center Controller with directional buttons
                    VStack(spacing: 10) {
                        Button(action: {}) {
                            Label("Up", systemImage: "chevron.up")
                                .frame(width: 32, height: 28)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        
                        HStack(spacing: 10) {
                            Button(action: {}) {
                                Label("Left", systemImage: "chevron.left")
                                    .frame(width: 32, height: 28)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            
                            Button(action: {}) {
                                Text("OK")
                                    .frame(width: 32, height: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            
                            Button(action: {}) {
                                Label("Right", systemImage: "chevron.right")
                                    .frame(width: 32, height: 28)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                        }
                        
                        Button(action: {}) {
                            Label("Down", systemImage: "chevron.down")
                                .frame(width: 32, height: 28)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                    }
                    
                    // Grid of 9 buttons
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                        Button(action: {}) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Options", systemImage: "asterisk")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Private Listening", systemImage: "headphones")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        .disabled(true)
                        Button(action: {}) {
                            Label("Rewind", systemImage: "backward.end.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Play/Pause", systemImage: "playpause.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Fast Forward", systemImage: "forward.end.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Mute", systemImage: "speaker.slash.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Volume Down", systemImage: "speaker.wave.1.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                        Button(action: {}) {
                            Label("Volume Up", systemImage: "speaker.wave.2.fill")
                                .frame(width: 28, height: 22)
                                .labelStyle(.iconOnly)
                        }
                    }
                    
                    AppLinksView(appLinks: appLinks)
                    
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20).frame(minWidth: 220.0, maxWidth: 400.0)
            .navigationDestination(for: SettingsDestination.self) { destination in
                SettingsView()
            }
        }

    }
}

enum SettingsDestination {
    case Devices
}

extension Color {
    static let appPrimary = Color(red: 0.434, green: 0.102, blue: 0.691)
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
    RokuRemoteView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(for: Device.self, inMemory: true)
}
