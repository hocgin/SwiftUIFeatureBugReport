// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftUIFeatureBugReport",
    // The source language of the key-based catalogue under Resources/. Every user-facing string is
    // looked up in this package's own bundle (`Bundle.module`, via the `L10n` helper), so the board
    // ships translated without any host-app setup. See README > Localisation.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftUIFeatureBugReport",
            targets: ["SwiftUIFeatureBugReport"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftUIFeatureBugReport",
            resources: [
                // Localizable.strings (+ .stringsdict for plurals) per language. See README > Localisation.
                .process("Resources"),
                // Folded into the host app's privacy report by Xcode. See README > Privacy.
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "SwiftUIFeatureBugReportTests",
            dependencies: ["SwiftUIFeatureBugReport"]
        ),
    ]
)
