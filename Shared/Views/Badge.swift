import SwiftUI

struct BadgeLabelStyle: LabelStyle {
    var color: Color = Color.blue
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = 14.0
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
            .foregroundColor(color.isLightColor ? .black : .white)
            .font(.caption2)
    }
}

extension LabelStyle where Self == BadgeLabelStyle {
    static func badge(_ color: Color) -> BadgeLabelStyle {
        BadgeLabelStyle(color: color)
    }
}

extension Color {
    var isLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        let brightness = (red * 299 + green * 587 + blue * 114) / 1000
        return brightness > 0.5
    }
}

#Preview("About") {
    Label("Test Badge!", systemImage: "keyboard")
        .labelStyle(.badge(Color.green))
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(devicePreviewContainer)
}
