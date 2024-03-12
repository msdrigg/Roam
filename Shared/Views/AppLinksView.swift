import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLinkAppEntity]
    var handleOpenApp: (AppLinkAppEntity) -> Void
    let rows: Int
    @State var cachedAppLinks: [AppLinkAppEntity]
    
    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String>  = Set()
        self.appLinks.forEach {
            appLinkPairs.insert("\($0.id);\($0.icon != nil)")
        }
        
        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }
    
    
    
    @Namespace var linkAnimation
    
    init(appLinks: [AppLinkAppEntity], rows: Int, handleOpenApp: @escaping (AppLinkAppEntity) -> Void) {
        self.appLinks = appLinks
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        
        var seenIDs = Set<String>()
        self.cachedAppLinks = appLinks.filter { appLink in
            guard !seenIDs.contains(appLink.id) else { return false }
            seenIDs.insert(appLink.id)
            return true
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                Spacer()
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: rows), spacing: 10) {
                    ForEach(Array(cachedAppLinks.enumerated()), id: \.element.id) { index, app in
                        AppLinkButton(app: app, action: handleOpenApp)
                    }
                }
                .scrollTargetLayout()
                .frame(
                    minWidth: geometry.frame(in: .global).width,
                    minHeight: geometry.frame(in: .global).height
                )
                
#if os(macOS)
                .captureVerticalScrollWheel()
#endif
                Spacer()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, 4)
        }.frame(height: 80 * CGFloat(rows))
            .animation(.interpolatingSpring, value: cachedAppLinks)
            .onChange(of: appIdsIconsHashed) {
                cachedAppLinks = appLinks
            }
    }
}

struct AppLinkButton: View {
    let app: AppLinkAppEntity
    let action: (AppLinkAppEntity) -> Void
    
    var body: some View {
        Button(action: {
            action(app)
        }) {
            VStack {
                DataImage(from: app.icon, fallback: "questionmark.app")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 60, height: 44)
                    .shadow(radius: 4)
                
                
                Text(app.name)
                    .font(.caption)
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
        .buttonStyle(.plain)
        
    }
}

#if os(macOS)
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
                handleScroll(with: scrollDist, precise: event.hasPreciseScrollingDeltas)
                
                scrollVelocity = scrollDelta
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

        private func handleScroll(with delta: CGFloat, precise: Bool) {
            var scrollDist = delta
            if !precise {
                scrollDist *= 2
            }

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
            if abs(scrollVelocity) < 0.8 {
                decelerationTimer?.invalidate()
                decelerationTimer = nil
                return
            }

            handleScroll(with: scrollVelocity, precise: true)
            scrollVelocity *= 0.95
        }
    }
}

extension View {
    func captureVerticalScrollWheel() -> some View {
        self.modifier(CaptureVerticalScrollWheelModifier())
    }
}
#endif


#Preview {
    AppLinksView(appLinks: getTestingAppLinks().map{$0.toAppEntity()}, rows: 1, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks().map{$0.toAppEntity()}, rows: 2, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
