#if os(macOS)
    import AppKit
    import SwiftUI

    struct CaptureVerticalScrollWheelModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(ScrollWheelHandlerView())
        }

        struct ScrollWheelHandlerView: NSViewRepresentable {
            func makeNSView(context _: Context) -> NSView {
                let view = ScrollWheelReceivingView()
                return view
            }

            func updateNSView(_: NSView, context _: Context) {}
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
                var scrollDist = event.scrollingDeltaX
                if abs(scrollDist) < 0.000001 {
                    scrollDist = event.scrollingDeltaY
                }
                if !event.hasPreciseScrollingDeltas {
                    scrollDist *= 4
                }

                // Handle legacy mice as event.phase == .none && event.momentumPhase == .none
                if event.phase == .began || event
                    .phase == .changed || (event.phase.rawValue == 0 && event.momentumPhase.rawValue == 0)
                {
                    handleScroll(with: scrollDist)
                    scrollVelocity = scrollDist * 1.4
                } else if event.phase == .ended {
                    decelerationTimer = Timer
                        .scheduledTimer(withTimeInterval: 0.009, repeats: true) { [weak self] timer in
                            guard let self else { timer.invalidate(); return }
                            decelerateScroll()
                        }
                } else if event.momentumPhase == .ended {
                    decelerationTimer?.invalidate()
                    decelerationTimer = nil
                }
            }

            private func handleScroll(with delta: CGFloat) {
                let scrollDist = delta

                guard let scrollView = enclosingScrollView else { return }
                let contentView = scrollView.contentView
                let contentSize = contentView.documentRect.size
                let scrollViewSize = scrollView.bounds.size

                let currentPoint = contentView.bounds.origin
                var newX = currentPoint.x - scrollDist

                // Clamp to viewable region
                let maxX = contentSize.width - scrollViewSize.width
                newX = max(newX, 0)
                newX = min(newX, maxX)

                scrollView.contentView.scroll(to: NSPoint(x: newX, y: currentPoint.y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            private func decelerateScroll() {
                if abs(scrollVelocity) < 0.1 {
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
            modifier(CaptureVerticalScrollWheelModifier())
        }
    }
#endif
