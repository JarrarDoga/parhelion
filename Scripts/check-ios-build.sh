#!/bin/sh
# Checks that an app depending on Parhelion still builds for iOS with xtool.
# The app also compiles the Library example's sources, a file that uses the
# data-flow API (@Observable, @Bindable, bindings into collections, lifecycle
# modifiers, and environment values), and a file that uses shapes, gradients,
# the styling modifiers, images, AsyncImage, and grids, so that the same
# sources are known to build against Parhelion on Linux and against Apple's
# SwiftUI.
#
# Then it adds the LibraryApp fixture's Assets.xcassets and an image from it,
# builds for iOS again, and reports whether xtool built the app with the
# catalog. That second build does not fail the check: on 2026-10-24, xtool
# 1.22.2 could not build it, because SwiftPM runs `actool` from xtool's
# temporary folder, where xtool puts none.
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
cat > "$work/Sources/CheckApp/Content.swift" <<'SWIFT'
import SwiftUI

struct ContentWedge: Shape {
    var angle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center, radius: min(rect.width, rect.height) / 2, startAngle: .zero,
            endAngle: angle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct ContentGallery: View {
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Rectangle().fill(.red)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange)
                    Circle().fill(.green, style: FillStyle(eoFill: true))
                    Capsule(style: .circular).fill(.blue)
                    Ellipse()
                    ContentWedge(angle: .degrees(120)).fill(.purple)
                    Path { path in
                        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
                        path.addEllipse(in: CGRect(x: 2, y: 2, width: 6, height: 6))
                        path.addLines([.zero, CGPoint(x: 3, y: 3)])
                    }
                }
                LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom)
                Text("Gradient")
                    .foregroundStyle(
                        .linearGradient(
                            stops: [
                                Gradient.Stop(color: .red, location: 0),
                                Gradient.Stop(color: .blue, location: 1),
                            ], startPoint: .leading, endPoint: .trailing))
                Image("Badge", bundle: .main)
                    .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) { Circle().fill(.red).frame(width: 8) }
                    .overlay(.white.opacity(0.2), in: Capsule())
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    .scaleEffect(1.2, anchor: .center)
                    .scaleEffect(x: -1)
                    .aspectRatio(1, contentMode: .fill)
                Color.teal.cornerRadius(8)
                AsyncImage(url: URL(string: "https://example.com/a.png"))
                AsyncImage(url: nil, scale: 2) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                AsyncImage(url: nil, transaction: Transaction(animation: .default)) { phase in
                    if let image = phase.image { image } else { Color.gray }
                }
                if #available(iOS 27, *) {
                    AsyncImage(request: URLRequest(url: URL(fileURLWithPath: "/tmp/a.png")))
                        .asyncImageURLSession(.shared)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                    Text("A")
                }
                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.flexible())], pinnedViews: []) {
                    Text("B")
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow(alignment: .top) {
                        Text("Name").gridColumnAlignment(.trailing)
                        Text("Value").gridCellAnchor(.center)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    Text("Wide").gridCellColumns(2)
                }
            }
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

# The same app with an asset catalog, whose image it shows from Bundle.module.
cp -R "$repo/Tools/parhelion-cli/Fixtures/LibraryApp/Sources/LibraryApp/Assets.xcassets" \
    "$work/Sources/CheckApp/Assets.xcassets"
cat > "$work/Sources/CheckApp/Catalog.swift" <<'SWIFT'
import SwiftUI

struct CatalogImage: View {
    var body: some View {
        Image("Badge", bundle: .module)
    }
}
SWIFT
echo "Building for Linux with an asset catalog..."
swift build >/dev/null 2>&1
echo "Building for iOS with an asset catalog..."
if xtool dev build >"$work/catalog-build.log" 2>&1; then
    echo "OK: xtool built the app for iOS with its Assets.xcassets."
else
    # xtool's errors include the whole environment, so they are not printed.
    if grep -q 'actool' "$work/catalog-build.log"; then
        echo "note: xtool did not build the app for iOS with its Assets.xcassets: SwiftPM tried to run actool, which xtool does not provide."
    else
        echo "note: xtool did not build the app for iOS with its Assets.xcassets."
    fi
fi
