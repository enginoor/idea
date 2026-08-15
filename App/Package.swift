// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OriginCheckApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OriginCheck", targets: ["OriginCheckApp"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "OriginCheckApp",
            dependencies: [
                .product(name: "OriginCheckEngine", package: "OriginCheckEngine")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
