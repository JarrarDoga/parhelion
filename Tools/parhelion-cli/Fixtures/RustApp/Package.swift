// swift-tools-version: 6.0

// An app that links a Rust library through UniFFI. `parhelion.json` tells
// `parhelion run` how to build the library before Swift and what to watch.
// CI runs it with `parhelion run`.

import PackageDescription

let package = Package(
    name: "RustApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RustApp", targets: ["RustApp"])
    ],
    dependencies: [
        .package(name: "parhelion", path: "../../../..")
    ],
    targets: [
        // The header that UniFFI generates for the Rust library.
        .target(
            name: "fixture_backendFFI",
            linkerSettings: [.linkedLibrary("fixture_backend")]
        ),
        .target(
            name: "RustApp",
            dependencies: [
                "fixture_backendFFI",
                .product(
                    name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux])),
            ]
        ),
    ],
    // UniFFI's generated Swift is not written for Swift 6 checking.
    swiftLanguageModes: [.v5]
)
