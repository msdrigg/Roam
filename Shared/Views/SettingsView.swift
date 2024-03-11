import SwiftUI
import SwiftData
import os


private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.lastSelectedAt)])
    fd.relationshipKeyPathsForPrefetching = [\.apps]
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt, \.deviceIcon]
    return fd
}()

struct SettingsView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    @Query(deviceFetchDescriptor) private var devices: [Device]
    @Binding var path: NavigationPath
    
    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var isScanning: Bool = false
    
    @State private var deviceActor: DeviceActor!
    
    
    @State private var tabSelection = 0
    @State private var showWatchOSNote = false
    
    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true
    
    @State private var showKeyboardShortcuts: Bool = false
    @State private var reportingDebugLogs: Bool = false
    @State private var debugLogsReportId: String? = nil
    
    func reportDebugLogs() {
        Task {
            reportingDebugLogs = true
            debugLogsReportId = "Error uploading"
            defer { reportingDebugLogs = false }
            Self.logger.info("Starting to send logs")
            let logs = await getDebugInfo(container: getSharedModelContainer(), message: "Requested from settings")
            Self.logger.info("Sending logs \(logs.id)")

            let bucketName = "roam-logs-eyebrows"
            let objectKey = logs.id
            let region = "us-east-1"
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601 // Or .formatted(DateFormatter) if you want a custom format

                let jsonData = try encoder.encode(logs)

                guard let url = URL(string: "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)") else {
                    Self.logger.error("Error uploading to S3: BadURL")
                    return
                }
                Self.logger.info("Encoded logs into json data \(jsonData.count). Uploading to \(url)")

                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                request.httpBody = jsonData

                let (_, response) = try await URLSession.shared.data(for: request)
                
                // Log the upload result
                Self.logger.info("Getting upload result")
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    Self.logger.error("Server error")
                    return
                }
                
                // Successfully uploaded to S3
                Self.logger.info("Upload successful")
                debugLogsReportId = logs.id
            } catch {
                Self.logger.error("Failed to upload logs to s3: \(error)")
            }
        }
        
    }
    
    var body: some View {
        Form {
            Section("Devices") {
                if devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(devices) { device in
                        DeviceListItem(device: device)
                            .id("\(device.name)\(device.udn)\(device.isOnline())\(device.location)")
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
#if os(watchOS)
                addDeviceButton
#endif
                
#if os(macOS)
                HStack {
                    addDeviceButton
                    
                    Spacer()
                    
                    scanDevicesButton
                }
#endif
            }
            
#if os(watchOS)
            Button("WatchOS Note", systemImage: "info.circle.fill", action: {showWatchOSNote = true})
                .sheet(isPresented: $showWatchOSNote) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unfortunately, WatchOS prevents us from discovering TV's on the local network.").font(.caption).foregroundStyle(.secondary)
                                Text("To work around this limitation, first discover devices on the iPhone app and then the devices will be transfered in the background from the iPhone to the watch (or you can manually add the TV if you can get it's IP address).").font(.caption).foregroundStyle(.secondary)
                                Text("Please be patient, because I don't have an apple watch so I can't test how effective this is. Please reach out if you aren't able to get this to work :). You can email me at scott@msd3.io").font(.caption).foregroundStyle(.secondary)
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
            
#if os(macOS)
            Button(action: {showKeyboardShortcuts = true}) {
                HStack {
                    Label("Keyboard shortcuts", systemImage: "keyboard")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k")
#endif
            
            NavigationLink("About", value: AboutDestination.Global)
            
            Button(action: { reportDebugLogs() }) {
                HStack {
                    Label("Report Debug Logs", systemImage: "gear")
                    Spacer()
                    if (reportingDebugLogs) {
                        Image(systemName: "rays")
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .sheet(isPresented: Binding<Bool>(
                get: { self.debugLogsReportId != nil && !reportingDebugLogs },
                set: { if !$0 { self.debugLogsReportId = nil } }
            )) {
                VStack {
                    Text("Log Report ID:")
                        .font(.headline)
                        .padding(.bottom, 1)
                    Text(debugLogsReportId ?? "unknown")
                        .font(.title)
                        .fontWeight(.semibold)
                        .padding(.bottom, 5)
                    Text("If you are submitting a bug report, include this ID in your message")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 2)
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
#if os(macOS)
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutPanel()
        }
#endif
        
#if os(iOS)
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
#if !os(watchOS)
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
}

struct DeviceListItem: View {
    @Bindable var device: Device
    
    var body: some View {
        NavigationLink(value: DeviceSettingsDestination(device)) {
            HStack(alignment: .center) {
                VStack(alignment: .center) {
                    DataImage(from: device.deviceIcon, fallback: "tv")
                        .resizable()
                        .controlSize(.extraLarge)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24.0, height: 24.0)
                        .padding(4)
                }
                
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        Text(device.name).lineLimit(1)
                    }
                    Text(getHost(from: device.location)).foregroundStyle(Color.secondary).lineLimit(1)
                }
            }
        }
    }
}

struct SettingsNavigationWrapper<Content>: View where Content : View {
    @Binding var path: NavigationPath
    @ViewBuilder let content: () -> Content
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack(path: $path) {
            content()
            
                .navigationDestination(for: SettingsDestination.self) { _ in
                    SettingsView(path: $path)
                }
                .navigationDestination(for: AboutDestination.self) { _ in
                    AboutView()
                }
                .navigationDestination(for: DeviceSettingsDestination.self) { destination in
                    DeviceDetailView(device: destination.device) {
                        if path.count > 0 {
                            path.removeLast()
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
            SettingsView(path: $navPath)
        }
    }
}

func getHost(from urlString: String) -> String {
    guard let url = URL(string: addSchemeAndPort(to: urlString)), let host = url.host else {
        return urlString
    }
    return host
}

func addSchemeAndPort(to urlString: String, scheme: String = "http", port: Int = 8060) -> String {
    let urlString = "http://" + urlString.replacing(/^.*:\/\//, with: { _ in "" })
    
    guard let url = URL(string: urlString), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return urlString
    }
    components.scheme = scheme
    components.port = url.port ?? port // Replace the port only if it's not already specified
    
    return (components.string ?? urlString).replacing(/\/*$/, with: {_ in ""}) + "/"
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
    
    var dismiss: () -> Void
    
    var body: some View {
        Form {
            Section("Parameters") {
                TextField("Name", text: $deviceName)
                    .frame(maxWidth: .infinity)
                TextField("IP Address", text: $deviceIP)
                    .frame(maxWidth: .infinity)
            }
            
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
                
                
                LabeledContent("Supports private listening") {
                    if let supportsDatagram = device.supportsDatagram {
                        if supportsDatagram {
                            Text("Yes!")
                        } else {
                            Text("No :(")
                        }
                    } else {
                        Text("Unknown")
                    }
                }
                LabeledContent("RTCP Port") {
                    if let rtcpPort = device.rtcpPort {
                        Text("\(rtcpPort)")
                    } else {
                        Text("Unknown")
                    }
                }
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
        .onChange(of: deviceIP) { prev, new in
            Self.logger.info("Changing from \(prev) to \(new)")
        }
        .onAppear {
            deviceName = device.name
            let host = getHost(from: device.location)
            Self.logger.info("Seeing host \(host) in appear")
            
            deviceIP = host
        }
        .onDisappear {
            Task {
                await saveDevice()
            }
        }
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
        .onAppear {
            let modelContainer = modelContext.container
            self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
            self.deviceActor = DeviceActor(modelContainer: modelContainer)
        }
        
#if os(macOS)
        .padding()
#endif
    }
    
    func saveDevice() async {
        // Try to get device id
        // Watchos can't check tcp connection, so just do the request
        let cleanedString = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        let deviceUrl = addSchemeAndPort(to: cleanedString)
        Self.logger.info("Getting device url \(deviceUrl)")
        let deviceInfo = await fetchDeviceInfo(location: deviceUrl)
        
        // If we get a device with a different UDN, replace the device
        if let udn = deviceInfo?.udn, udn != device.udn {
            do {
                try await deviceActor.delete(device.persistentModelID)
                let _ = try await deviceActor.addOrReplaceDevice(
                    location: deviceUrl, friendlyDeviceName: deviceName, udn: udn
                )
                
            } catch {
                Self.logger.error("Error saving device \(error)")
            }
            return
        }
        
        do {
            Self.logger.info("Saving devicea abd \(deviceUrl) with da \(String(describing: deviceActor)) id \(String(describing: device.persistentModelID))")
            try await deviceActor.updateDevice(
                device.persistentModelID,
                name: deviceName,
                location: deviceUrl,
                udn: device.udn
            )
            Self.logger.info("Saved device \(deviceUrl)")
        } catch {
            Self.logger.error("Error saving device \(error)")
        }
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
}

struct DeviceSettingsDestination: Hashable {
    let device: Device
    
    init(_ device: Device) {
        self.device = device
    }
}


#Preview("Device List") {
    @State var path: NavigationPath = NavigationPath()
    return SettingsView(path: $path)
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(devicePreviewContainer)
}

#Preview("Device Detail") {
    DeviceDetailView(device: getTestingDevices()[0]){}
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
