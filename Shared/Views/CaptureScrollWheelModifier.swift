#if os(macOS)
import SwiftUI
import AppKit

struct CaptureVerticalScrollWheelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ScrollWheelHandlerView())
    }

    struct ScrollWheelHandlerView: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = ScrollWheelReceivingView()
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    class ScrollWheelReceivingView: NSView {
        private var scrollVelocity: CGFloat = 0
        private var decelerationTimer: Timer?
        
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func scrollWheel(with event: NSEvent) {
            var scrollDist = event.deltaX
            var scrollDelta = event.scrollingDeltaX
            if abs(scrollDist) < abs(event.deltaY) {
                scrollDist = event.deltaY
                scrollDelta = event.scrollingDeltaY
            }
            if event.phase == .began || event.phase == .changed || event.phase.rawValue == 0 {
                // Directly handle scrolling
                handleScroll(with: scrollDist)
                
                scrollVelocity = scrollDelta / 8
            } else if event.phase == .ended {
                // Begin decelerating
                decelerationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
                    guard let self = self else { timer.invalidate(); return }
                    self.decelerateScroll()
                }
            } else if event.momentumPhase == .ended {
                // Invalidate the timer if momentum scrolling has ended
                decelerationTimer?.invalidate()
                decelerationTimer = nil
            }
        }

        private func handleScroll(with delta: CGFloat) {
            var scrollDist = delta
            scrollDist *= 4

            guard let scrollView = self.enclosingScrollView else { return }
            let contentView = scrollView.contentView
            let contentSize = contentView.documentRect.size
            let scrollViewSize = scrollView.bounds.size

            let currentPoint = contentView.bounds.origin
            var newX = currentPoint.x - scrollDist

            // Calculate the maximum allowable X position (right edge of content)
            let maxX = contentSize.width - scrollViewSize.width
            // Ensure newX does not exceed the bounds
            newX = max(newX, 0) // No less than 0 (left edge)
            newX = min(newX, maxX) // No more than maxX (right edge)

            // Scroll to the new X position if it's within the bounds
            scrollView.contentView.scroll(to: NSPoint(x: newX, y: currentPoint.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func decelerateScroll() {
            if abs(scrollVelocity) < 0.3 {
                decelerationTimer?.invalidate()
                decelerationTimer = nil
                return
            }

            handleScroll(with: scrollVelocity)
            scrollVelocity *= 0.9
        }
    }
}

extension View {
    func captureVerticalScrollWheel() -> some View {
        self.modifier(CaptureVerticalScrollWheelModifier())
    }
}
#endif
