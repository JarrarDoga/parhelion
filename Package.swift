// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "ParhelionUI", targets: ["ParhelionUI"]),
    .library(name: "ParhelionRender", targets: ["ParhelionRender"]),
    .library(name: "ParhelionPreview", targets: ["ParhelionPreview"]),
]

// `parhelion run` and `parhelion mcp` set PARHELION_OPTIMIZE_FRAMEWORK=1 so that a
// debug build compiles Parhelion's own modules with optimization while the app stays
// at -Onone: rendering is about ten times faster and app edits rebuild as fast as
// before. SwiftPM rejects unsafe flags in a dependency pinned to a version, even
// behind a condition, so the flag exists only while the variable is set, and the
// tool sets it only for root, path, branch, and revision dependencies. Ordinary
// builds never see it.
let frameworkSettings: [SwiftSetting] =
    Context.environment["PARHELION_OPTIMIZE_FRAMEWORK"] == "1"
    ? [.unsafeFlags(["-O"], .when(platforms: [.linux], configuration: .debug))] : []

var targets: [Target] = [
    // ParhelionUI must not declare SwiftPM resources: xtool packages the resource
    // bundles of every target in an app's graph, including targets that are
    // excluded on iOS, and fails when they were not built. Font metrics are
    // embedded as generated source instead; see Scripts/embed-font.sh.
    .target(name: "ParhelionRender", swiftSettings: frameworkSettings),
    .target(name: "ParhelionPreview", swiftSettings: frameworkSettings),
    .target(
        name: "ParhelionUI",
        dependencies: ["ParhelionRender", "ParhelionPreview"],
        swiftSettings: frameworkSettings
    ),
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
    .target(name: "SwiftUI", dependencies: ["ParhelionUI"], swiftSettings: frameworkSettings),
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
    .executableTarget(
        name: "Scrolling",
        dependencies: ["SwiftUI"],
        path: "Examples/Scrolling"
    ),
    .executableTarget(
        name: "Form",
        dependencies: ["SwiftUI"],
        path: "Examples/Form"
    ),
    .executableTarget(
        name: "Tasks",
        dependencies: ["SwiftUI"],
        path: "Examples/Tasks"
    ),
    .executableTarget(
        name: "Tabs",
        dependencies: ["SwiftUI"],
        path: "Examples/Tabs"
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
