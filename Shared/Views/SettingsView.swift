import SwiftUI
import SwiftData
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(tvOS)
let DEVICE_ICON_SIZE: CGFloat = 64.0
let CIRCLE_SIZE: CGFloat = 18
#elseif os(visionOS)
let DEVICE_ICON_SIZE: CGFloat = 42.0
let CIRCLE_SIZE: CGFloat = 14
#elseif os(macOS)
let DEVICE_ICON_SIZE: CGFloat = 32.0
let CIRCLE_SIZE: CGFloat = 10
#else
let DEVICE_ICON_SIZE: CGFloat = 24.0
let CIRCLE_SIZE: CGFloat = 10
#endif

private let messageFetchDescriptor: FetchDescriptor<Message> = {
    var fd = FetchDescriptor(
        predicate: #Predicate<Message> {
            !$0.viewed
        })
    return fd
}()


private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name, order: .reverse)])
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt, \.deviceIcon]
    return fd
}()

struct SettingsView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    
    @Environment(\.modelContext) private var modelContext
    @Query(deviceFetchDescriptor) private var devices: [Device]
    @Query(messageFetchDescriptor) private var unreadMessages: [Message]
    @Binding var path: NavigationPath
    let destination: SettingsDestination
    
    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var isScanning: Bool = false
    
    @State private var deviceActor: DeviceActor!
    
    
    @State private var tabSelection = 0
    @State private var showWatchOSNote = false
    
    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true
    @AppStorage(UserDefaultKeys.userMajorActionCount) private var majorActionsCount = 0

    
    @State private var reportingDebugLogs: Bool = false
    @State private var debugLogReportID: String? = nil
    
    @State private var variableColor: CGFloat = 0.0
    
    func reportDebugLogs() {
        Task {
            reportingDebugLogs = true
            defer { reportingDebugLogs = false }
            Self.logger.info("Starting to send logs")
            let logs = await getDebugInfo(container: getSharedModelContainer(), message: "Requested from settings")
            Self.logger.info("Sending logs \(logs.id)")
            
            do {
                try await uploadDebugLogs(logs: logs)
                
                Self.logger.info("Upload successful")
                DispatchQueue.main.async {
#if os(watchOS)
                    debugLogReportID = logs.id
#elseif os(macOS)
                    openWindow(id: "messages")
#else
                    path.append(MessagingDestination.Global)
#endif
                }
            } catch {
                Self.logger.error("Failed to upload logs to s3: \(error)")
            }
        }
        
    }
    
    var body: some View {
        Form {
            Section {
                if devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(devices, id: \.displayHash) { device in
                        DeviceListItem(device: device)
#if !os(watchOS)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            Self.logger.error("HI")
                                            try await deviceActor.delete(device.persistentModelID)
                                            Self.logger.info("Deleted device with id \(String(describing: device.persistentModelID))")
                                            
                                        } catch {
                                            Self.logger.error("Error deleting device \(error)")
                                        }
                                    }
                                    
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                NavigationLink(value: DeviceSettingsDestination(device)) {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
#endif
#if !os(tvOS)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await deviceActor.delete(device.persistentModelID)
                                        } catch {
                                            Self.logger.error("Error deleting device \(error)")
                                        }
                                    }
                                    
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
#endif
                    }
                    .onDelete { indexSet in
                        Task {
                            do {
                                for index in indexSet {
                                    if let model = devices[safe: index] {
                                        try await deviceActor.delete(model.persistentModelID)
                                    }
                                }
                            } catch {
                                Self.logger.error("Error deleting device \(error)")
                            }
                        }
                    }
                }
#if os(watchOS) || os(tvOS)
                addDeviceButton
#endif
#if os(tvOS)
                scanDevicesButton
#endif
                
#if os(macOS)
                HStack {
                    Spacer()
                    
                    addDeviceButton
                }
#endif
            } header: {
                HStack {
                    Text("Devices")
#if os(macOS)
                    Spacer()
                    if isScanning {
                        Label("Scanning for devices...", systemImage: "rays")
                        .labelStyle(.iconOnly)
                        .symbolEffect(.variableColor, isActive: isScanning)
                        .padding(.init(top: 3, leading: 8, bottom: 3, trailing: 8))
                        .offset(x: 6)
                    } else {
                        Button("Scan for devices", systemImage: "arrow.clockwise") {
                            Task {
                                isScanning = true
                                defer {
                                    isScanning = false
                                }
                                
                                await scanningActor.scanIPV4Once()
                            }
                        }
                        .buttonStyle(PaddedHoverButtonStyle(padding: .init(top: 3, leading: 8, bottom: 3, trailing: 8)))
                        .labelStyle(.iconOnly)
                        .offset(x: 6)
                    }
#endif
                }
            }
            
