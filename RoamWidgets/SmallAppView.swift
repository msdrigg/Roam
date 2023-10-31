import SwiftUI
import Foundation

struct SmallAppView: View {
    let device: DeviceAppEntity?
    let apps: [AppLinkAppEntity]
    
    var appRows: [[AppLinkAppEntity?]] {
        if device == nil && apps.isEmpty {
            return [[nil, nil], [nil, nil]]
        }
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
            ForEach(appRows.indices, id: \.self) { index in
                let row = appRows[index]
                GridRow {
                    ForEach(row.indices, id: \.self) { rowIndex in
                        if let app = row[rowIndex] {
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
                        } else if device != nil {
                            Spacer()
                        } else {
                            VStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 60, height: 60)
                                    .shadow(radius: 4)

                                Text("App")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 60)
                                    .frame(height: 10)
                                    .foregroundStyle(.secondary)
                            }
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

#Preview {
    SmallAppView(device: nil, apps: [])
        .frame(width: 200, height: 200)
}
