#!/bin/sh
# Checks that an app depending on Parhelion still builds for iOS with xtool.
#
# Usage: Scripts/check-ios-build.sh
#
# Requires xtool with the iOS SDK installed (`xtool setup`). CI cannot run
# this check, because the SDK comes from Xcode. Run it before opening a pull
# request that changes Package.swift; see docs/adr/0003-no-swiftpm-resources.md.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/CheckApp"
cat > "$work/Package.swift" <<MANIFEST
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CheckApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CheckApp", targets: ["CheckApp"])],
    // The name is explicit so the check works whatever the clone directory is called.
    dependencies: [.package(name: "parhelion", path: "$repo")],
    targets: [
        .target(
            name: "CheckApp",
            dependencies: [
                .product(name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux]))
            ]
        )
    ]
)
MANIFEST
printf 'version: 1\nbundleID: dev.parhelion.CheckApp\n' > "$work/xtool.yml"
cat > "$work/Sources/CheckApp/CheckApp.swift" <<'SWIFT'
import SwiftUI

@main
struct CheckApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Hello")
                Button("Tap") {}
            }
            .padding()
        }
    }
}
SWIFT

cd "$work"
echo "Building for Linux..."
swift build >/dev/null
echo "Building for iOS..."
xtool dev build >/dev/null
binary="$work/xtool/CheckApp.app/CheckApp"
if strings "$binary" | grep -qi parhelion; then
    echo "error: the iOS binary contains Parhelion symbols" >&2
    exit 1
fi
strings "$binary" | grep -q 'SwiftUI.framework' || {
    echo "error: the iOS binary does not link SwiftUI.framework" >&2
    exit 1
}
echo "OK: the app builds for Linux with Parhelion and for iOS with Apple's SwiftUI."
