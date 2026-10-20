// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "ParhelionUI", targets: ["ParhelionUI"]),
    .library(name: "ParhelionRender", targets: ["ParhelionRender"]),
    .library(name: "ParhelionPreview", targets: ["ParhelionPreview"]),
]

var targets: [Target] = [
    // ParhelionUI must not declare SwiftPM resources: xtool packages the resource
    // bundles of every target in an app's graph, including targets that are
    // excluded on iOS, and fails when they were not built. Font metrics are
    // embedded as generated source instead; see Scripts/embed-font.sh.
    .target(name: "ParhelionRender"),
    .target(name: "ParhelionPreview"),
    .target(name: "ParhelionUI", dependencies: ["ParhelionRender", "ParhelionPreview"]),
    .testTarget(name: "ParhelionRenderTests", dependencies: ["ParhelionRender"]),
    .testTarget(name: "ParhelionPreviewTests", dependencies: ["ParhelionPreview"]),
    .testTarget(
        name: "ParhelionUITests",
        dependencies: ["ParhelionUI", "ParhelionRender", "ParhelionPreview"]
    ),
]

// Apple's SwiftUI does not exist on Linux, so Parhelion ships a module with that
// name there. App code keeps `import SwiftUI` and builds unchanged. On Apple
// platforms the shim is omitted so it never shadows the real framework.
// See docs/adr/0001-swiftui-module-shim.md.
#if os(Linux)
products.append(.library(name: "SwiftUI", targets: ["SwiftUI"]))
targets += [
    .target(name: "SwiftUI", dependencies: ["ParhelionUI"]),
    .testTarget(name: "SourceCompatibilityTests", dependencies: ["SwiftUI"]),
    .executableTarget(
        name: "HelloParhelion",
        dependencies: ["SwiftUI"],
        path: "Examples/HelloParhelion"
    ),
    .executableTarget(
        name: "Counter",
        dependencies: ["SwiftUI"],
        path: "Examples/Counter"
    ),
]
#endif

let package = Package(
    name: "Parhelion",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
