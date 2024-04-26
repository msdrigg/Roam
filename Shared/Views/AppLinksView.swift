import SwiftData
import SwiftUI

#if os(tvOS) || os(visionOS)
    let GRID_WIDTH: CGFloat = 100
    let GRID_SPACING: CGFloat = 20
    let GRID_HEIGHT: CGFloat = 130
#elseif os(visionOS)
    let GRID_WIDTH: CGFloat = 80
    let GRID_SPACING: CGFloat = 20
    let GRID_HEIGHT: CGFloat = 130
#else
    let GRID_WIDTH: CGFloat = 60
    let GRID_SPACING: CGFloat = 10
    let GRID_HEIGHT: CGFloat = 80
#endif

struct AppLinksView: View {
    var handleOpenApp: (AppLinkAppEntity) -> Void
    @Query private var appLinks: [AppLink]
    let rows: Int
    @State var cachedAppLinks: [AppLink]

    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String> = Set()
        for appLink in appLinks {
            appLinkPairs.insert("\(appLink.id);\(appLink.icon != nil)")
        }

        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }

    @Namespace var linkAnimation

    init(deviceId: String?, rows: Int, handleOpenApp: @escaping (AppLinkAppEntity) -> Void) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows

        _appLinks = Query(
            filter: #Predicate {
                $0.deviceUid == deviceId
            },
            sort: \.lastSelected,
            order: .reverse
        )
        cachedAppLinks = []
    }

    var body: some View {
        GeometryReader { geometry in
            if !cachedAppLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Spacer()
                    LazyHGrid(rows: Array(repeating:
                        GridItem(.fixed(CGFloat(GRID_WIDTH))), count: rows), spacing: GRID_SPACING)
                    {
                        ForEach(Array(cachedAppLinks.enumerated()), id: \.element.id) { _, app in
                            AppLinkButton(app: app, action: handleOpenApp)
                        }
                    }
                    .scrollTargetLayout()
                    .frame(
                        minWidth: geometry.frame(in: .global).width,
                        minHeight: geometry.frame(in: .global).height
                    )

                    #if os(macOS)
                    .captureVerticalScrollWheel()
                    #endif
                    Spacer()
                }
                .scrollTargetBehavior(.viewAligned)
                .safeAreaPadding(.horizontal, 4)
            }
        }
        .frame(height: GRID_HEIGHT * CGFloat(rows))
        .onAppear {
            cachedAppLinks = appLinks
        }
        .onChange(of: appIdsIconsHashed) {
            withAnimation(.interpolatingSpring) {
                cachedAppLinks = appLinks
            }
        }
    }
}

struct AppLinkButton: View {
    let app: AppLink
    let action: (AppLinkAppEntity) -> Void

    var body: some View {
        Button(action: {
            action(app.toAppEntity())
        }) {
            VStack {
                DataImage(from: app.icon, fallback: "questionmark.app")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: GRID_WIDTH)
                    .shadow(radius: 4)

                Text(app.name)
                #if os(tvOS) || os(visionOS)
                    .font(.body)
                #else
                    .font(.caption)
                #endif
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .frame(maxWidth: GRID_WIDTH)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppLinksView(deviceId: nil, rows: 1, handleOpenApp: { _ in })
        .modelContainer(previewContainer)
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}

#Preview {
    AppLinksView(deviceId: nil, rows: 2, handleOpenApp: { _ in })
        .modelContainer(previewContainer)
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
