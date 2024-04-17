import Foundation
import SwiftUI
import os

#if os(tvOS)
let BASELINE_OFFSET: CGFloat = 4
let CIRCLE_ICON_SIZE: CGFloat = 16
#else
let BASELINE_OFFSET: CGFloat = 2
let CIRCLE_ICON_SIZE: CGFloat = 8
#endif

struct DevicePicker: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    var deviceActor: DeviceActor {
        DeviceActor(modelContainer: modelContext.container)
    }
    
    
    let devices: [Device]
    @Binding var device: Device?
    
    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }
    
    var body: some View {
        Menu {
            if !devices.isEmpty {
                Picker("Device", selection: Binding<Device?>(
                    get: {
                        self.device
                    },
                    set: {
                        self.device = $0
                        if let pid = $0?.persistentModelID {
                            Task {
                                do {
                                    try? await Task.sleep(duration: 0.5)
                                    try await deviceActor.setSelectedDevice(pid)
                                } catch {
                                    Self.logger.error("Error setting selected device \(error)")
                                }
                            }
                        }
                    }
                )) {
                    ForEach(devices) { device in
                        Text(device.name)
                            .lineLimit(1)
                            .tag(device as Device?)
                    }
                }.pickerStyle(.inline)
            } else {
                Text("No devices")
            }
            
            Divider()
#if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gear")
                    .labelStyle(.titleAndIcon)
            }
#elseif !APPCLIP
            NavigationLink(value: NavigationDestination.SettingsDestination(.Global)) {
                Label("Settings", systemImage: "gear")
            }
            .labelStyle(.titleAndIcon)
#endif
        } label: {
            if let device = device {
                Group {
                    Text(Image(systemName: "circle.fill") ).font(.system(size: CIRCLE_ICON_SIZE))
                        .foregroundColor(deviceStatusColor)
                        .baselineOffset(BASELINE_OFFSET) +
                    Text(" ").font(.body) +
                    Text(device.name).font(.body)
                }.multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180)
            } else {
                Text("No devices")
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180)
            }
        }
        .animation(nil, value: UUID())
    }
}
