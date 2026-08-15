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
        .package(path: ".."),
        // Automatic updates. Sparkle's EdDSA update signing is separate from
        // Apple code signing, so it works for an ad-hoc signed app. The
        // framework is a prebuilt binary artifact; Scripts/package-app.sh
        // embeds it into Contents/Frameworks, and the rpath below lets dyld
        // find it inside the packaged app (SwiftPM only links it, it does not
        // embed it into the .app bundle).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "OriginCheckApp",
            dependencies: [
                .product(name: "OriginCheckEngine", package: "idea"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                // SwiftPM adds no embed step for binary frameworks (Xcode's
                // "Embed & Sign" phase does that in Xcode projects). Without
                // this rpath, dyld cannot resolve @rpath/Sparkle.framework
                // once package-app.sh copies it into Contents/Frameworks.
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
