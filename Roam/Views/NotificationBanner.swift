import SwiftUI

struct NotificationBanner: View {
    let message: String
    let level: Level
    let onClick: (() -> Void)?
    let onDismiss: (() -> Void)?
    let dismissable: Bool = false
    
    init(message: String, onClick: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil, level: Level = .error) {
        self.message = message
        self.onClick = onClick
        self.level = level
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(textColor)

            if dismissable {
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(textColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(5)
        .onTapGesture {
            onClick?()
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .info:
            return Color.blue.opacity(0.3)
        case .warning:
            return Color.orange.opacity(0.3)
        case .error:
            return Color.red.opacity(0.3)
        }
    }

    private var textColor: Color {
        Color.primary.opacity(0.7)
    }

    enum Level {
        case warning, error, info
    }
}




#Preview("Clickable") {
    NotificationBanner(message: "Message (clickable)", onClick: {})
        .padding()
}

#Preview("Not clickable") {
    NotificationBanner(message: "Message (not clickable)")
        .padding()
}

#Preview("Info") {
    NotificationBanner(message: "Message (not clickable)", level: .info)
        .padding()
}
