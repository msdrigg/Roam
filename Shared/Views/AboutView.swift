import SwiftUI
import SwiftData
import os

struct Dependency: Identifiable {
    let name: String
    let link: String
    let licenseType: String
    
    var id: String {
        link
    }
}

#if os(watchOS)
let WATCHOS_LICENSES = [
    Dependency(name: "libwebp", link: "https://chromium.googlesource.com/webm/libwebp", licenseType: "BSD-3-Clause"),
    Dependency(name: "libwebp-Xcode", link: "https://github.com/SDWebImage/libwebp-Xcode", licenseType: "BSD-3-Clause")
]
#endif
    

let MAIN_LICENSES: [Dependency] = [
    Dependency(name: "Opus", link: "https://github.com/xiph/opus/tree/master", licenseType: "BSD-3-Clause"),
    Dependency(name: "Swift-Opus", link: "https://github.com/alta/swift-opus", licenseType: "BSD-3-Clause"),
    Dependency(name: "Swift-RTP", link: "https://github.com/alta/swift-rtp", licenseType: "MIT"),
    Dependency(name: "Swift-Async-Algorithms", link: "https://github.com/apple/swift-async-algorithms", licenseType: "Apache-2.0"),
    Dependency(name: "SSDPClient", link: "https://github.com/pierrickrouxel/SSDPClient", licenseType: "MIT"),
    Dependency(name: "XMLCoder", link: "https://github.com/CoreOffice/XMLCoder", licenseType: "MIT"),
    Dependency(name: "AsyncSemaphore", link: "https://github.com/groue/Semaphore", licenseType: "MIT"),
    Dependency(name: "Swift Collections", link: "https://github.com/apple/swift-collections", licenseType: "Apache-2.0")
]

#if os(watchOS)
let LICENSES = MAIN_LICENSES + WATCHOS_LICENSES
#else
let LICENSES = MAIN_LICENSES
#endif

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("App Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--")
                }
            }
            
            Section("Dependencies") {
                ForEach(LICENSES) { license in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(license.name)
                            Spacer()
                            Text(license.licenseType)
                        }
                        Link(license.link, destination: URL(string: license.link)!)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("About")
    }
}


enum AboutDestination{
    case Global
}


#Preview("About") {
    AboutView()
        .previewLayout(.fixed(width: 100.0, height: 300.0))
        .modelContainer(devicePreviewContainer)
}