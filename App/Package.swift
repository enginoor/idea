// swift-tools-version: 6.0

import PackageDescription

// The engine is referenced as a path dependency (".."). SwiftPM identifies
// path dependencies by the checkout directory name, not by the Package.swift
// name field, so this package must be built from a checkout of enginoor/idea
// whose folder is named "idea". GitHub Actions checks out into the repo name,
// so CI matches. Renaming the folder breaks the reference.
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
                .product(name: "OriginCheckEngine", package: "idea")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
