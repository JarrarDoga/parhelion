// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "ParhelionUI", targets: ["ParhelionUI"])
]

var targets: [Target] = [
    .target(name: "ParhelionUI"),
    .testTarget(name: "ParhelionUITests", dependencies: ["ParhelionUI"]),
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
]
#endif

let package = Package(
    name: "Parhelion",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
