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
                }.pickerStyle(.inline).onChange(of: device) { _oldSelected, selected in
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
    }
}
