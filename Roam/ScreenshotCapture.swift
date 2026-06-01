#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// macOS screenshot helpers driven by launch arguments.
///
/// The capture itself is performed *outside* the app — the Python
/// orchestrator (`scripts/sync-metadata.py` → `scripts/tart_screenshots.py`)
/// runs `screencapture -x` (or `-R x,y,w,h` for menu-bar crops) inside a
/// Tart-managed guest VM with a 2880x1800 display. The app's only job
/// here is to render the requested state and, for the MenuBarExtra
/// capture, click its status item open and report the icon + popover
/// frames so the orchestrator can crop precisely.
///
/// Recognized launch args (all optional):
///   `-OpenMenuBarExtra`           — force `showMenuBar = true` so SwiftUI
///                                   installs the `MenuBarExtra`, activate
///                                   the app, then click the status item
///                                   button to open the popover.
///   `-MenuBarExtraReportPath <p>` — JSON file the app writes containing
///                                   the icon's status-bar window frame,
///                                   the popover window frame (when found),
///                                   the main display frame, the backing
///                                   scale factor, and a diagnostic dump
///                                   of every NSApp.windows entry.
///                                   Frames are AppKit bottom-origin
///                                   screen points.
enum MacScreenshotCapture {
    static var wantsMenuBarExtra: Bool {
        CommandLine.arguments.contains("-OpenMenuBarExtra")
    }

