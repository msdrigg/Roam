import SwiftUI
import Foundation

struct SmallAppView: View {
    let device: DeviceAppEntity?
    let apps: [AppLinkAppEntity]
    
    var appRows: [[AppLinkAppEntity?]] {
        var rows: [[AppLinkAppEntity?]] = []
        let cappedApps = Array(apps.prefix(4))
        
        for i in stride(from: 0, to: cappedApps.count, by: 2) {
            let endIndex = min(i + 2, cappedApps.count)
            let row = Array(cappedApps[i..<endIndex])
            rows.append(row + [nil, nil][..<(2 - row.count)])
        }
        
        return rows
    }
    
    var body: some View {
        Grid {
            ForEach(appRows, id: \.first??.id) { row in
                GridRow {
                    ForEach(row, id: \.self?.id) { app in
                        if let app = app {
                            Button(intent: LaunchAppIntent(app, device: device)) {
                                VStack(spacing: 0) {
                                    DataImage(from: app.icon, fallback: "questionmark.app")
                                        .resizable().aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .frame(width: 60, height: 60)
                                        .shadow(radius: 4)
                                    
                                        Text(" \(app.name) ")
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: 60)
                                            .frame(height: 10)
                                            .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .font(.body.bold())
        .buttonBorderShape(.roundedRectangle)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .tint(Color("AccentColor"))
    }
}
