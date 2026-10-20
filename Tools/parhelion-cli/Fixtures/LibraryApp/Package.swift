// swift-tools-version: 6.0

// An app shaped the way `xtool new` creates one: a single library product
// whose `@main` type is the app. CI runs it with `parhelion run`.

import PackageDescription

let package = Package(
    name: "LibraryApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LibraryApp", targets: ["LibraryApp"])
    ],
    dependencies: [
        .package(name: "parhelion", path: "../../../..")
    ],
    targets: [
        .target(
            name: "LibraryApp",
            dependencies: [
                .product(
                    name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux]))
            ]
        )
    ]
)