    static var menuBarExtraReportPath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-MenuBarExtraReportPath"),
              i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func scheduleIfRequested(appDelegate _: RoamAppDelegate) {
        guard wantsMenuBarExtra else { return }

        // NOTE: `showMenuBar` must already be true when the app's scene
        // graph is first built — the orchestrator passes `-showMenuBar YES`
        // as a launch argument so the @AppStorage reads true from the
        // NSArgumentDomain. Do NOT flip it here at runtime: toggling the
        // `MenuBarExtra(isInserted:)` binding after the scene graph exists
        // sends SwiftUI into an infinite scene-update recursion
        // (graphDidChange → scenesDidChange → … ) that overflows the stack
        // and crashes the app.

        // Activate so the popover attaches to the icon when clicked.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            await openMenuBarPopoverAndReport()
        }
    }

    @MainActor
    private static func openMenuBarPopoverAndReport() async {
        // SwiftUI's `MenuBarExtra` installs its status item inside an
        // `NSStatusBarWindow` that shows up in `NSApp.windows`. (The
        // private `NSStatusBar._statusItems` accessor returns empty for
        // SwiftUI-created items, so we match the window by class instead.)
        let statusWindow = await waitForStatusBarWindow(timeout: 10.0)
        guard let statusWindow else {
            writeReport(
                iconFrame: nil,
                popoverFrame: nil,
                error: "no NSStatusBarWindow appeared within 10s of -OpenMenuBarExtra"
            )
            FileHandle.standardError.write(
                Data("MENUBAR_ERROR: no NSStatusBarWindow appeared\n".utf8))
            return
        }
        // The status bar window's frame IS the icon's on-screen box.
        let iconScreenFrame = statusWindow.frame
        let windowsBeforeClick = snapshotVisibleWindowIdentities()

        // Click the status item button to open the .window-style popover.
        if let content = statusWindow.contentView,
           let button = firstButton(in: content) {
            button.performClick(nil)
        } else {
            FileHandle.standardError.write(
                Data("MENUBAR_WARN: no button in status window; reporting icon only\n".utf8))
        }

        // Poll up to ~3s for the popover window to appear below the icon.
        let popoverFrame = await waitForPopover(
            iconFrame: iconScreenFrame,
            seen: windowsBeforeClick,
            timeout: 3.0
        )
        writeReport(
            iconFrame: iconScreenFrame,
            popoverFrame: popoverFrame,
            error: popoverFrame == nil
                ? "popover window not detected after performClick"
                : nil
        )
    }

    // MARK: - Status bar window detection

    @MainActor
    private static func statusBarWindow() -> NSWindow? {
        // Prefer the visible NSStatusBarWindow highest on screen (largest
        // minY) on the main display — that's our menu-bar icon.
        NSApp.windows
            .filter { window in
                guard window.isVisible else { return false }
                return NSStringFromClass(type(of: window)).contains("StatusBarWindow")
            }
            .max(by: { $0.frame.minY < $1.frame.minY })
    }

    /// A freshly created status item window briefly sits at the screen
    /// origin (frame y ≈ -24) before macOS lays out the menu bar and
    /// places it at the top-right. Reading the frame before placement
    /// gives bogus coordinates, so we wait until the window's top edge
    /// reaches the menu bar band at the top of the main display.
    @MainActor
    private static func isPlacedInMenuBar(_ window: NSWindow) -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return false
        }
        // AppKit is bottom-origin: the menu bar is at the top, so a placed
        // status item's maxY is within a couple points of the screen's maxY.
        return window.frame.maxY >= screen.frame.maxY - 4
    }

    @MainActor
    private static func waitForStatusBarWindow(timeout: TimeInterval) async -> NSWindow? {
        let pollInterval: TimeInterval = 0.25
        let deadline = Date().addingTimeInterval(timeout)
        var lastSeen: NSWindow?
        while Date() < deadline {
            if let window = statusBarWindow() {
                lastSeen = window
                if isPlacedInMenuBar(window) {
                    return window
                }
            }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
        // Timed out waiting for placement — return whatever we last saw so
        // the caller can still report (with possibly-imperfect coords)
        // rather than failing outright.
        return lastSeen
    }

    /// Depth-first search for the first NSButton in a view subtree — the
    /// status item's clickable button lives inside the status bar window's
    /// content view.
    @MainActor
    private static func firstButton(in view: NSView) -> NSButton? {
        if let b = view as? NSButton { return b }
        for sub in view.subviews {
            if let b = firstButton(in: sub) { return b }
        }
        return nil
    }

    // MARK: - Popover detection

    /// Identity of a window stable enough to diff snapshots across a click.
    private struct WindowID: Hashable {
        let pointer: UInt
        let windowNumber: Int
    }

    @MainActor
    private static func snapshotVisibleWindowIdentities() -> Set<WindowID> {
        var set = Set<WindowID>()
        for window in NSApp.windows where window.isVisible {
            set.insert(WindowID(
                pointer: UInt(bitPattern: ObjectIdentifier(window).hashValue),
                windowNumber: window.windowNumber
            ))
        }
        return set
    }

    @MainActor
    private static func waitForPopover(
        iconFrame: NSRect,
        seen: Set<WindowID>,
        timeout: TimeInterval
    ) async -> NSRect? {
        let pollInterval: TimeInterval = 0.15
        let deadline = Date().addingTimeInterval(timeout)
        // The popover for .menuBarExtraStyle(.window) anchors just below
        // the menu-bar icon — its top edge should be within ~30pt of the
        // icon window's bottom edge.
        let menuBarBottom = iconFrame.minY
        let skipIDs: Set<String> = ["main", "about", "messages"]
        while Date() < deadline {
            for window in NSApp.windows {
                guard window.isVisible else { continue }
                let id = WindowID(
                    pointer: UInt(bitPattern: ObjectIdentifier(window).hashValue),
                    windowNumber: window.windowNumber
                )
                if seen.contains(id) { continue }
                if let identifier = window.identifier?.rawValue,
                   skipIDs.contains(identifier) { continue }
                let cls = NSStringFromClass(type(of: window))
                if cls.contains("StatusBarWindow") { continue }
                // Must be in the menu-bar Y range — guard against picking
                // unrelated SwiftUI helper windows that aren't the popover.
                let gap = menuBarBottom - window.frame.maxY
                if gap < -5 || gap > 60 { continue }
                return window.frame
            }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
        return nil
    }

    // MARK: - Report writing

    @MainActor
    private static func writeReport(
        iconFrame: NSRect?, popoverFrame: NSRect?, error: String?
    ) {
        guard let path = menuBarExtraReportPath else { return }
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let displayFrame = mainScreen?.frame ?? .zero
        let scale = mainScreen?.backingScaleFactor ?? 1.0

        var dict: [String: Any] = [
            "displayFrame": rectDict(displayFrame),
            "backingScaleFactor": Double(scale),
            "windows": windowsDiagnostic(),
            "statusBarWindows": statusBarWindowsDiagnostic(),
        ]
        if let iconFrame { dict["iconFrame"] = rectDict(iconFrame) }
        if let popoverFrame { dict["popoverFrame"] = rectDict(popoverFrame) }
        if let error { dict["error"] = error }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
            )
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            FileHandle.standardOutput.write(
                Data("MENUBAR_REPORT_WRITTEN: \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(
                Data("MENUBAR_ERROR: write report failed: \(error)\n".utf8))
        }
    }

    @MainActor
    private static func windowsDiagnostic() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for window in NSApp.windows {
            rows.append([
                "class": NSStringFromClass(type(of: window)),
                "identifier": window.identifier?.rawValue ?? "",
                "isVisible": window.isVisible,
                "windowNumber": window.windowNumber,
                "frame": rectDict(window.frame),
                "title": window.title,
            ])
        }
        return rows
    }

    @MainActor
    private static func statusBarWindowsDiagnostic() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for window in NSApp.windows where
            NSStringFromClass(type(of: window)).contains("StatusBarWindow") {
            var row: [String: Any] = [
                "frame": rectDict(window.frame),
                "isVisible": window.isVisible,
                "class": NSStringFromClass(type(of: window)),
            ]
            if let content = window.contentView,
               let button = firstButton(in: content), let img = button.image {
                row["imageName"] = img.name() ?? ""
                row["imageAxDescription"] = img.accessibilityDescription ?? ""
            }
            rows.append(row)
        }
        return rows
    }

    private static func rectDict(_ rect: NSRect) -> [String: Double] {
        return [
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "width": Double(rect.size.width),
            "height": Double(rect.size.height),
        ]
    }
}
#endif
