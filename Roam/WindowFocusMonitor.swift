#if os(macOS)
import SwiftUI
import AppKit

struct WindowFocusedModifier: ViewModifier {
    let onFocus: () -> Void
    @State private var window: NSWindow?
    @State private var observer: (any NSObjectProtocol)?

    func body(content: Content) -> some View {
        content
            .background(WindowFinder(window: $window))
            .onChange(of: window, initial: true) {
                // Hop off the update pass before reporting focus. `onChange`
                // actions run inside `Update.dispatchActions`, and every
                // `onFocus` handler writes `navigationPath.focusedWindow` --
                // which `RoamApp`'s command groups read, so a synchronous write
                // dirties the app body from inside its own update. The
                // `didBecomeKey` observer below already takes this hop; this
                // path was the one that did not.
                DispatchQueue.main.async {
                    if let window = window, window.isKeyWindow {
                        onFocus()
                    }
                }
            }
            .onAppear {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    DispatchQueue.main.async {
                        if window?.isKeyWindow == true {
                            onFocus()
                        }
                    }
                }
            }
            .onDisappear {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
    }
}

// Helper view to extract the NSWindow
struct WindowFinder: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func onWindowFocused(_ onFocus: @escaping () -> Void) -> some View {
        modifier(WindowFocusedModifier(onFocus: onFocus))
    }
}

#endif
