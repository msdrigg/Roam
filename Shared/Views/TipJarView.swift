import StoreKit
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// The tip jar is not offered on watchOS: the watch app is a companion surface
// with no room for a store, and `formStyle(.grouped)` isn't available there.
#if !os(watchOS)

/// The alternate app icons unlocked by tipping.
///
/// `assetName` must match the `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
/// entries; `nil` means the default icon.
enum AppIconOption: String, CaseIterable, Identifiable {
    case standard
    case pride = "AppIconPride"
    case smiley = "AppIconSmiley"
    case retro = "AppIconRetro"
    case midnight = "AppIconMidnight"

    var id: String { rawValue }

    /// `UIApplication` wants `nil` rather than a name for the primary icon.
    var alternateIconName: String? {
        self == .standard ? nil : rawValue
    }

    /// The asset catalog image used for the preview swatch. These are separate
    /// image sets from the app-icon sets, because icon assets themselves are
    /// not addressable as `Image(...)` at runtime.
    var previewAssetName: String {
        self == .standard ? "AppIconPreview" : "\(rawValue)Preview"
    }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Default", comment: "Name of the default app icon")
        case .pride: String(localized: "Pride", comment: "Name of the rainbow app icon")
        case .smiley: String(localized: "Smiley", comment: "Name of the smiley-face app icon")
        case .retro: String(localized: "Retro", comment: "Name of the retro TV test-pattern app icon")
        case .midnight: String(localized: "Midnight", comment: "Name of the dark monochrome app icon")
        }
    }
}

struct TipJarView: View {
    @State private var store = TipStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Roam is free, ad-free, and open source.",
                        comment: "Headline at the top of the tip jar"
                    )
                    .font(.headline)

                    Text(
                        // swiftlint:disable:next line_length
                        "If it's been useful to you, you can leave a tip. Any tip unlocks custom accent colors and the alternate app icons — but every tier unlocks the same things, so pick whatever feels right.",
                        comment: "Explanation of what tipping does"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(TipTier.allCases) { tier in
                    TipTierRow(tier: tier, store: store)
                }
            } header: {
                Text("Leave a tip", comment: "Section header above the list of tip tiers")
            } footer: {
                if store.hasTipped {
                    Label(
                        String(
                            localized: "Thank you! Your extras are unlocked.",
                            comment: "Confirmation shown once the user has tipped"
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    HStack {
                        Text("Restore Purchases", comment: "Button to restore previous in-app purchases")
                        Spacer()
                        if store.isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRestoring)
            } footer: {
                Text(
                    "Already tipped on another device? Restore to unlock the extras here.",
                    comment: "Explanation of the restore purchases button"
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Tip Jar", comment: "Navigation title of the tip jar page"))
        .task {
            await store.loadProducts()
        }
        .alertingError(message: "Purchase Failed", error: $store.purchaseError)
        .customAccentColorTint()
    }
}

private struct TipTierRow: View {
    let tier: TipTier
    let store: TipStore

    private var product: Product? {
        store.product(for: tier)
    }

    private var isPurchased: Bool {
        store.purchasedProductIDs.contains(tier.rawValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(tier.emoji)
                .font(.title2)

            Text(tier.displayName)

            Spacer()

            if isPurchased {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let product {
                Button(product.displayPrice) {
                    Task { await store.purchase(product) }
                }
                .buttonStyle(.glassIfSupported(isProminent: true))
            } else if inScreenshotTestingContext() {
                // Screenshot runs have to be deterministic. The redacted pill
                // below is right for real users (it signals "still loading"),
                // but it makes the App Store review screenshot useless — the
                // reviewer needs to see the actual purchase affordance. Same
                // reasoning as DeviceListItem forcing its status dot green
                // under screenshot testing. The amounts match the App Store
                // Connect prices exactly; nothing is purchasable here.
                Button(tier.placeholderPrice) {}
                    .buttonStyle(.glassIfSupported(isProminent: true))
            } else {
                // Products still loading (or unavailable, e.g. no network).
                Text(tier.placeholderPrice)
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

#if os(iOS)
    /// Alternate app icons are an iOS/iPadOS affordance — `setAlternateIconName`
    /// has no macOS, watchOS or visionOS equivalent.
    struct AppIconPickerView: View {
        @State private var store = TipStore.shared
        @AppStorage(UserDefaultKeys.alternateAppIcon) private var selectedIcon: String = AppIconOption.standard
            .rawValue
        @State private var iconError: Error?

        private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

        var body: some View {
            Form {
                Section {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppIconOption.allCases) { option in
                            Button {
                                select(option)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(option.previewAssetName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(
                                                    selectedIcon == option.rawValue ? Color.accentColor : .clear,
                                                    lineWidth: 3
                                                )
                                        }
                                    Text(option.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text(
                        "Choose the icon shown on your Home Screen.",
                        comment: "Explanation under the alternate app icon picker"
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "App Icon", comment: "Navigation title of the app icon picker"))
            .alertingError(message: "Couldn't Change Icon", error: $iconError)
            .customAccentColorTint()
        }

        private func select(_ option: AppIconOption) {
            guard UIApplication.shared.supportsAlternateIcons else { return }

            UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
                Task { @MainActor in
                    if let error {
                        Log.userInteraction.error("Failed setting alternate icon \(error, privacy: .public)")
                        iconError = error
                    } else {
                        selectedIcon = option.rawValue
                        Log.userInteraction.notice("Alternate icon set to \(option.rawValue, privacy: .public)")
                    }
                }
            }
        }
    }
#endif

#endif
