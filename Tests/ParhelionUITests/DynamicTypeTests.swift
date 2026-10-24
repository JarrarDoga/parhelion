import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 300),
    safeAreaInsets: EdgeInsets()
)

/// Text that shows the Dynamic Type size it reads from the environment.
private struct SizeLabel: View {
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        Text(size.name)
    }
}

/// A color whose size comes from scaled metrics.
private struct ScaledSquare: View {
    @ScaledMetric private var width: CGFloat = 100
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 24

    var body: some View {
        Color.red.frame(width: width, height: height)
    }
}

@MainActor
private func frame(_ host: ViewHost, text: String) throws -> CGRect {
    try #require(host.root.allNodes.first { $0.text == text }?.frame)
}

@MainActor
@Suite("Dynamic Type")
struct DynamicTypeTests {
    @Test("The table's Large column is the default size of every text style")
    func largeColumn() {
        for style in Font.TextStyle.allCases {
            let metrics = LayoutDefaults.textStyleMetrics(style)
            let entry = DynamicTypeTable.entry(style, .large)
            #expect(entry.size == metrics.size && entry.lineHeight == metrics.lineHeight)
            #expect(DynamicTypeTable.entries(style).count == DynamicTypeSize.allCases.count)
        }
    }

    @Test("The table has the kit's sizes and line heights, from xSmall to accessibility5")
    func cells() {
        func entry(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> [CGFloat] {
            let entry = DynamicTypeTable.entry(style, size)
            return [entry.size, entry.lineHeight]
        }
        #expect(entry(.largeTitle, .xSmall) == [31, 38])
        #expect(entry(.largeTitle, .accessibility3) == [52, 61])
        #expect(entry(.title2, .xxxLarge) == [28, 34])
        #expect(entry(.body, .xxxLarge) == [23, 29])
        #expect(entry(.body, .accessibility5) == [53, 62])
        #expect(entry(.subheadline, .xxxLarge) == [21, 28])
        #expect(entry(.footnote, .medium) == [12, 16])
        #expect(entry(.caption, .accessibility1) == [22, 28])
        #expect(entry(.caption2, .xSmall) == [11, 13])
        #expect(entry(.caption2, .accessibility5) == [40, 48])
        // Sizes never shrink as the setting grows.
        for style in Font.TextStyle.allCases {
            let sizes = DynamicTypeTable.entries(style).map(\.size)
            #expect(sizes == sizes.sorted())
        }
    }

    @Test("Text styles scale with the device's text size and record the size they draw at")
    func deviceSize() throws {
        let host = ViewHost(
            VStack(spacing: 0) {
                Text("Body")
                Text("Title").font(.title)
                Text("Fixed").font(.system(size: 17))
            }, device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack spacing=0
                   ├─ Text "Body"
                   ├─ Text "Title" font=title
                   └─ Text "Fixed" font=system(17)
                """)
        host.dynamicTypeSize = .xxxLarge
        #expect(
            host.root.outline() == """
                Root dynamicTypeSize=xxxLarge
                └─ VStack spacing=0
                   ├─ Text "Body" fontSize=23
                   ├─ Text "Title" font=title fontSize=34
                   └─ Text "Fixed" font=system(17)
                """)
        #expect(try frame(host, text: "Body").height == 29)
        #expect(try frame(host, text: "Title").height == 41)
        #expect(try frame(host, text: "Fixed").height == 20)
    }

    @Test("dynamicTypeSize(_:) sets the size of its content and records it there")
    func setSize() {
        let host = ViewHost(
            VStack {
                SizeLabel()
                SizeLabel().dynamicTypeSize(.accessibility1)
            }, device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "large"
                   └─ Text "accessibility1" dynamicTypeSize=accessibility1 fontSize=28
                """)
    }

    // Apple's three examples, from the documentation of `dynamicTypeSize(_:)`
    // with a size and with a range.

    @Test("A range applied after a size limits it")
    func rangeLimitsSize() {
        let host = ViewHost(
            SizeLabel()
                .dynamicTypeSize(...DynamicTypeSize.large)
                .dynamicTypeSize(.xLarge), device: square)
        #expect(host.root.allNodes.compactMap(\.text) == ["large"])
    }

    @Test("A size set after a range is not limited by it")
    func sizeAfterRange() {
        let host = ViewHost(
            SizeLabel()
                .dynamicTypeSize(.xLarge)
                .dynamicTypeSize(...DynamicTypeSize.large), device: square)
        #expect(host.root.allNodes.compactMap(\.text) == ["xLarge"])
    }

    @Test("Several ranges limit the size to their intersection")
    func rangesIntersect() {
        func size(on device: DynamicTypeSize) -> [String] {
            ViewHost(
                SizeLabel()
                    .dynamicTypeSize(.small...)
                    .dynamicTypeSize(...DynamicTypeSize.large), device: square,
                dynamicTypeSize: device
            ).root.allNodes.compactMap(\.text)
        }
        #expect(size(on: .xSmall) == ["small"])
        #expect(size(on: .medium) == ["medium"])
        #expect(size(on: .accessibility3) == ["large"])
    }

    @Test("@ScaledMetric scales like body text, or like the style it is relative to")
    func scaledMetric() throws {
        let host = ViewHost(ScaledSquare(), device: square)
        var color = try #require(host.root.allNodes.first { $0.kind == "Color" }?.frame)
        #expect(color.size == CGSize(width: 100, height: 24))
        host.dynamicTypeSize = .xxxLarge
        color = try #require(host.root.allNodes.first { $0.kind == "Color" }?.frame)
        // Body is 23 points instead of 17, and caption 18 instead of 12.
        #expect(abs(color.width - 100 * 23 / 17) < 0.01)
        #expect(color.height == 36)
    }

    @Test("Custom fonts scale with a text style unless their size is fixed")
    func customFonts() throws {
        let host = ViewHost(
            VStack(spacing: 0) {
                Text("Body").font(.custom("Avenir", size: 17))
                Text("Caption").font(.custom("Avenir", size: 12, relativeTo: .caption))
                Text("Fixed").font(.custom("Avenir", fixedSize: 17))
            }, device: square, dynamicTypeSize: .xxxLarge)
        #expect(
            host.root.outline() == """
                Root dynamicTypeSize=xxxLarge
                └─ VStack spacing=0
                   ├─ Text "Body" font=custom(Avenir,17) fontSize=23
                   ├─ Text "Caption" font=custom(Avenir,12) fontSize=18
                   └─ Text "Fixed" font=custom(Avenir,17)
                """)
        // A custom font's line is San Francisco's for the size it is drawn
        // at, as the system font's is.
        #expect(try frame(host, text: "Body").height == 28)
        #expect(try frame(host, text: "Fixed").height == 20)
    }

