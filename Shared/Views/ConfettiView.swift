import SwiftUI

@MainActor @Observable
final class CelebrationController {
    private(set) var burst: Int = 0

    func celebrate() {
        burst += 1
    }
}

/// A one-shot rain of confetti, in the spirit of the Messages screen effect.
///
/// Position, spin and fade are pure functions of elapsed time rather than
/// integrated per frame, so a dropped frame cannot desync the animation.
struct ConfettiOverlay: View {
    let burst: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pieces: [ConfettiPiece] = []
    @State private var startDate: Date?

    private static let lifetime: TimeInterval = 4.0

    var body: some View {
        // One long-lived timeline, parked via `paused:` between bursts.
        // Swapping it in and out on `startDate` never starts ticking, so the
        // burst renders as nothing.
        TimelineView(.animation(paused: startDate == nil)) { timeline in
            Canvas { context, size in
                guard let startDate else { return }
                let elapsed = timeline.date.timeIntervalSince(startDate)
                for piece in pieces {
                    draw(piece, elapsed: elapsed, in: context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onChange(of: burst) { _, newValue in
            // Reduce Motion means no full-screen motion, and a paid-feature
            // unlock isn't worth making someone motion-sick over. The unlock
            // itself has already happened either way.
            guard newValue > 0, !reduceMotion else { return }
            pieces = ConfettiPiece.burst()
            startDate = .now
        }
        .task(id: startDate) {
            guard startDate != nil else { return }
            try? await Task.sleep(for: .seconds(Self.lifetime))
            guard !Task.isCancelled else { return }
            pieces = []
            startDate = nil
        }
    }

    private func draw(_ piece: ConfettiPiece, elapsed: TimeInterval, in context: GraphicsContext, size: CGSize) {
        let time = elapsed - piece.delay
        guard time >= 0 else { return }

        let progress = time / piece.fallDuration
        guard progress <= 1 else { return }

        let travel = size.height + piece.size.height * 2
        let y = -piece.size.height + progress * travel
        let x = piece.xFraction * size.width + sin(time * piece.swayFrequency + piece.swayPhase) * piece.swayAmplitude

        let fade = progress > 0.75 ? (1 - progress) / 0.25 : 1

        var pieceContext = context
        pieceContext.translateBy(x: x, y: y)
        pieceContext.rotate(by: .radians(piece.tilt + time * piece.spin))
        // Squashing width on a faster cycle reads as a 3D tumble. Floored so a
        // piece never collapses to an invisible sliver when edge-on.
        pieceContext.scaleBy(x: max(0.2, abs(cos(time * piece.spin * 1.3))), y: 1)

        let rect = CGRect(
            x: -piece.size.width / 2,
            y: -piece.size.height / 2,
            width: piece.size.width,
            height: piece.size.height
        )
        let path = piece.isCircle
            ? Path(ellipseIn: rect)
            : Path(roundedRect: rect, cornerRadius: 1.5)

        pieceContext.fill(path, with: .color(piece.color.opacity(fade)))
    }
}

private struct ConfettiPiece: Identifiable {
    let id: Int
    let xFraction: Double
    let delay: TimeInterval
    let fallDuration: TimeInterval
    let swayAmplitude: Double
    let swayFrequency: Double
    let swayPhase: Double
    let spin: Double
    let tilt: Double
    let size: CGSize
    let color: Color
    let isCircle: Bool

    /// Not the app accent color: confetti matching the tint reads as chrome.
    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.29, blue: 0.42),
        Color(red: 0.99, green: 0.60, blue: 0.21),
        Color(red: 1.00, green: 0.83, blue: 0.25),
        Color(red: 0.30, green: 0.80, blue: 0.47),
        Color(red: 0.24, green: 0.62, blue: 0.97),
        Color(red: 0.65, green: 0.40, blue: 0.95),
    ]

#if os(watchOS)
    private static let count = 40
#else
    private static let count = 90
#endif

    static func burst() -> [ConfettiPiece] {
        (0 ..< count).map { index in
            let width = Double.random(in: 5 ... 10)
            return ConfettiPiece(
                id: index,
                xFraction: Double.random(in: -0.02 ... 1.02),
                delay: Double.random(in: 0 ... 0.9),
                fallDuration: Double.random(in: 1.9 ... 3.0),
                swayAmplitude: Double.random(in: 8 ... 32),
                swayFrequency: Double.random(in: 1.4 ... 3.2),
                swayPhase: Double.random(in: 0 ... (2 * .pi)),
                spin: Double.random(in: 3 ... 9) * (Bool.random() ? 1 : -1),
                tilt: Double.random(in: 0 ... (2 * .pi)),
                size: CGSize(width: width, height: width * Double.random(in: 1.2 ... 2.0)),
                color: palette.randomElement() ?? .pink,
                isCircle: Int.random(in: 0 ..< 5) == 0
            )
        }
    }
}

extension View {
    func confettiOverlay(burst: Int) -> some View {
        overlay(ConfettiOverlay(burst: burst))
    }
}

#if DEBUG
#Preview("Confetti") {
    struct ConfettiPreview: View {
        @State private var burst = 1

        var body: some View {
            ZStack {
                Color.gray.opacity(0.15)
                Button("Celebrate", systemImage: "party.popper.fill") {
                    burst += 1
                }
                .buttonStyle(.glassIfSupported(isProminent: true))
            }
            .confettiOverlay(burst: burst)
        }
    }

    return ConfettiPreview()
}
#endif
