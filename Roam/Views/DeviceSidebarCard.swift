#if !os(watchOS)
import SwiftUI

/// Card-styled row used in the sidebar of `DeviceSplitRoot` (iPad / macOS /
/// visionOS) and as a tap target on the iPhone home grid (`PhoneHomeView`).
///
/// Renders the device's icon, name, and a small online-status indicator. While
/// the device record is still loading it shows a muted placeholder so the
/// sidebar can render immediately rather than wait for a network round-trip.
struct DeviceSidebarCard: View {
    @State private var deviceLoader: DeviceLoader
    private let deviceId: String

    init(deviceId: String) {
        self.deviceId = deviceId
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    private var device: Device? { deviceLoader.device }

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 56, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(device?.name ?? String(
                    localized: "Loading…",
                    comment: "Placeholder shown on a device card while its record loads"
                ))
                .font(.headline)
                .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        if let device {
            FallibleImage(from: device.iconURL, fallback: "tv", maxSize: 120)
        } else {
            Image(systemName: "tv")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var isOnline: Bool {
        // Reading through the monitor rather than `device.isOnline()` — only
        // the connected device gets its `lastOnlineAt` refreshed, so the record
        // alone can't say anything about the rest of the list.
        DeviceLivenessMonitor.shared.isOnline(device)
    }

    private var statusText: String {
        if let device {
            return getHostPortDisplay(from: device.location)
        }
        return ""
    }
}

/// Picks the order every device list is shown in.
///
/// Lives next to the lists it reorders — the iPhone home screen's `⇅` menu and
/// the sidebar footer — rather than in Settings, where a sort control for a
/// handful of devices reads as heavier than the thing it sorts.
///
/// Writing through the data handler is what makes the change take effect
/// immediately: it republishes the device list, so every open list re-renders
/// in the new order rather than waiting for the next thing to touch it.
struct DeviceSortOrderPicker: View {
    @AppStorage(UserDefaultKeys.deviceSortOrder) private var storedOrder: String =
        DeviceSortOrder.manual.rawValue

    private var selection: Binding<DeviceSortOrder> {
        Binding {
            DeviceSortOrder(rawValue: storedOrder) ?? .manual
        } set: { newOrder in
            storedOrder = newOrder.rawValue
            Task {
                await RoamDataHandler.shared.setDeviceSortOrder(newOrder)
            }
        }
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(DeviceSortOrder.allCases) { order in
                Text(order.label).tag(order)
            }
        } label: {
            Text("Sort by", comment: "Header above the device sort options")
        }
        // Inline, so the options sit directly in the menu under a "Sort by"
        // header. The default style nests them behind a submenu, which put two
        // taps between the button and a one-of-three choice.
        .pickerStyle(.inline)
        .accessibilityIdentifier("DeviceSortOrderPicker")
    }
}

#if DEBUG
#Preview("Device Sidebar Card", traits: .fixedLayout(width: 320, height: 80)) {
    DeviceSidebarCard(deviceId: getTestingDevices()[0].id)
        .padding()
}
#endif
#endif
