// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OriginCheckEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OriginCheckEngine", targets: ["OriginCheckEngine"])
    ],
    targets: [
        .target(name: "OriginCheckEngine"),
        .testTarget(
            name: "OriginCheckEngineTests",
            dependencies: ["OriginCheckEngine"]
        )
    ],
    swiftLanguageModes: [.v6]
)