#if os(watchOS)
            Button("WatchOS Note", systemImage: "info.circle.fill", action: {showWatchOSNote = true})
                .sheet(isPresented: $showWatchOSNote) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unfortunately, WatchOS prevents us from discovering TV's on the local network.").font(.caption).foregroundStyle(.secondary)
                                Text("To work around this limitation, first discover devices on the iPhone app and then the devices will be transfered in the background from the iPhone to the watch (or you can manually add the TV if you can get it's IP address).").font(.caption).foregroundStyle(.secondary)
                                Text("Please be patient, because I don't have an apple watch so I can't test how effective this is. Please reach out if you aren't able to get this to work :). You can email me at roam-support@msd3.io").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
#endif
            
#if !os(watchOS)
            Section("Behavior") {
#if os(iOS)
                Toggle("Use volume buttons to control TV volume", isOn: $controlVolumeWithHWButtons)
#endif
                
                Toggle("Scan for devices automatically", isOn: $scanIpAutomatically)
            }
#endif
            
            Section("Other") {
#if !os(tvOS) && !os(watchOS)
                HStack {
                    NavigationLink(value: KeyboardShortcutDestination.Global, label: {
                        Label("Keyboard shortcuts", systemImage: "keyboard")
                    })
                    .buttonStyle(.plain)
                    .keyboardShortcut("k")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
#endif
                if (majorActionsCount > 5) {
                    HStack {
                        ShareLink(item: URL(string: "https://apps.apple.com/us/app/roam-a-better-remote-for-roku/id6469834197")!) {
                            Label("Gift Roam to a friend", systemImage: "gift")
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }

#if !os(watchOS)
                HStack {
                    Button(action: {
#if os(macOS)
                        openWindow(id: "messages")
#else
                        path.append(MessagingDestination.Global)
#endif
                    }) {
                        if unreadMessages.count > 0 {
                            Label("Chat with the developer", systemImage: "message")
                                .badge(unreadMessages.count)
                        } else {
                            Label("Chat with the developer", systemImage: "message")
                        }

                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
#endif

                Button(action: { reportDebugLogs() }) {
                    HStack {
                        Label(reportingDebugLogs ? "Collecting Diagnostics..." : "Send Feedback", systemImage: "square.and.arrow.up")
                        Spacer()
                        if (reportingDebugLogs) {
                            Image(systemName: "rays")
                                .symbolEffect(.variableColor, isActive: true)
                        }
                    }
                }
#if os(macOS)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
#endif
                .sheet(isPresented: Binding<Bool>(
                    get: { self.debugLogReportID != nil && !reportingDebugLogs },
                    set: { if !$0 { self.debugLogReportID = nil } }
                )) {
                    VStack {
                        Text("Your diagnostic report has been created with ID  \"\(debugLogReportID ?? "unknown")\"")
                            .font(.headline)
                            .padding(.bottom, 2)
                        Text("Please send an email to roam-support@msd3.io including the report ID any other feedback")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 2)
                        HStack {
#if !os(tvOS)
                            ShareLink(item: """
        Hi Roam Support (roam-support@msd3.io),
        
        <Add Feedback Here>
        
        ---
        Debug Info Link: https://roam-logs-eyebrows.s3.us-east-1.amazonaws.com/\(debugLogReportID ?? "unknown")
        """, subject: Text("Roam Feedback")) {
                                Label("Open Email Template", systemImage: "square.and.arrow.up")
                            }
#endif
                            Button("Close", systemImage: "xmark", role: .destructive) {debugLogReportID = nil}
                        }
                        
#if os(macOS)
                        Text("Press [esc] to close")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
#endif
                    }
                    .padding()
                }
            }
            
            Section {
                NavigationLink("About", value: AboutDestination.Global)
            }
        }
        .onAppear {
            if destination == .Debugging {
                reportDebugLogs()
            }
        }
#if !os(macOS) && !os(watchOS) && !os(tvOS)
        .refreshable {
            isScanning = true
            defer {
                isScanning = false
            }
            
            await scanningActor.scanIPV4Once()
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                scanDevicesButton
                    .labelStyle(.titleAndIcon)
            }
            ToolbarItem(placement: .primaryAction) {
                addDeviceButton
            }
        }
#endif
#if !os(watchOS) && !os(tvOS)
        .navigationTitle("Settings")
#endif
        .formStyle(.grouped)
        .onAppear {
            let modelContainer = modelContext.container
            self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
            self.deviceActor = DeviceActor(modelContainer: modelContainer)
            
            modelContext.processPendingChanges()
        }
#if !os(watchOS)
        .task(priority: .background) {
            if !scanIpAutomatically {
                return
            }
            
            defer {
                isScanning = false
            }
            
            isScanning = true
            await self.scanningActor.scanIPV4Once()
        }
#endif
    }
    
#if !os(watchOS)
    @ViewBuilder
    var scanDevicesButton: some View {
        Button(isScanning ? "Scanning for devices..." : "Scan for devices", systemImage: isScanning ? "rays" : "arrow.clockwise") {
            Task {
                isScanning = true
                defer {
                    isScanning = false
                }
                
                await scanningActor.scanIPV4Once()
            }
        }
        .symbolEffect(.variableColor, isActive: isScanning)
    }
#endif
    
    
    @ViewBuilder
    var addDeviceButton: some View {
        Button("Add a device manually", systemImage: "plus") {
            let newDevice = Device(name: "New device", location: "http://192.168.0.1:8060/", lastSelectedAt: Date.now, udn: "roam:newdevice-\(UUID().uuidString)")
            do {
                modelContext.insert(newDevice)
                Self.logger.info("Added new empty device \(String(describing: newDevice.persistentModelID))")
                try modelContext.save()
                path.append(DeviceSettingsDestination(newDevice))
            } catch {
                Self.logger.error("Error inserting new device \(error)")
            }
        }
        
    }
}

