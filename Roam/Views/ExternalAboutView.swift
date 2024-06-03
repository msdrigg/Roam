#if os(macOS)
    import SwiftUI

    struct ExternalAboutView: View {
        var body: some View {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 180)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 40)

                Divider()

                VStack(alignment: .center, spacing: 10) {
                    Spacer()
                    Text("Roam", comment: "App name")
                        .font(.title)
                        .foregroundStyle(.accent)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("App Version", comment: "Version label in About page for the app")
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--")", comment: "Translate directly as \"%@\"")
                        Spacer()
                    }
                    .font(.headline)
                    HStack(spacing: 4) {
                        Spacer()
                        Text("Build Version", comment: "Version label in About page for the app")
                        Text("\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--")")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer().frame(maxHeight: 10)

                    VStack(alignment: .center, spacing: 5) {
                        Text("Made with ❤️ by Scott Driggers", comment: "Text description within the About View for the app")

                        Link(String(localized: "roam-support@msd3.io", comment: "Support email (not localizable)"), destination: URL(string: "mailto:roam-support@msd3.io")!)
                    }
                    .font(.footnote)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)

                Spacer()
            }
            .frame(width: 600, height: 300)
        }
    }

    #Preview {
        ExternalAboutView()
    }
#endif
