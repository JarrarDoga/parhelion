#!/bin/sh
# Checks that an app depending on Parhelion still builds for iOS with xtool.
# The app also compiles the Library example's sources and a file that uses the
# data-flow API (@Observable, @Bindable, bindings into collections, lifecycle
# modifiers, and environment values), so that the same sources are known to
# build against Parhelion on Linux and against Apple's SwiftUI.
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
# The example's own @main would collide with CheckApp's.
sed '/^@main$/d' "$repo/Examples/Library/LibraryApp.swift" > "$work/Sources/CheckApp/LibraryApp.swift"
cat > "$work/Sources/CheckApp/DataFlow.swift" <<'SWIFT'
import SwiftUI

@Observable
final class DataFlowModel {
    var count = 0
    var names = ["Ada", "Grace"]
    var rows = [DataFlowRow(id: 1, title: "One"), DataFlowRow(id: 2, title: "Two")]
}

struct DataFlowRow: Identifiable {
    var id: Int
    var title: String
}

struct DataFlowView: View {
    @State private var model = DataFlowModel()
    @State private var query = ""
    @State private var settings = DataFlowRow(id: 0, title: "Settings")
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.locale) private var locale
    @Environment(DataFlowModel.self) private var shared: DataFlowModel?

    var body: some View {
        @Bindable var model = model
        VStack {
            Text("\(model.count)")
            Text(dynamicTypeSize.isAccessibilitySize ? "Large" : "Regular")
            TextField("Title", text: $settings.title)
            ForEach($model.names, id: \.self) { $name in
                TextField("Name", text: $name)
            }
            ForEach($model.rows) { $row in
                DataFlowEditor(row: $row, model: model)
            }
            Group {
                AnyView(erasing: Text("Erased"))
                AnyView(Text(colorScheme == .light ? "Light" : "Dark"))
            }
            Text(horizontalSizeClass == .compact && verticalSizeClass == .regular ? "Phone" : "Other")
            Text(locale.identifier)
        }
        .onAppear { model.count += 1 }
        .onDisappear {}
        .onChange(of: model.count) { oldValue, newValue in query = "\(oldValue) \(newValue)" }
        .onChange(of: query, initial: true) {}
        .task(id: query) { await Task.yield() }
        .task(priority: .low) {}
        .environment(DataFlowModel())
    }
}

struct DataFlowEditor: View {
    @Binding var row: DataFlowRow
    @Bindable var model: DataFlowModel

    var body: some View {
        TextField("Row", text: $row.title)
        Text("\(model.rows.count) rows, \(Array($model.rows).count) bindings")
        Text("First row: \($model.rows[0].id)")
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
