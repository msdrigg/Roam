import SwiftUI

struct BadgeLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = 10.0
    var color: Color = .blue
    /// When true, the badge shows only its icon (the title is kept on the
    /// `Label` for accessibility but not drawn) to save horizontal space.
    var iconOnly: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: iconOnly ? 0 : iconWidth) {
            configuration.icon
                .frame(width: iconWidth)
            if !iconOnly {
                configuration.title
            }
        }
        #if os(visionOS)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        #else
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        #endif
        .truncationMode(.tail)
        .lineLimit(1)
        .background(color.opacity(0.6))
        .clipShape(Capsule())
        .font(.caption2)
    }
}

extension LabelStyle where Self == BadgeLabelStyle {
    static func badge(_ color: Color) -> BadgeLabelStyle {
        BadgeLabelStyle(color: color)
    }

    static func badge(_ color: Color, iconOnly: Bool) -> BadgeLabelStyle {
        BadgeLabelStyle(color: color, iconOnly: iconOnly)
    }
}

#if DEBUG
#Preview(
    "About",
    traits: .fixedLayout(width: 200.0, height: 300.0)
) {
    Label(String("Test Badge!"), systemImage: "keyboard")
        .padding()
        .labelStyle(.badge(Color.green))
}
#endif
