import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.lastSelectedAt) private var devices: [Device]
    
    @State private var selectedDeviceId: UUID?
    private var selectedDevice: Device? {
        devices.first {d in
            d.id == selectedDeviceId
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(devices, selection: $selectedDeviceId) { device in
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 4) {
                        Circle()
                            .foregroundColor(device.isOnline() ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(device.name)
                    }
                    Text(device.host).foregroundStyle(Color.secondary)
                }
            }
            .navigationTitle("Devices")
        } detail: {
            if let selectedDevice = selectedDevice {
                DeviceDetailView(device: selectedDevice)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button( "Add device", systemImage: "plus") {
                    let newDevice = Device(name: "New device", host: "192.168.0.1", lastSelectedAt: Date.now)
                    modelContext.insert(newDevice)
                    selectedDeviceId = newDevice.id
                }
            }
        }
    }
}

struct DeviceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var device: Device
    
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $device.name)
                TextField("Host", text: $device.host)
            }
            Section {
                LabeledContent("Last Selected") {
                    Text(device.lastSelectedAt?.formatted() ?? "Never")
                }
                
                LabeledContent("Last Online") {
                    Text(device.lastOnlineAt?.formatted() ?? "Never")
                }
            }
            .foregroundStyle(Color.secondary)
            
            Section {
                Button(action: {
                    modelContext.delete(device)
                }) {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(Color.red)
                }
            }
        }.padding(.horizontal, 20)
    }
}

#Preview {
    SettingsView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(for: Device.self, inMemory: true)
}
