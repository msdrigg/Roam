import SwiftUI
import Foundation

struct AppListView: View {
    let device: DeviceAppEntity?
    let apps: [AppLinkAppEntity]
    
    @State var appClicks: [String: Int] = [:]
    func appPressCount(_ app: String) -> Int {
        appClicks[app] ?? 0
    }
    
    func incrementAppPressCount(_ app: String) {
        appClicks[app] = (appClicks[app] ?? 0) + 1
    }
    
    var body: some View {
        List {
            ForEach(apps) { app in
                Button(action: {
                    incrementAppPressCount(app.id)
                    Task {
                        try? await launchApp(app: app, device: device)
                    }
                }) {
                    Label {
                        Text(app.name)
                    } icon: {
                        DataImage(from: app.icon, fallback: "questionmark.app")
                            .resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: 32, height: 32)
                            .shadow(radius: 4)
                    }
                    .labelStyle(AppIconLabelStyle())
                }                   
                .sensoryFeedback(.impact, trigger: appPressCount(app.id))

            }
            if apps.isEmpty {
                Text("No apps")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AppIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

