import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLink]
    var handleOpenApp: (AppLink) -> Void
    
    init(appLinks: [AppLink], handleOpenApp: @escaping (AppLink) -> Void) {
        self.appLinks = appLinks
        self.handleOpenApp = handleOpenApp
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Spacer()
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
                    Spacer()
                }
                .frame( 
                    minWidth: geometry.frame(in: .global).width,
                    minHeight: geometry.frame(in: .global).height
                )
            }
        }.frame(minHeight: 80)
    }
}

#Preview {
    AppLinksView(appLinks: getTestingAppLinks(), handleOpenApp: {_ in })
        .previewLayout(.fixed(width: 100.0, height: 300.0))
}
