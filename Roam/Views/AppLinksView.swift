import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLinkAppEntity]
    var handleOpenApp: (AppLinkAppEntity) -> Void
    let rows: Int
    
    @Namespace var linkAnimation
    
    init(appLinks: [AppLinkAppEntity], rows: Int, handleOpenApp: @escaping (AppLinkAppEntity) -> Void) {
        self.appLinks = appLinks
        self.handleOpenApp = handleOpenApp
        self.rows = rows
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                Spacer()
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: rows), spacing: 10) {
                    ForEach(Array(appLinks.enumerated()), id: \.element.id) { index, app in
                        AppLinkButton(app: app, action: handleOpenApp)
                            .matchedGeometryEffect(id: app.id, in: linkAnimation)
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
            .animation(.interpolatingSpring, value: appLinks)
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