struct DeviceListItem: View {
    @Bindable var device: Device
    
    var body: some View {
        NavigationLink(value: DeviceSettingsDestination(device)) {
            HStack(alignment: .center) {
                VStack(alignment: .center) {
                    DataImage(from: device.deviceIcon, fallback: "tv")
                        .resizable()
#if !os(tvOS)
                        .controlSize(.extraLarge)
#endif
                        .aspectRatio(contentMode: .fit)
                        .frame(width: DEVICE_ICON_SIZE, height: DEVICE_ICON_SIZE)
                        .padding(4)
                }
                
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                            .frame(width: CIRCLE_SIZE, height: CIRCLE_SIZE)
                        Text(device.name).lineLimit(1)
                    }
                    WrappingHStack(alignment: .bottomLeading, horizontalSpacing: 12, verticalSpacing: 12, fitContentWidth: true) {
                        Text(getHost(from: device.location)).foregroundStyle(Color.secondary).lineLimit(1)
#if !os(watchOS)
                        if device.supportsDatagram == true {
                            Label("Supported", systemImage: "headphones").labelStyle(.badge(.green))
                        } else if device.supportsDatagram == false {
                            Label("Not supported", systemImage: "headphones").labelStyle(.badge(.red))
                        } else {
                            Label("Support unknown", systemImage: "headphones").labelStyle(.badge(.yellow))
                        }
#endif
                    }
                }
            }
        }
    }
}

struct MacSettings: View {
    @State var navPath = NavigationPath()
    var body: some View {
        SettingsNavigationWrapper(path: $navPath) {
            SettingsView(path: $navPath, destination: .Global)
        }
    }
}

