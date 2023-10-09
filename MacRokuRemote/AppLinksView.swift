//
//  AppLinks.swift
//  MacRokuRemote
//
//  Created by Scott Driggers on 10/8/23.
//

import SwiftUI

struct AppLinksView: View {
    var appLinks: [AppLink]
    
    init(appLinks: [AppLink]) {
        self.appLinks = appLinks
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Spacer()
                ForEach(appLinks) { app in
                    Button(action: {}) {
                        CachedAsyncImage(url: URL(string: app.link ?? "https://logo.clearbit.com/\(app.website)")) { image in
                            image.resizable()
                        } placeholder: {
                            HStack {
                                ProgressView() {
                                    Text(app.name).controlSize(.small)
                                }.progressViewStyle(.linear)
                            }
                        }.aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: 50, height: 40)
                        .shadow(radius: 4)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }
}
