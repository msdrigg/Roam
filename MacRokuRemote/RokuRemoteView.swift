import SwiftUI
import SwiftData

struct RokuRemoteView: View {
    private var appLinks: [AppLink] = loadDefaultAppLinks()
    
    @Environment(\.modelContext) private var modelContext
    //private var devices: [Device] = getTestingDevices()
    @Query(sort: \Device.lastSelectedAt, order: .reverse) private var devices: [Device]
    
    var selectedDevice: Device? {
        devices.first
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
                                ForEach(devices) {device in
                                    Button(action: {
                                        device.lastSelectedAt = Date.now
                                    }){
                                        HStack {
                                            Text(device.name)
                                            Spacer()
                                            Circle()
                                                .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                                                .frame(width: 10, height: 10)
                                            if let time = device.lastSelectedAt {
                                                Text(time, style: .date)
                                            } else {
                                                Text("Never connected")
                                            }
                                        }
                                    }
                                }.frame(minHeight: 400)
                                
                                if (devices.count == 0) {
                                    Text("No devices")
                                }
                                
                                Divider()
                                
                                NavigationLink("Device Settings", value: SettingsDestination.Devices)
                            } label: {
                                Label{
                                    Text(selectedDevice?.name ?? "No devices")
                                } icon: {
                                    if let selectedDevice = selectedDevice {
                                        let color = selectedDevice.isOnline() ? Color.green : Color.gray
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

#Preview {
    RokuRemoteView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(for: Device.self, inMemory: true)
}
