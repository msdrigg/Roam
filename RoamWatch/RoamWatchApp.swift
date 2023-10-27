import SwiftUI
import SwiftData
import os.log

@main
struct RoamWatch: App {
    var sharedModelContainer: ModelContainer
    init() {
        do {
            sharedModelContainer = try getSharedModelContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            WatchAppView()
        }
        .modelContainer(sharedModelContainer)
    }
}

let DPAD: [[RemoteButton?]] = [
    [
        .back, .up, .power
    ],
    [
        .left, .select, .right
    ],
    [
        .volumeDown, .down, .volumeUp
    ]
]

let CONTROLS: [[RemoteButton?]] = [
    [
        .instantReplay, .home, .options
    ],
    [
        .rewind, .playPause, .fastForward
    ],
    [
        .volumeDown, .mute, .volumeUp
    ]
]

struct WatchAppView: View {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WatchAppView.self)
    )
    
    @State private var scanningActor: DeviceDiscoveryActor!
    
    @Query(sort: \Device.name, order: .reverse) private var devices: [Device]
    @State private var manuallySelectedDevice: Device?
    
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    
    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    private var selectedDevice: Device? {
        return manuallySelectedDevice ?? devices.min { d1, d2 in
            (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
        }
    }
    
    var mainBody: some View {
        NavigationStack {
            TabView {
                
                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: DPAD)
                
                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: CONTROLS)
                
                AppListView(device: selectedDevice?.toAppEntity(), apps: selectedDevice?.appsSorted.map{$0.toAppEntity()} ?? [])
            }
                .navigationTitle(selectedDevice?.name ?? "No device")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DevicePicker(
                        devices: devices,
                        device: $manuallySelectedDevice.withDefault(selectedDevice)
                    )
                    .font(.body)
                }
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                let modelContainer = modelContext.container
                self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
            }
        }
    }
    
    
    var body: some View {
        if runningInPreview {
            mainBody
        } else {
            mainBody
                .task(id: selectedDevice?.id, priority: .medium) {
                    if let devId = selectedDevice?.persistentModelID {
                        await self.scanningActor.refreshSelectedDeviceContinually(id: devId)
                    }
                }
        }
    }
}
