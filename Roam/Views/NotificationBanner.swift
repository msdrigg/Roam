import SwiftUI
import Foundation

/// True while something occupies the remote's bottom banner slot. On iPhone
/// that slot otherwise sits under the pager's floating button bar.
struct BottomBannerVisibleKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

#if os(watchOS)
struct NotificationBanner: View {
    let message: String
    let level: Level
    let onDismiss: (() -> Void)?
    let onClick: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor

    init(message: String, onClick: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil, level: Level = .error) {
        self.message = message
        self.onDismiss = onDismiss
        self.level = level
        self.onClick = onClick
    }

    var body: some View {
        VStack {
            if let onClick {
                Button(action: onClick, label: {
                    Text(message)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .font(.subheadline)
                        .foregroundStyle(
                            colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(backgroundColor)
                        .cornerRadius(8)
                })
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(message)
                            .font(.subheadline)
                        Spacer()
                    }

                    if let onDismiss {
                        Button("Dismiss", systemImage: "x.circle.fill", action: onDismiss)
                            .controlSize(.small)
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(
                    Color.white.opacity(0.8)
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(backgroundColor)
                .cornerRadius(8)
            }
            Spacer()
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .info:
            customAccentColor.opacity(0.3)
        case .warning:
            Color.orange.opacity(0.3)
        case .error:
            Color.red.opacity(0.3)
        }
    }

    enum Level {
        case warning, error, info
    }
}
#else
/// One line of status under the remote, styled like `TimedMuteStatusPill` so
/// stacked banners read as a set.
struct NotificationBanner: View {
    let message: String
    let level: Level
    let systemImage: String?
    let onDismiss: (() -> Void)?
    let onClick: (() -> Void)?

    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor

    init(
        message: String,
        onClick: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        level: Level = .error,
        systemImage: String? = nil
    ) {
        self.message = message
        self.onDismiss = onDismiss
        self.level = level
        self.systemImage = systemImage
        self.onClick = onClick
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onClick {
                Button(action: onClick) {
                    HStack(spacing: 8) {
                        icon
                        messageText
                        Image(systemName: "chevron.forward")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                icon
                messageText
            }

            if let onDismiss {
                BannerDismissButton(action: onDismiss)
            }
        }
        .bannerPill(tint: tint)
        .help(message)
        .preference(key: BottomBannerVisibleKey.self, value: true)
    }

    private var icon: some View {
        Image(systemName: systemImage ?? level.systemImage)
            .foregroundStyle(tint)
    }

    private var messageText: some View {
        Text(message)
            .truncationMode(.tail)
    }

    private var tint: Color {
        switch level {
        case .info:
            customAccentColor
        case .warning:
            Color.orange
        case .error:
            Color.red
        }
    }

    enum Level {
        case warning, error, info

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "exclamationmark.octagon.fill"
            }
        }
    }
}

struct BannerDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(
            String(localized: "Dismiss", comment: "Button that hides a banner under the remote"),
            systemImage: "xmark.circle.fill",
            action: action
        )
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }
}

extension View {
    /// The shared banner shape: a capsule on one line, a rounded card on two.
    func bannerPill(tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return self
            .font(.footnote.weight(.medium))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(tint.opacity(0.18), in: shape)
            .background(.regularMaterial, in: shape)
            .frame(maxWidth: 420)
    }
}
#endif

#if DEBUG
#Preview("Clickable") {
    NotificationBanner(message: String("Message (clickable)"), onDismiss: {})
        .padding()
}

#Preview("Not clickable") {
    NotificationBanner(message: String("Message (not clickable)"))
        .padding()
}

#Preview("Info") {
    NotificationBanner(message: String("Message (not clickable)"), level: .info)
        .padding()
}
#endif
