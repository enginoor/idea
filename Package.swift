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
        .target(
            name: "OriginCheckEngine",
            resources: [
                // Detection data ships inside the app bundle (english
                // frequency dictionary, AI phrase database, sample
                // passages), so text detection is fully offline and needs
                // no installed tools or network access.
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "OriginCheckEngineTests",
            dependencies: ["OriginCheckEngine"]
        )
    ],
    swiftLanguageModes: [.v6]
)
