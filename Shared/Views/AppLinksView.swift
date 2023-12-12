import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLinkAppEntity]
    var handleOpenApp: (AppLinkAppEntity) -> Void
    let rows: Int
    @State var cachedAppLinks: [AppLinkAppEntity]
    
    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String>  = Set()
        self.appLinks.forEach {
            appLinkPairs.insert("\($0.id);\($0.icon != nil)")
        }
        
        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }
    
    
    
    @Namespace var linkAnimation
    
    init(appLinks: [AppLinkAppEntity], rows: Int, handleOpenApp: @escaping (AppLinkAppEntity) -> Void) {
        self.appLinks = appLinks
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        
        var seenIDs = Set<String>()
        self.cachedAppLinks = appLinks.filter { appLink in
            guard !seenIDs.contains(appLink.id) else { return false }
            seenIDs.insert(appLink.id)
            return true
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                Spacer()
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: rows), spacing: 10) {
                    ForEach(Array(cachedAppLinks.enumerated()), id: \.element.id) { index, app in
                        AppLinkButton(app: app, action: handleOpenApp)
                    }
                }
                .scrollTargetLayout()
                .frame(
                    minWidth: geometry.frame(in: .global).width,
                    minHeight: geometry.frame(in: .global).height
                )
                Spacer()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, 4)
        }.frame(height: 80 * CGFloat(rows))
            .animation(.interpolatingSpring, value: cachedAppLinks)
            .onChange(of: appIdsIconsHashed) {
                cachedAppLinks = appLinks
            }
    }
}

struct AppLinkButton: View {
    let app: AppLinkAppEntity
    let action: (AppLinkAppEntity) -> Void
    
    var body: some View {
        Button(action: {
            action(app)
        }) {
            VStack {
                DataImage(from: app.icon, fallback: "questionmark.app")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 60, height: 44)
                    .shadow(radius: 4)
                
                
                Text(app.name)
                    .font(.caption)
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
        .buttonStyle(.plain)
        
    }
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks().map{$0.toAppEntity()}, rows: 1, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks().map{$0.toAppEntity()}, rows: 2, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
