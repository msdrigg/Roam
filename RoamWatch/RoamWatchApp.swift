import SwiftUI
import SwiftData
import os.log

@main
struct RoamWatch: App {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RoamWatch.self)
    )
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
        Self.logger.info("Getting WatchConnectivity \(String(describing: WatchConnectivity.shared))")
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


private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name, order: .reverse)])
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]
    
    return fd
}()

struct WatchAppView: View {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WatchAppView.self)
    )
    
    @State private var scanningActor: DeviceDiscoveryActor!
    
    @Query(deviceFetchDescriptor) private var devices: [Device]
    @State private var manuallySelectedDevice: Device?
    @State private var showDeviceList: Bool = false
    
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
    
    @State var navPath = NavigationPath()
    
    var mainBody: some View {
        NavigationStack {
            TabView {
                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: DPAD)
                
                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: CONTROLS)
                
                if let device = selectedDevice {
                    AppListViewWrapper(device: device.toAppEntity())
                }
            }
            .disabled(selectedDevice == nil)
            .navigationTitle(selectedDevice?.name ?? "No device")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DevicePicker(
                        devices: devices,
                        device: $manuallySelectedDevice.withDefault(selectedDevice),
                        showingPicker: $showDeviceList
                    )
                    .font(.body)
                }
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                let modelContainer = modelContext.container
                self.scanningActor = DeviceDiscoveryActor(modelContainer: modelContainer)
                modelContext.processPendingChanges()
            }
            .overlay {
                if selectedDevice == nil {
                    VStack(spacing: 2) {
                        Spacer().frame(maxHeight: 120)
                        Button(action: {showDeviceList = true}) {
                            Label("Setup a device to get started :)", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                                .font(.subheadline)
                                .padding(8)
                                .background(Color("AccentColor"))
                                .cornerRadius(6)
                                .padding(.horizontal, 4)
                        }
                        .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
    
    
    var body: some View {
        if runningInPreview {
            mainBody
        } else {
            mainBody
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    if let devId = selectedDevice?.persistentModelID {
                        await self.scanningActor.refreshSelectedDeviceContinually(id: devId)
                    }
                }
        }
    }
}

struct AppListViewWrapper: View {
    private let device: DeviceAppEntity
    @Query private var apps: [AppLink]
    @Environment(\.modelContext) private var modelContext
    @State var cachedAppLinks: [AppLink]

    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String>  = Set()
        self.apps.forEach {
            appLinkPairs.insert("\($0.id);\($0.icon != nil)")
        }
        
        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }

    init(device: DeviceAppEntity) {
        let pid = device.udn
        
        self._apps = Query(
            filter: #Predicate {
                pid != nil && $0.deviceUid == pid
            },
            sort: \.lastSelected,
            order: .reverse
        )
        self.device = device
        cachedAppLinks = []
    }
    
    var body: some View {
        AppListView(device: device, apps: cachedAppLinks, onClick: {
            $0.lastSelected = Date.now
            try? modelContext.save()
        })
        .onAppear {
            cachedAppLinks = apps
        }
        .onChange(of: appIdsIconsHashed) {
            cachedAppLinks = apps
        }
    }
}
