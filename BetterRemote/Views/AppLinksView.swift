import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLink]
    var handleOpenApp: (AppLink) -> Void
    let rows: Int
    
    init(appLinks: [AppLink], rows: Int, handleOpenApp: @escaping (AppLink) -> Void) {
        self.appLinks = appLinks
        self.handleOpenApp = handleOpenApp
        self.rows = rows
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                Spacer()
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: rows), spacing: 20) {
                    ForEach(appLinks) { app in
                        Button(action: {
                            handleOpenApp(app)
                        }) {
                            VStack {
                                DataImage(from: app.icon, fallback: "questionmark.app")
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .frame(width: 50, height: 40)
                                    .shadow(radius: 4)
                                

                                Text(app.name)
                                    .font(.caption)
                                    .truncationMode(.tail)
                                    .lineLimit(1)
                                    .frame(maxWidth: 50)
                            }
                        }.buttonStyle(.plain)
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
    }
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks(), rows: 1, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks(), rows: 2, handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
