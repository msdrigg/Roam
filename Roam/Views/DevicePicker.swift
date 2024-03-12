import Foundation
import SwiftUI
import os


struct DevicePicker: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    
    let devices: [Device]
    @Binding var device: Device?
    
    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }
    
    var body: some View {
        Menu {
            if !devices.isEmpty {
                Picker("Device", selection: $device) {
                    ForEach(devices) { device in
                        Text(device.name)
                            .lineLimit(1)
                            .tag(device as Device?)
                    }
                }.onChange(of: device) { _oldSelected, selected in
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
            if let device = device {
                Group {
                    Text(Image(systemName: "circle.fill") ).font(.system(size: 8))
                        .foregroundColor(deviceStatusColor)
                        .baselineOffset(2) +
                    Text(" ").font(.body)
                        .foregroundColor(.secondary)
                    +
                    Text(device.name).font(.body)
                        .foregroundColor(.secondary)
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
    }
}
