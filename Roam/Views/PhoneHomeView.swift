#if os(iOS)
import SwiftUI
import UIKit

/// Adaptive phone root: a sidebar and remote on the inner display,
/// or a device grid and pushed pager in compact layouts.
///
/// Tapping a card presents `PhoneDeviceDetailPager` full screen, zooming out of
/// the card the way Weather opens a city. `DeviceZoomPresenter` does this in
/// UIKit; see its comment for why.
///
/// When the grid first appears, the selected device's pager is presented
/// without animation so the app opens to the last-viewed remote.
struct PhoneHomeView: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    @State private var didAutoOpenPrimary = false
    // Nil on a phone without a hinge, or while its state is unknown.
    @State private var isHingeOpen: Bool?
    @State private var zoomPresenter = DeviceZoomPresenter()
    @State private var scanIPV4Actor: DeviceDiscoveryActor?
    @State private var scanSSDPActor: DeviceDiscoveryActor?
    @State private var dropTargetId: String?

    // Shared by both navigation modes and the compact grid zoom transition.
    @State private var selectedDeviceId: String?

    private var deviceIds: [String] { devicesLoader.devices ?? [] }
    private var isEmpty: Bool { devicesLoader.devices != nil && deviceIds.isEmpty }
    private var unreadMessages: Int { messageLoader.unreadCount }

    var body: some View {
        // A ZStack rather than a Group, which would give each branch its own
        // hinge observer and rebuild it on every fold.
        ZStack {
            if usesSidebar {
                NavigationStack {
                    PhoneDeviceDetailPager(
                        selectedDeviceId: $selectedDeviceId,
                        allDeviceIds: deviceIds,
                        unreadMessages: unreadMessages,
                        usesSidebar: true,
                        onScan: runManualScan
                    )
                }
            } else {
                phoneNavigation
            }
        }
        .background(
            HingeObserver { [zoomPresenter] isOpen in
                isHingeOpen = isOpen
                // While the pager covers the grid, SwiftUI holds the grid's
                // updates until it is back in the window, so unfolding has to
                // put it back from here.
                if isOpen == true { zoomPresenter.dismissAfterDisplayChange() }
            }
        )
        .onChange(of: usesSidebar) { _, usesSidebar in
            didAutoOpenPrimary = true
            if usesSidebar {
                zoomPresenter.dismissAfterDisplayChange()
            } else if let selectedDeviceId {
                zoomPresenter.present(deviceId: selectedDeviceId, animated: false)
            }
        }
        .onAppear {
            if scanIPV4Actor == nil { scanIPV4Actor = DeviceDiscoveryActor() }
            if scanSSDPActor == nil { scanSSDPActor = DeviceDiscoveryActor() }
        }
        // Only the connected device refreshes its own online status.
        .probingDeviceLiveness(deviceIds, isActive: scenePhase == .active)
        // If the remembered device has gone away, fall back to the next most
        // recently viewed one rather than leaving nothing selected.
        .task(id: deviceIds) {
            do {
                try await RoamDataHandler.shared.ensureValidPrimaryDevice()
            } catch {
                Log.userInteraction.error(
                    "Error selecting an initial device \(error, privacy: .public)")
            }
        }
        .onChange(of: primaryDeviceLoader.device?.id, initial: true) { _, newId in
            guard selectedDeviceId.map({ deviceIds.contains($0) }) != true else { return }
            selectedDeviceId = newId
        }
        .onChange(of: deviceIds) { _, ids in
            if ids.isEmpty {
                selectedDeviceId = nil
                zoomPresenter.dismiss(animated: true)
            }
        }
        .task(id: autoOpenDeviceId) {
            guard !didAutoOpenPrimary, let deviceId = autoOpenDeviceId else { return }
            didAutoOpenPrimary = true
            // No zoom-in from a card the user never tapped; the dismissal still zooms.
            zoomPresenter.present(deviceId: deviceId, animated: false)
        }
    }

    /// A foldable shows the grid on its outer display only, and the sidebar on
    /// the inner display in either orientation.
    private var usesSidebar: Bool {
        if let isHingeOpen { return isHingeOpen }
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var autoOpenDeviceId: String? {
        guard !usesSidebar, let selectedDeviceId, deviceIds.contains(selectedDeviceId) else { return nil }
        return selectedDeviceId
    }

    private var phoneNavigation: some View {
        NavigationStack {
            content
                .navigationTitle(String(
                    localized: "Devices",
                    comment: "Title of the iPhone home screen listing all devices"
                ))
                .navigationBarTitleDisplayMode(.large)
                .applyBuilder {
                    if #available(iOS 26.0, *) {
                        $0
                            .safeAreaInset(edge: .bottom, spacing: 0) { connectivityBanner }
                            .toolbar { homeToolbar }
                    } else {
                        $0.safeAreaInset(edge: .bottom, spacing: 0) { simulatedBottomBar }
                    }
                }
                .background(
                    DeviceZoomPresentationAnchor(
                        presenter: zoomPresenter,
                        selectedDeviceId: selectedDeviceId,
                        content: presentedPager
                    )
                )
                .customAccentColorTint()
        }
    }

    // MARK: - Bottom bar
    //
    // iOS 26 draws toolbar items in liquid glass, and only a real toolbar joins
    // iPhone Duo's vertical bar along the trailing edge of the outer display.
    // Earlier releases keep the simulated bar, whose buttons carry their own
    // glass.

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            // A toolbar reduces a Label to its icon, which is all a vertical
            // bar has room for. The horizontal bar keeps the title.
            ToolbarAxisReader { isVertical in
                addDeviceButton(showsTitle: !isVertical)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if deviceIds.count > 1 {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    DeviceSortOrderPicker()
                } label: {
                    Label(sortDevicesTitle, systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("SortDevicesButton")
                .tint(.primary)
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button {
                appDelegate.navigationPath.append(.settingsDestination(.global))
            } label: {
                Label(settingsTitle, systemImage: "gear")
            }
            .accessibilityIdentifier("SettingsButton")
            .tint(.primary)
        }
    }

    private func addDeviceButton(showsTitle: Bool) -> some View {
        Button {
            appDelegate.navigationPath.showAddDevice = true
        } label: {
            if showsTitle {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(addDeviceTitle)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 6)
            } else {
                Label(addDeviceTitle, systemImage: "plus")
            }
        }
        .accessibilityIdentifier("AddDeviceButton")
        // The pre-26 bar drew white icons, not the accent-tinted default.
        .tint(.primary)
    }

    // Connectivity / permission warnings live above the bottom bar so they
    // stay pinned in place while the device grid scrolls.
    private var connectivityBanner: some View {
        NetworkConnectivityBanner()
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private var addDeviceTitle: String {
        String(
            localized: "Add device manually",
            comment: "Bottom-bar button on iPhone home to manually add a device"
        )
    }

    private var sortDevicesTitle: String {
        String(
            localized: "Sort devices",
            comment: "Accessibility label for the iPhone home button that changes the device order"
        )
    }

    private var settingsTitle: String {
        String(
            localized: "Settings",
            comment: "Bottom-bar button on iPhone home to open Settings"
        )
    }

    private var simulatedBottomBar: some View {
        VStack(spacing: 0) {
            connectivityBanner
            bottomBarButtons
        }
    }

    private var bottomBarButtons: some View {
        HStack(spacing: 12) {
            Button {
                appDelegate.navigationPath.showAddDevice = true
            } label: {
                Label(addDeviceTitle, systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddDeviceButton")

            Spacer()

            if deviceIds.count > 1 {
                sortMenu
            }

            Button {
                appDelegate.navigationPath.append(.settingsDestination(.global))
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SettingsButton")
            .accessibilityLabel(settingsTitle)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, -10)
    }

    /// Sort options. A custom arrangement is made by dragging the cards
    /// themselves, so there's nothing else in here.
    private var sortMenu: some View {
        Menu {
            DeviceSortOrderPicker()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SortDevicesButton")
        .accessibilityLabel(sortDevicesTitle)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            emptyContent
        } else {
            deviceGrid
        }
    }

    private var deviceGrid: some View {
        ScrollView {
            // Eager rather than a LazyVStack so every card's zoom source view
            // exists when the pager is dismissed back to it. Device counts are
            // small enough that building them all is cheap.
            VStack(spacing: 12) {
                ForEach(cardRows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row, id: \.self) { deviceId in
                            deviceCardButton(for: deviceId)
                                .frame(maxWidth: .infinity)
                        }
                        if row.count < cardColumns {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
            }
            .animation(.snappy, value: deviceIds)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await runManualScan() }
    }

    /// Two columns once the width is regular, such as iPhone Duo's inner
    /// display, so the cards don't stretch across it.
    private var cardColumns: Int {
        horizontalSizeClass == .regular ? 2 : 1
    }

    private var cardRows: [[String]] {
        stride(from: 0, to: deviceIds.count, by: cardColumns).map {
            Array(deviceIds[$0..<min($0 + cardColumns, deviceIds.count)])
        }
    }

    private func deviceCardButton(for deviceId: String) -> some View {
        ZoomSourceCard(presenter: zoomPresenter, deviceId: deviceId) {
            deviceCard(for: deviceId)
        }
    }

    /// Hosted by `ZoomSourceCard`, so it carries the accent tint itself.
    private func deviceCard(for deviceId: String) -> some View {
        Button {
            openDevice(deviceId)
        } label: {
            DeviceSidebarCard(deviceId: deviceId)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .deviceActions(
                    deviceId: deviceId,
                    deviceName: nil,
                    onEdit: { appDelegate.navigationPath.showEditDevice = deviceId }
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DeviceCard_\(deviceId)")
        // Long-press to lift a card and drop it on another to take its place,
        // the same idiom as rearranging Home Screen icons. The card keeps its
        // context menu: a long press that doesn't move still opens the menu.
        .overlay {
            if dropTargetId == deviceId {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .draggable(deviceId)
        .dropDestination(for: String.self) { items, _ in
            dropTargetId = nil
            guard let draggedId = items.first else { return false }
            return moveDevice(draggedId, toPositionOf: deviceId)
        } isTargeted: { isTargeted in
            withAnimation(.snappy) {
                if isTargeted {
                    dropTargetId = deviceId
                } else if dropTargetId == deviceId {
                    dropTargetId = nil
                }
            }
        }
        .customAccentColorTint()
    }

    private func openDevice(_ deviceId: String) {
        // A tap that lands while the pager is still zooming away is ignored.
        guard !zoomPresenter.isPresenting else { return }
        selectedDeviceId = deviceId
        zoomPresenter.present(deviceId: deviceId, animated: true)
    }

    /// Moves `draggedId` to where `targetId` currently sits.
    @discardableResult
    private func moveDevice(_ draggedId: String, toPositionOf targetId: String) -> Bool {
        guard draggedId != targetId,
            let from = deviceIds.firstIndex(of: draggedId),
            let to = deviceIds.firstIndex(of: targetId)
        else {
            return false
        }

        // `move(fromOffsets:toOffset:)` inserts *before* `toOffset`, computed
        // against the pre-removal indices - so landing on a card further down
        // the list needs the offset past it, not on it.
        let destination = to > from ? to + 1 : to
        Task {
            do {
                try await RoamDataHandler.shared.reorderDevices(
                    fromOffsets: IndexSet(integer: from), toOffset: destination)
            } catch {
                Log.userInteraction.error("Error reordering devices \(error, privacy: .public)")
            }
        }
        return true
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
    }

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Label(
                    String(
                        localized: "Scanning for devices",
                        comment: "Empty-state heading on iPhone home while no devices have been discovered"
                    ),
                    systemImage: "rays"
                )
                .labelStyle(.titleAndIcon)
                .font(.title3)
                .symbolEffect(.variableColor)
                .padding()
                .glowing()

                Text(
                    "Roam will list Roku devices on your network as they're found.",
                    comment: "Empty-state caption on iPhone home explaining auto-discovery"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await runManualScan() }
    }

    // MARK: - Presented pager

    private func presentedPager() -> AnyView {
        AnyView(
            PresentedPagerRoot(
                initialDeviceIds: deviceIds,
                initialSelection: selectedDeviceId,
                presenter: zoomPresenter,
                onSelect: { selectedDeviceId = $0 },
                onScan: runManualScan
            )
            .environmentObject(appDelegate)
        )
    }

    // MARK: - Scanning

    private func runManualScan() async {
        guard let scanIPV4Actor, let scanSSDPActor else { return }
        await performManualDeviceScan(ipv4Actor: scanIPV4Actor, ssdpActor: scanSSDPActor)
    }
}

// MARK: - Zoom presentation

/// Presents the pager full screen with UIKit's zoom transition, out of and
/// back into the tapped card.
///
/// This is UIKit rather than a SwiftUI push with `.navigationTransition(.zoom)`
/// because the push shared one navigation bar and one bottom toolbar between
/// the grid and the pager. That chrome cross-faded in place instead of
/// zooming with the content, and a cancelled pop on iOS 27.0 could leave the
/// bar invisible or the pager's toolbar stranded over the grid. A modal
/// presentation gives the pager a screen of its own, and UIKit exposes what
/// SwiftUI does not: the source view is looked up when the dismissal starts,
/// the dismiss gesture can be refused, and touches can be cut off while the
/// pager zooms away.
@MainActor
final class DeviceZoomPresenter {
    /// Set by the pager while a gesture inside it should not dismiss it.
    var blocksInteractiveDismiss = false

    var selectedDeviceId: String?
    fileprivate var makeContent: (() -> AnyView)?
    fileprivate var onPresentedChange: ((Bool) -> Void)?

    private weak var anchor: UIViewController?
    private weak var presented: PagerHostingController?
    private var isShowing = false
    private var isDismissing = false
    private var pending: (deviceId: String, animated: Bool)?
    private let sources = NSMapTable<NSString, UIView>.strongToWeakObjects()

    /// True from the moment a presentation starts until its dismissal ends.
    var isPresenting: Bool { isShowing }

    func present(deviceId: String, animated: Bool) {
        guard !isShowing else { return }
        pending = (deviceId, animated)
        presentPendingIfPossible()
    }

    func dismiss(animated: Bool) {
        pending = nil
        guard let presenting = presented?.presentingViewController, !isDismissing else { return }
        Log.userInteraction.notice("Dismissing pager animated \(animated, privacy: .public)")
        isDismissing = true
        // Through the presenter, so a sheet open over the pager goes too.
        presenting.dismiss(animated: animated) { [weak self] in
            self?.didDismiss()
        }
    }

    /// Reached from the dismissal's completion, or from the pager's own
    /// disappearance when the dismiss gesture ends it. During a Duo's move
    /// between displays only the completion is called.
    private func didDismiss() {
        isDismissing = false
        guard isShowing else { return }
        isShowing = false
        onPresentedChange?(false)
    }

    /// Dismisses once a Duo has finished moving to its inner display.
    /// Dismissing during the move interrupts the window's resize, and the
    /// window keeps the outer display's shape, drawing the grid sideways.
    func dismissAfterDisplayChange() {
        guard let presented, !isDismissing else { return }
        presented.afterNextSizeTransition { [weak self, weak presented] in
            // The fallback can land after a fold has presented a new pager.
            guard let self, let presented, self.presented === presented else { return }
            dismiss(animated: false)
        }
    }

    fileprivate func register(_ view: UIView, for deviceId: String) {
        sources.setObject(view, forKey: deviceId as NSString)
    }

    fileprivate func attach(_ anchor: UIViewController) {
        self.anchor = anchor
    }

    fileprivate func anchorDidAppear() {
        presentPendingIfPossible()
    }

    fileprivate func refreshPresentedContent() {
        guard let presented, let makeContent else { return }
        presented.rootView = presented.wrap(makeContent())
    }

    private func presentPendingIfPossible() {
        guard let request = pending, !isShowing, let anchor, let makeContent,
            let window = anchor.view.window
        else {
            return
        }
        pending = nil
        guard window.rootViewController?.presentedViewController == nil else {
            Log.userInteraction.notice("Not presenting the pager over another presentation")
            return
        }

        let host = PagerHostingController(content: makeContent())
        // Over-full-screen would keep the grid live underneath, but it stops
        // following rotation when the Duo moves between displays.
        host.modalPresentationStyle = .fullScreen
        host.overrideUserInterfaceStyle = .dark
        host.onDismissed = { [weak self] in
            self?.didDismiss()
        }
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { [weak self] context in
            MainActor.assumeIsolated {
                guard let self, !self.blocksInteractiveDismiss else { return false }
                // Horizontal drags belong to the pager's paging.
                return abs(context.velocity.dy) >= abs(context.velocity.dx)
            }
        }
        host.preferredTransition = .zoom(options: options) { [weak self] _ in
            MainActor.assumeIsolated { self?.sourceView() }
        }

        presented = host
        isShowing = true
        onPresentedChange?(true)
        Log.userInteraction.notice("Presenting pager animated \(request.animated, privacy: .public)")
        anchor.present(host, animated: request.animated)
    }

    /// The card for the page on screen, scrolled into view. A card that is
    /// gone, or never reached a window, gets the system's fallback zoom
    /// instead, since morphing to a view outside the hierarchy asserts.
    private func sourceView() -> UIView? {
        guard let deviceId = selectedDeviceId,
            let view = sources.object(forKey: deviceId as NSString), view.window != nil
        else {
            return nil
        }
        var ancestor = view.superview
        while let candidate = ancestor, !(candidate is UIScrollView) {
            ancestor = candidate.superview
        }
        if let scrollView = ancestor as? UIScrollView {
            scrollView.scrollRectToVisible(view.convert(view.bounds, to: scrollView), animated: false)
        }
        return view
    }
}

/// The pager's root in its own hosting controller. SwiftUI holds the grid's
/// updates while a full-screen presentation has it out of the window, so
/// this keeps its own device list, unread count and selection rather than
/// reading the grid's.
private struct PresentedPagerRoot: View {
    let initialDeviceIds: [String]
    let presenter: DeviceZoomPresenter
    let onSelect: (String?) -> Void
    let onScan: () async -> Void

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    @State private var selection: String?

    init(
        initialDeviceIds: [String],
        initialSelection: String?,
        presenter: DeviceZoomPresenter,
        onSelect: @escaping (String?) -> Void,
        onScan: @escaping () async -> Void
    ) {
        self.initialDeviceIds = initialDeviceIds
        self.presenter = presenter
        self.onSelect = onSelect
        self.onScan = onScan
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            PhoneDeviceDetailPager(
                selectedDeviceId: $selection,
                allDeviceIds: devicesLoader.devices ?? initialDeviceIds,
                unreadMessages: messageLoader.unreadCount,
                usesSidebar: false,
                onScan: onScan,
                onBackToHome: { presenter.dismiss(animated: true) },
                onBlocksDismissChange: { presenter.blocksInteractiveDismiss = $0 }
            )
        }
        .rootSheets(isActive: true)
        .customAccentColorTint()
        .onChange(of: selection) { _, selection in
            presenter.selectedDeviceId = selection
            onSelect(selection)
        }
    }
}

/// The hosted pager's scene phase. A hosting controller outside a SwiftUI
/// scene reports `.background` throughout, which would pause discovery, so
/// this follows the window scene's notifications instead.
@MainActor @Observable
private final class HostedScenePhase {
    var phase: ScenePhase = .active
}

private struct HostedScenePhaseReader: View {
    let model: HostedScenePhase
    let content: AnyView

    var body: some View {
        content.environment(\.scenePhase, model.phase)
    }
}

private final class PagerHostingController: UIHostingController<AnyView> {
    var onDismissed: (() -> Void)?
    private let scenePhase = HostedScenePhase()
    private var sizeTransitionActions: [@MainActor () -> Void] = []

    init(content: AnyView) {
        super.init(rootView: AnyView(EmptyView()))
        rootView = wrap(content)
        let center = NotificationCenter.default
        let phases: [(Notification.Name, ScenePhase)] = [
            (UIScene.didActivateNotification, .active),
            (UIScene.willDeactivateNotification, .inactive),
            (UIScene.willEnterForegroundNotification, .inactive),
            (UIScene.didEnterBackgroundNotification, .background),
        ]
        for (name, phase) in phases {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sceneId = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, self.isInScene(sceneId) else { return }
                    self.scenePhase.phase = phase
                }
            }
        }
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Runs `action` when the next size transition ends, and again after a
    /// second in case none starts, so it must be safe to repeat.
    func afterNextSizeTransition(_ action: @escaping @MainActor () -> Void) {
        sizeTransitionActions.append(action)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            action()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let actions = sizeTransitionActions
        sizeTransitionActions = []
        guard !actions.isEmpty else { return }
        coordinator.animate(alongsideTransition: nil) { _ in
            actions.forEach { $0() }
        }
    }

    func wrap(_ content: AnyView) -> AnyView {
        AnyView(HostedScenePhaseReader(model: scenePhase, content: content))
    }

    private func isInScene(_ sceneId: ObjectIdentifier?) -> Bool {
        guard let scene = view.window?.windowScene else { return true }
        return sceneId == ObjectIdentifier(scene)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.isUserInteractionEnabled = true
        if let state = view.window?.windowScene?.activationState ?? presentingViewController?.view.window?.windowScene?.activationState {
            scenePhase.phase = switch state {
            case .foregroundActive: .active
            case .foregroundInactive: .inactive
            default: .background
            }
        }
    }

    /// Stops the remote taking touches as soon as any dismissal starts,
    /// interactive or not, and gives them back if it is cancelled. Otherwise
    /// a tap aimed at the grid lands on a remote button mid-zoom.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.isUserInteractionEnabled = false
        transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
            if context.isCancelled {
                self?.view.isUserInteractionEnabled = true
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismissed?()
        }
    }
}

/// Sits behind the grid to give the presenter a view controller to present
/// from, and to present a pending pager once the grid is in a window.
struct DeviceZoomPresentationAnchor: UIViewControllerRepresentable {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    let presenter: DeviceZoomPresenter
    let selectedDeviceId: String?
    let content: () -> AnyView

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.presenter = presenter
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        let navigation = appDelegate.navigationPath
        presenter.selectedDeviceId = selectedDeviceId
        presenter.makeContent = content
        presenter.onPresentedChange = { navigation.phonePagerIsPresented = $0 }
        presenter.attach(controller)
        presenter.refreshPresentedContent()
    }

    final class Controller: UIViewController {
        weak var presenter: DeviceZoomPresenter?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presenter?.anchorDidAppear()
        }
    }
}

/// Hosts a card in its own view so UIKit's zoom has a real view to morph
/// from and back into.
struct ZoomSourceCard<Content: View>: UIViewControllerRepresentable {
    let presenter: DeviceZoomPresenter
    let deviceId: String
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        presenter.register(host.view, for: deviceId)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        host.rootView = content()
        presenter.register(host.view, for: deviceId)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController host: UIHostingController<Content>,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

/// Reports whether a foldable's hinge is open, or nil without a hinge. The
/// interaction goes on the window so it outlives this view's moves.
private struct HingeObserver: UIViewRepresentable {
    let onChange: (Bool?) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.uninstall()
    }

    final class ObserverView: UIView {
        var onChange: ((Bool?) -> Void)?
        private var interaction: (any UIInteraction)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard #available(iOS 27.1, *), let window, interaction?.view !== window else { return }
            uninstall()
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let status = update.hinge?.status else { return }
                self?.onChange?(Self.isOpen(status))
            }
            window.addInteraction(interaction)
            self.interaction = interaction
        }

        func uninstall() {
            if let interaction {
                interaction.view?.removeInteraction(interaction)
            }
            interaction = nil
        }

        @available(iOS 27.1, *)
        private static func isOpen(_ status: UIHinge.Status) -> Bool? {
            switch status {
            case .closed: false
            case .partiallyOpen, .fullyOpen: true
            default: nil
            }
        }
    }
}

/// Reports whether the enclosing toolbar is laid out vertically, as it is
/// along the trailing edge of iPhone Duo's outer display.
struct ToolbarAxisReader<Content: View>: View {
    @ViewBuilder var content: (_ isVertical: Bool) -> Content

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalEdgeReader(content: content)
        } else {
            content(false)
        }
    }

    @available(iOS 27.1, *)
    private struct VerticalEdgeReader: View {
        @Environment(\.toolbarVerticalEdge) private var verticalEdge
        let content: (Bool) -> Content

        var body: some View {
            content(verticalEdge != nil)
        }
    }
}
#endif
