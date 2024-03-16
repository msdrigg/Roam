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

#if os(watchOS) || os(tvOS)
let WEBP_LICENSES = [
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
    Dependency(name: "Swift Collections", link: "https://github.com/apple/swift-collections", licenseType: "Apache-2.0"),
    Dependency(name: "Wrapping HStack", link: "https://github.com/ksemianov/WrappingHStack", licenseType: "MIT")
]

#if os(watchOS) || os(tvOS)
let LICENSES = MAIN_LICENSES + WEBP_LICENSES
#else
let LICENSES = MAIN_LICENSES
#endif

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("App Version") {
                    Text(Bundle.main.infoDictionary?["CURRENT_PROJECT_VERSION"] as? String ?? "--")
                }
                .focusable()
            }
            
            Section("Dependencies") {
                licenseIterator
            }
        }
        .navigationTitle("About")
    }
    
    @ViewBuilder
    var licenseIterator: some View {
        ForEach(Array(zip(LICENSES.indices, LICENSES)), id: \.0) { idx, license in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if idx % 8 == 7 {
                        Text(license.name)
                            .foregroundStyle(.primary, .primary)
                        #if os(tvOS)
                            .focusable()
                        #endif
                    } else {
                        Text(license.name)
                            .foregroundStyle(.primary, .primary)
                    }
                    
                    Spacer()
                    
                    #if os(tvOS)
                    Text(license.link)
                        .font(.body)
                        .foregroundStyle(.secondary, .secondary)
                        .lineLimit(1)
                    #else
                    Link(license.link, destination: URL(string: license.link)!)
                        .font(.body)
                        .foregroundStyle(.secondary, .secondary)
                        .lineLimit(1)
                    #endif
                }
                Text(license.licenseType)
                    .font(.body)
                    .foregroundStyle(.secondary, .secondary)
            }
        }
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
