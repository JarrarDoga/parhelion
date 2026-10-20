// swift-tools-version: 6.0

import PackageDescription

// The `parhelion` command-line tool, including the preview window host.
//
// It lives in its own package because it depends on SDL3, a system library.
// Parhelion's root package must stay free of system libraries so that apps
// can depend on it without installing anything; see
// docs/adr/0004-pure-swift-renderer.md.
let package = Package(
    name: "parhelion-cli",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "parhelion", targets: ["parhelion"])
    ],
    dependencies: [
        // The name is explicit so the build works whatever the clone directory is called.
        .package(name: "parhelion", path: "../.."),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSDL3",
            pkgConfig: "sdl3",
            providers: [
                .apt(["libsdl3-dev"]),
                .yum(["SDL3-devel"]),
                .brew(["sdl3"]),
            ]
        ),
        // Package inspection, runner generation, file watching, and builds:
        // everything that does not need a window, so it can be tested.
        .target(name: "ParhelionTooling"),
        .testTarget(name: "ParhelionToolingTests", dependencies: ["ParhelionTooling"]),
        .executableTarget(
            name: "parhelion",
            dependencies: [
                "CSDL3",
                "ParhelionTooling",
                .product(name: "ParhelionPreview", package: "parhelion"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
