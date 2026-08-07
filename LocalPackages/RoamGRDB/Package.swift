// swift-tools-version: 6.0
import PackageDescription

// Wraps GRDB in a dynamically linked product so the app, its widget extension,
// and the watch app share a single copy instead of each statically linking one.
let package = Package(
    name: "RoamGRDB",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "RoamGRDB", type: .dynamic, targets: ["RoamGRDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(name: "RoamGRDB", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
