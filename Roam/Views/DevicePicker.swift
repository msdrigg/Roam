import Foundation
import os
import SwiftUI

#if os(tvOS)
    let globalBaselineOffset: CGFloat = 4
    let circleIconSize: CGFloat = 16
#else
    let globalBaselineOffset: CGFloat = 2
    let circleIconSize: CGFloat = 8
#endif

struct DevicePicker: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.createDataHandler) private var createDataHandler

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
                        device
                    },
                    set: {
                        device = $0
                        if let pid = $0?.persistentModelID {
                            Task.detached {
                                try? await Task.sleep(duration: 0.5)
                                await createDataHandler()?.setSelectedDevice(pid)
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
                NavigationLink(value: NavigationDestination.settingsDestination(.global)) {
                    Label("Settings", systemImage: "gear")
                }
                .labelStyle(.titleAndIcon)
            #elseif APPCLIP
            Button(String(localized: "Download the full app", comment: "Text on a button to download the app from the app store"), systemImage: "app.gift") {
                    openURL(URL(string: "https://apps.apple.com/us/app/roam-a-better-remote-for-roku/id6469834197")!)
                }
                .labelStyle(.titleAndIcon)
            #endif
        } label: {
            if let device {
                Group {
                    Text(Image(systemName: "circle.fill")).font(.system(size: circleIconSize))
                        .foregroundColor(deviceStatusColor)
                        .baselineOffset(globalBaselineOffset) +
                    Text(" ", comment: "Empty space").font(.body) +
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
