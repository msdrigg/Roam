import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.lastSelectedAt) private var devices: [Device]
    
    @State private var selectedDeviceId: String?
    private var selectedDevice: Device? {
        devices.first {d in
            d.id == selectedDeviceId
        }
    }
    
    var body: some View {
        Form {
            Section("Devices") {
                if devices.isEmpty {
                    List {
                        Text("No devices")
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    List(devices, selection: $selectedDeviceId) { device in
                        VStack(alignment: .leading) {
                            HStack(alignment: .center, spacing: 4) {
                                Circle()
                                    .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(device.name)
                            }
                            Text(device.location).foregroundStyle(Color.secondary)
                        }
                    }
                    .sheet(isPresented: $selectedDeviceId.mappedToBool()) {
                        if let selectedDevice = selectedDevice {
                            DeviceDetailView(device: selectedDevice)
                        }
                    }
                }
            }
            Button( "Add device", systemImage: "plus") {
                let newDevice = Device(name: "New device", location: "192.168.0.1", lastSelectedAt: Date.now, id: UUID().uuidString)
                modelContext.insert(newDevice)
                selectedDeviceId = newDevice.id
            }
        }
#if os(macOS)
        .padding()
#endif
    }
}

struct DeviceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentationMode) var presentationMode
    
    @Bindable var device: Device
    
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $device.name)
                TextField("Host", text: $device.location)
            }
            Section {
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
            }
            .foregroundStyle(Color.secondary)
            Section {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Save changes", systemImage: "checkmark")
                }
            }
            
            Section {
                Button(action: {
                    do {
                        modelContext.delete(device)
                        try modelContext.save()
                    } catch {
                        os_log("Error deleting device \(error)")
                    }
                }) {
                    Label("Delete device", systemImage: "trash")
                        .foregroundColor(Color.red)
                }
            }
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


#Preview {
    SettingsView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(for: Device.self, inMemory: true)
}

#Preview {
    DeviceDetailView(device: getTestingDevices()[0])
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(for: Device.self, inMemory: true)
}