struct DeviceDetailView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceDetailView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var deviceActor: DeviceActor!
    
    @Bindable var device: Device
    @State var deviceName: String = ""
    @State var deviceIP: String = ""
    
    @State var showHeadphonesModeDescription: Bool = false
    
    var dismiss: () -> Void
    
    var body: some View {
        Form {
            Section("Parameters") {
                TextField("Name", text: $deviceName)
                    .frame(maxWidth: .infinity)
                TextField("IP Address", text: $deviceIP)
                    .frame(maxWidth: .infinity)
#if os(tvOS)
                Button("Save", systemImage: "checkmark", action: {
                    dismiss()
                })
                
                Button("Delete", systemImage: "trash", role: .destructive, action: {
                    // Don't block the dismiss waiting for save
                    Self.logger.info("Deleting device")
                    Task {
                        do {
                            try await deviceActor.delete(device.persistentModelID)
                            Self.logger.info("Deleted device with id \(String(describing: device.persistentModelID))");
                        } catch {
                            Self.logger.error("Error deleting device \(error)")
                        }
                    }
                    
                    dismiss()
                })
                .foregroundStyle(Color.red)
#endif
            }
            
            #if !os(watchOS)
            Section("Private listening") {
                Button(action: {
                    withAnimation {
                        showHeadphonesModeDescription = !showHeadphonesModeDescription
                    }
                }) {
                    LabeledContent("Supports headphones mode") {
                        HStack(spacing: 8) {
                            if device.supportsDatagram == true {
                                Label("Supported", systemImage: "headphones").labelStyle(.badge(.green))
                            } else if device.supportsDatagram == false {
                                Label("Not supported", systemImage: "headphones").labelStyle(.badge(.red))
                            } else {
                                Label("Support unknown", systemImage: "headphones").labelStyle(.badge(.yellow))
                            }
                            
                            Image(systemName: "info.circle")
                            
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if showHeadphonesModeDescription {
                    if device.supportsDatagram == true {
                        Text("Your Roku device supports streaming audio directly to Roam. Click the headphones button in the main view to see it in action!")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if device.supportsDatagram == false {
                        Text("Some Roku devices support streaming audio directly to Roam. Unfortunately yours does not support this. To see which devices support this check out https://www.roku.com/products/compare")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text("Some Roku devices support streaming audio directly to Roam. Roam hasn't been able to check for support on this device. Click the headphones button in the main view to see if it works for you or visit https://www.roku.com/products/compare to see which devices do support this feature.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            #endif
            

            
            Section("Info") {
                LabeledContent("Id") {
                    Text(device.udn)
                }
                LabeledContent("Last Selected") {
                    Text(device.lastSelectedAt?.formatted() ?? "Never")
                    
                }
                LabeledContent("Last Online") {
                    Text(device.lastOnlineAt?.formatted() ?? "Never")
                }
                
                LabeledContent("Power State") {
                    Text(device.powerMode ?? "--")
                }
                
                LabeledContent("Network State") {
                    Text(device.networkType ?? "--")
                }
                
                LabeledContent("Wifi MAC") {
                    Text(device.wifiMAC ?? "--")
                }
                
                LabeledContent("Ethernet MAC") {
                    Text(device.ethernetMAC ?? "--")
                }
                
                LabeledContent("RTCP Port") {
                    if let rtcpPort = device.rtcpPort {
                        Text("\(rtcpPort)")
                    } else {
                        Text("Unknown")
                    }
                }
#if os(tvOS)
                .focusable()
#endif
                
            }
        }
        .formStyle(.grouped)
        .onChange(of: device.name) { prev, new in
            deviceName = new
        }
        .onChange(of: device.location) { prev, new in
            let host = getHost(from: new)
            Self.logger.info("Seeing host \(host) in change")
            deviceIP = host
        }
        .onAppear {
            deviceName = device.name
            let host = getHost(from: device.location)
            Self.logger.info("Seeing host \(host) in appear")
            
            deviceIP = host
        }
        .onDisappear {
            Task {
                await saveDevice(
                    existingDeviceId: device.persistentModelID,
                    existingUDN: device.udn,
                    newIP: deviceIP,
                    newDeviceName: deviceName,
                    deviceActor: DeviceActor(
                        modelContainer: modelContext.container
                    )
                )
            }
        }
#if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save", systemImage: "checkmark", action: {
                    dismiss()
                })
            }
            
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", systemImage: "trash", role: .destructive, action: {
                    // Don't block the dismiss waiting for save
                    Self.logger.info("Deleting device")
                    Task {
                        do {
                            try await deviceActor.delete(device.persistentModelID)
                            Self.logger.info("Deleted device with id \(String(describing: device.persistentModelID))");
                        } catch {
                            Self.logger.error("Error deleting device \(error)")
                        }
                    }
                    
                    dismiss()
                })
                .foregroundStyle(Color.red)
            }
        }
#endif
        .onAppear {
            let modelContainer = modelContext.container
            self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
            self.deviceActor = DeviceActor(modelContainer: modelContainer)
        }
        
#if os(macOS)
        .padding()
#endif
    }
}

extension Binding where Value == Bool {
    /// Creates a binding by mapping an optional value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` the value
    /// of `bindingToOptional`'s `wrappedValue` is set to `nil`.
    ///
    /// Setting the value of the produce binding to `true` does nothing and
    /// will log an error.
    ///
    /// - parameter bindingToOptional: A `Binding` to an optional value, used to calculate the `wrappedValue`.
    public init<Wrapped>(mappedTo bindingToOptional: Binding<Wrapped?>) {
        self.init(
            get: { bindingToOptional.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    bindingToOptional.wrappedValue = nil
                } else {
                    os_log(
                        .error,
                        "Optional binding mapped to optional has been set to `true`, which will have no effect. Current value: %@",
                        String(describing: bindingToOptional.wrappedValue)
                    )
                }
            }
        )
    }
}

extension Binding {
    /// Returns a binding by mapping this binding's value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` this binding's value
    /// is set to `nil`.
    public func mappedToBool<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        return Binding<Bool>(mappedTo: self)
    }
}

enum SettingsDestination{
    case Global
    case Debugging
}


struct DeviceSettingsDestination: Hashable {
    let device: Device
    
    init(_ device: Device) {
        self.device = device
    }
}


#Preview("Device List") {
    @State var path: NavigationPath = NavigationPath()
    return SettingsView(path: $path, destination: .Global)
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(devicePreviewContainer)
}

#Preview("Device Detail") {
    DeviceDetailView(device: getTestingDevices()[0]){}
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
