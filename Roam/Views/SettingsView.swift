import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.lastSelectedAt) private var devices: [Device]
    
    @State private var selectedDeviceId: String?
    private var selectedDevice: Device? {
        devices.first {d in
            d.id == selectedDeviceId
        }
    }
    
    @State private var scanningActor: DeviceScanningActor!
    @State private var isScanning: Bool = false
    
    @State private var tabSelection = 0
    
    @AppStorage("scanIPAutomatically") private var scanIpAutomatically: Bool = true
    @AppStorage("controlVolumeWithHWButtons") private var controlVolumeWithHWButtons: Bool = true
    
    var body: some View {
        TabView(selection: $tabSelection) {
            deviceSettings
                .tabItem {
                    Label("Devices", systemImage: "sparkles.tv")
                }
                .tag(0)
            
            behaviorSettings
                .tabItem {
                    Label("Behavior", systemImage: "gearshape")
                }
                .tag(1)
        }
    }
    
@ViewBuilder
    var behaviorSettings: some View {
    Form {
        #if os(iOS)
        Toggle("Use volume buttons to control TV volume", isOn: $controlVolumeWithHWButtons)
        #endif
        
        Toggle("Scan for devices when app opens", isOn: $scanIpAutomatically)
    }
    .formStyle(.grouped)
}
    
    @ViewBuilder
    var deviceSettings: some View {
#if os(macOS)
        VStack {
            deviceList
                .sheet(isPresented: $selectedDeviceId.mappedToBool()) {
                    if let dev = selectedDevice {
                        DeviceDetailView(device: dev) {
                            selectedDeviceId = nil
                        }
                    }
                }
                .onAppear {
                    let modelContainer = modelContext.container
                    self.scanningActor = DeviceScanningActor(modelContainer: modelContainer)
                }
                .task(priority: .low) {
                    if !scanIpAutomatically {
                        return
                    }

                    defer {
                        isScanning = false
                    }
                    
                    isScanning = true
                    await self.scanningActor.scanIPV4Once()
                }
            
            HStack (alignment: .center) {
                addDeviceButton
                    .padding()
                
                scanDevicesButton
                    .padding()
            }
            
        }
#else
        NavigationSplitView {
            deviceList
                .onAppear {
                    let modelContainer = modelContext.container
                    self.scanningActor = DeviceScanningActor(modelContainer: modelContainer)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        addDeviceButton
                    }
                    ToolbarItem(placement: .status) {
                        scanDevicesButton
                    }
                }
                .task(priority: .low) {
                    if !scanIpAutomatically {
                        return
                    }
                    defer {
                        isScanning = false
                    }
                    isScanning = true
                    await self.scanningActor.scanIPV4Once()
                }
                .navigationTitle("Devices")
        } detail: {
            if let dev = selectedDevice {
                DeviceDetailView(device: dev) {
                    selectedDeviceId = nil
                }
            }
        }
#endif

    }
    
    @ViewBuilder
    var deviceList: some View {
        if devices.isEmpty {
            List {
                Text("No devices")
                    .foregroundStyle(Color.secondary)
            }
        } else {
            List(devices, selection: $selectedDeviceId) { device in
                DeviceListItem(device: device)
            }
        }
        
    }
    
    @ViewBuilder
    var addDeviceButton: some View {
        Button("Add device", systemImage: "plus") {
            let newDevice = Device(name: "New device", location: "http://192.168.0.1:8060/", lastSelectedAt: Date.now, id: UUID().uuidString)
            do {
                modelContext.insert(newDevice)
                try modelContext.save()
            } catch {
                Self.logger.error("Error inserting new device \(error)")
            }
            selectedDeviceId = newDevice.id
        }
        
    }
    
    @ViewBuilder
    var scanDevicesButton: some View {
        Button(isScanning ? "Scanning..." : "Scan", systemImage: "rays") {
            isScanning = !isScanning
        }
        .task(id: isScanning) {
            if !isScanning {
                return
            }
            isScanning = true
            defer {
                isScanning = false
            }
            
            await scanningActor.scanIPV4Once()
        }
        .labelStyle(.titleAndIcon)
        .symbolEffect(.variableColor, isActive: isScanning)
        
    }
}

func DataImage(from data: Data?, fallback: String) -> Image {
    if let data = data {
#if os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: fallback)
        }
#else
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
        } else {
            Image(systemName: fallback)
        }
#endif
    } else {
        Image(systemName: fallback)
    }
}

struct DeviceListItem: View {
    @Bindable var device: Device
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .center) {
                DataImage(from: device.deviceIcon, fallback: "tv")
                    .resizable()
                    .controlSize(.extraLarge)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32.0, height: 32.0)
            }.frame(width: 60)
            
            VStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(device.name)
                }
                Text(device.location).foregroundStyle(Color.secondary)
            }
        }
    }
}

struct DeviceDetailView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceDetailView.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var scanningActor: DeviceScanningActor!
    
    @Bindable var device: Device
    @State var deviceName: String = ""
    @State var deviceLocation: String = ""
    
    var dismiss: () -> Void
    
    var body: some View {
        Form {
            Section("Parameters") {
                TextField("Name", text: $deviceName)
                    .frame(maxWidth: .infinity)
                TextField("Location URL", text: $deviceLocation)
                    .frame(maxWidth: .infinity)
            }
            
            Section("Info") {
                LabeledContent("Id") {
                    Text(device.id)
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
                
                
                LabeledContent("Supports datagram") {
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
        .onAppear {
            deviceName = device.name
            deviceLocation = device.location
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save", systemImage: "checkmark", action: {
                    Task {
                        // Try to get device id
                        
                        var deviceInfo: DeviceInfo? = nil
                        
                        if await canConnectTCP(location: deviceLocation, timeout: 1) {
                            deviceInfo = await scanningActor.fetchDeviceInfo(location: deviceLocation)
                        }
                        
                        if let id = deviceInfo?.udn {
                            if id != device.id {
                                modelContext.insert(Device(name: deviceName, location: deviceLocation, id: id))
                                
                                try modelContext.save()
                                
                                modelContext.delete(device)
                            } else {
                                device.location = deviceLocation
                                device.name = deviceName
                            }
                        } else {
                            device.location = deviceLocation
                            device.name = deviceName
                        }
                        
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            Self.logger.error("Error saving device changes \(error)")
                        }
                    }
                })
            }
            
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", systemImage: "trash", role: .destructive, action: {
                    do {
                        modelContext.delete(device)
                        try modelContext.save()
                        dismiss()
                    } catch {
                        Self.logger.error("Error deleting device \(error)")
                    }
                })
                .foregroundStyle(Color.red)
            }
        }          
        .onAppear {
            let modelContainer = modelContext.container
            self.scanningActor = DeviceScanningActor(modelContainer: modelContainer)
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


#Preview("Device List") {
    SettingsView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(devicePreviewContainer)
}

#Preview("Device Detail") {
    DeviceDetailView(device: getTestingDevices()[0]){}
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
