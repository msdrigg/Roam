#if os(macOS)
import Cocoa

class RoamWindowDelegate: NSObject, NSWindowDelegate {
    var targetFrame: NSRect = .zero
    var animationTimer: Timer?

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        targetFrame = NSRect(origin: sender.frame.origin, size: frameSize)
        startSmoothResizeAnimation(for: sender)
        return sender.frame.size
    }

    private func startSmoothResizeAnimation(for window: NSWindow) {
        self.resizeTick(for: window)
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.resizeTick(for: window)
        }
    }
    
    private func resizeTick(for window: NSWindow) {
        let strongSelf = self
        var currentFrame = window.frame
        let deltaX = (strongSelf.targetFrame.size.width - currentFrame.size.width) / 4
        let deltaY = (strongSelf.targetFrame.size.height - currentFrame.size.height) / 4

        if abs(deltaX) < 1 && abs(deltaY) < 1 {
            strongSelf.animationTimer?.invalidate()
            currentFrame.size = strongSelf.targetFrame.size
        } else {
            currentFrame.size.width += deltaX
            currentFrame.size.height += deltaY
        }

        window.setFrame(currentFrame, display: true, animate: false)
    }
}
#endif
