// swift-tools-version: 6.0

// An app that publishes now-playing info and handles remote commands. It is
// the fixture for the MPRIS check: `playerctl metadata` shows its title and
// `playerctl pause` pauses it. See docs/adr/0017-mediaplayer-mpris.md.

import PackageDescription

let package = Package(
    name: "MediaApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MediaApp", targets: ["MediaApp"])
    ],
    dependencies: [
        .package(name: "parhelion", path: "../../../..")
    ],
    targets: [
        .target(
            name: "MediaApp",
            dependencies: [
                .product(
                    name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux])),
                .product(
                    name: "MediaPlayer", package: "parhelion", condition: .when(platforms: [.linux])
                ),
            ]
        )
    ]
)
