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
                    Text("Roam")
                        .font(.title)
                        .foregroundStyle(.accent)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("App Version")
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--")")
                        Spacer()
                    }
                    .font(.headline)
                    HStack(spacing: 4) {
                        Spacer()
                        Text("Build Version")
                        Text("\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--")")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer().frame(maxHeight: 10)

                    VStack(alignment: .center, spacing: 5) {
                        Text("Made with ❤️ by Scott Driggers")

                        Link("roam-support@msd3.io", destination: URL(string: "mailto:roam-support@msd3.io")!)
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