    @Test("A list's rows grow with their text, and its footers scale like footnote")
    func listRows() throws {
        func list() -> some View {
            List {
                Section {
                    Text("Row")
                } footer: {
                    Text("Footer")
                }
            }
        }
        let large = ViewHost(list(), device: .iPhone16)
        let row = try #require(large.root.allNodes.first { $0.listRowFrame != nil })
        #expect(row.listRowFrame?.height == 52)

        let host = ViewHost(list(), device: .iPhone16, dynamicTypeSize: .accessibility2)
        let scaled = try #require(host.root.allNodes.first { $0.listRowFrame != nil })
        // Body is 33 on a 40-point line, inside the row's 15-point insets.
        #expect(scaled.listRowFrame?.height == 70)
        let footer = try #require(host.root.allNodes.first { $0.text == "Footer" })
        #expect(footer.attributes["font"] == "system(13)")
        #expect(footer.attributes["fontSize"] == "27")
    }

    @Test("Toolbar items and tab bars keep their size, and a large title's bar grows")
    func bars() throws {
        let navigation = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Title")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} }
                    }
            }, device: .iPhone16, dynamicTypeSize: .accessibility1)
        let bar = try #require(navigation.root.allNodes.first { $0.kind == "NavigationBar" })
        let edit = try #require(bar.allNodes.first { $0.text == "Edit" })
        #expect(edit.attributes["fontSize"] == nil)
        let title = try #require(bar.allNodes.first { $0.text == "Title" })
        #expect(title.attributes["font"] == "largeTitle.bold")
        #expect(title.attributes["fontSize"] == "44")
        // 54 + the title's 52-point line + 10, instead of 105 at Large.
        #expect(bar.frame?.height == 116)

        let tabs = ViewHost(
            TabView {
                Tab("Home", systemImage: "house") { Text("Home") }
            }, device: .iPhone16, dynamicTypeSize: .accessibility5)
        let tabBar = try #require(tabs.root.allNodes.first { $0.kind == "TabBar" })
        #expect(tabBar.allNodes.allSatisfy { $0.attributes["fontSize"] == nil })
        #expect(tabBar.frame?.height == LayoutDefaults.tabBarHeight)
    }

    @Test("Bordered and alert buttons grow with their labels, never below the kit's height")
    func buttons() throws {
        let host = ViewHost(
            Button("Bordered") {}
                .buttonStyle(.bordered)
                .alert("Title", isPresented: .constant(true)) {
                    Button("OK") {}
                }, device: .iPhone16, dynamicTypeSize: .accessibility3)
        let bordered = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Bordered" }?.frame)
        // Body is 40 on a 48-point line, with the kit's 6 points above and below.
        #expect(bordered.height == 60)
        let ok = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "OK" }?.frame)
        #expect(ok.height == 74)

        let small = ViewHost(
            Button("Bordered") {}.buttonStyle(.bordered), device: .iPhone16,
            dynamicTypeSize: .xSmall)
        let smallBordered = try #require(
            small.root.allNodes.first { $0.kind == "Button" && $0.label == "Bordered" })
        #expect(smallBordered.frame?.height == 34)
    }

    @Test("A text field's text scales like body text")
    func textField() throws {
        let host = ViewHost(
            TextField("Name", text: .constant("Ada")), device: square,
            dynamicTypeSize: .accessibility1)
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        #expect(field.attributes["fontSize"] == "28")
        #expect(field.frame?.height == 34)
        let large = ViewHost(TextField("Name", text: .constant("Ada")), device: square)
        #expect(large.root.allNodes.first { $0.kind == "TextField" }?.attributes["fontSize"] == nil)
    }

    @Test("Symbols scale with the font around them")
    func symbols() throws {
        let host = ViewHost(
            Image(systemName: "star"), device: square, dynamicTypeSize: .xxxLarge)
        let symbol = try #require(host.root.allNodes.first { $0.kind == "Image" })
        #expect(symbol.attributes["fontSize"] == "23")
        #expect(symbol.frame?.width == 23)
    }

    @Test("A font's attributes read back as the font they record")
    func attributesRoundTrip() {
        let fonts: [ResolvedFont] = [
            Font.body.resolved(dynamicTypeSize: .xxxLarge),
            Font.headline.bold().resolved(dynamicTypeSize: .accessibility4),
            Font.caption2.resolved(dynamicTypeSize: .small),
            Font.custom("Avenir", size: 20, relativeTo: .title3).resolved(dynamicTypeSize: .xLarge),
            LayoutDefaults.listFooterFont.resolved(dynamicTypeSize: .xxLarge),
        ]
        for font in fonts {
            var attributes: [String: String] = [:]
            font.record(in: &attributes)
            let read = ResolvedFont(attribute: attributes["font"], fontSize: attributes["fontSize"])
            #expect(read.size == font.size)
            #expect(read.lineHeight == font.lineHeight)
            #expect(read.weight == font.weight)
        }
    }
}
