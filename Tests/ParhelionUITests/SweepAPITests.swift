import Foundation
import Testing

@testable import ParhelionUI

// SwiftUI APIs that a real iOS app uses: buttons with symbols, links and
// `openURL`, text field styles, button border shapes, the bottom bar, and
// string section index labels.

/// A 300 × 500 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 500),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

private let example = URL(string: "https://example.com")!

@MainActor
@Suite("Sweep APIs")
struct SweepAPITests {
    // MARK: - Buttons with symbols

    @Test("Button(_:systemImage:action:) is a button labeled with a title and a symbol")
    func buttonWithSymbol() {
        let host = ViewHost(
            VStack {
                Button("Share", systemImage: "square.and.arrow.up") {}
                Button("Delete", systemImage: "trash", role: .destructive) {}
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Button
                   │  └─ Label
                   │     ├─ Image systemName=square.and.arrow.up
                   │     └─ Text "Share"
                   └─ Button role=destructive
                      └─ Label
                         ├─ Image systemName=trash
                         └─ Text "Delete"
                """)
    }

    // MARK: - Links

    @Test("A link is a button that records its URL")
    func linkTree() {
        let host = ViewHost(
            VStack {
                Link("A link", destination: example)
                Link(destination: example) { Label("Site", systemImage: "globe") }
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Button link=https://example.com
                   │  └─ Text "A link"
                   └─ Button link=https://example.com
                      └─ Label
                         ├─ Image systemName=globe
                         └─ Text "Site"
                """)
    }

    @Test("Tapping a link opens its URL, which the host records")
    func linkOpens() throws {
        let host = ViewHost(Link("A link", destination: example), device: screen)
        #expect(host.openedURLs.isEmpty)
        try host.tapButton(labeled: "A link")
        #expect(host.openedURLs == [example])
        #expect(host.root.attributes["openedURL"] == "https://example.com")
    }

    @Test("A custom openURL action replaces the system action unless it asks for it")
    func customOpenURL() throws {
        let other = URL(string: "https://example.org")!
        struct Links: View {
            let other: URL
            var body: some View {
                VStack {
                    Link("Handled", destination: example)
                        .environment(\.openURL, OpenURLAction { _ in .handled })
                    Link("System", destination: example)
                        .environment(\.openURL, OpenURLAction { _ in .systemAction })
                    Link("Other", destination: example)
                        .environment(\.openURL, OpenURLAction { _ in .systemAction(other) })
                }
            }
        }
        let host = ViewHost(Links(other: other), device: screen)
        try host.tapButton(labeled: "Handled")
        #expect(host.openedURLs.isEmpty)
        try host.tapButton(labeled: "System")
        try host.tapButton(labeled: "Other")
        #expect(host.openedURLs == [example, other])
    }

    @Test("A view can open a URL with the openURL action from the environment")
    func environmentOpenURL() throws {
        struct Opener: View {
            @Environment(\.openURL) var openURL
            var body: some View {
                Button("Open") { openURL(example) }
            }
        }
        let host = ViewHost(Opener(), device: screen)
        try host.tapButton(labeled: "Open")
        #expect(host.openedURLs == [example])
    }

    // MARK: - Text field styles

    @Test("A rounded border field is padded inside a hairline border")
    func roundedBorderField() throws {
        let host = ViewHost(
            VStack {
                TextField("Search", text: .constant("")).textFieldStyle(.roundedBorder)
                TextField("Plain", text: .constant("")).textFieldStyle(.plain)
                TextField("Default", text: .constant(""))
            }.padding(24), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack padding(24)
                   ├─ TextField padding(6, 7, 6, 7) roundedBorderTextField placeholder=Search textFieldStyle=roundedBorder value=
                   ├─ TextField placeholder=Plain textFieldStyle=plain value=
                   └─ TextField placeholder=Default value=
                """)
        // Measured on an iPhone on iOS 27: the field is 34 points high.
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        #expect(field.modifierFrames.last?.height == 34)
    }

    // MARK: - Button border shapes

    @Test("Bordered buttons record their border shape; other buttons do not")
    func borderShapeTree() {
        let host = ViewHost(
            VStack {
                Button("Capsule") {}.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                Button("Square") {}.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle)
                Button("Twelve") {}.buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                Button("+") {}.buttonStyle(.bordered).buttonBorderShape(.circle)
                Button("Plain") {}.buttonBorderShape(.circle)
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Button buttonBorderShape=capsule buttonStyle=borderedProminent
                   │  └─ Text "Capsule"
                   ├─ Button buttonBorderShape=roundedRectangle buttonStyle=bordered
                   │  └─ Text "Square"
                   ├─ Button buttonBorderShape=roundedRectangle(12) buttonStyle=bordered
                   │  └─ Text "Twelve"
                   ├─ Button buttonBorderShape=circle buttonStyle=bordered
                   │  └─ Text "+"
                   └─ Button
                      └─ Text "Plain"
                """)
    }

    @Test("A circle button is square, and a rounded rectangle has its radius")
    func borderShapeGeometry() throws {
        let host = ViewHost(
            Button("+") {}.buttonStyle(.bordered).buttonBorderShape(.circle), device: screen)
        let frame = try #require(host.root.children.first?.frame)
        #expect(frame.width == frame.height)
        #expect(
            ButtonBorderShape.cornerRadius(attribute: "roundedRectangle(12)", in: frame) == 12)
        #expect(
            ButtonBorderShape.cornerRadius(attribute: "roundedRectangle", in: frame)
                == ButtonBorderShape.defaultCornerRadius)
        #expect(ButtonBorderShape.cornerRadius(attribute: nil, in: frame) == frame.height / 2)
    }

    // MARK: - Bottom bar

    @Test("A bottom bar item is a glass group at the bottom of the navigation stack")
    func bottomBar() throws {
        let phone = try #require(Device.named("iPhone 18 Pro Max"))
        var shared = 0
        let host = ViewHost(
            NavigationStack {
                Text("Detail")
                    .navigationTitle("Detail")
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Share", systemImage: "square.and.arrow.up") { shared += 1 }
                        }
                    }
            }, device: phone)
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=large
                   │  └─ Text "Detail" font=largeTitle.bold
                   ├─ Text "Detail"
                   └─ ToolbarItemGroup placement=bottom
                      └─ Button
                         └─ Label
                            └─ Image imageScale=large systemName=square.and.arrow.up
                """)
        // Measured on an iPhone on iOS 27: a 48-point circle whose bottom is
        // 28 points above the bottom of the screen, centered.
        let bar = try #require(
            host.root.allNodes.first { $0.attributes["placement"] == "bottom" }?.frame)
        #expect(bar == CGRect(x: 196, y: 880, width: 48, height: 48))
        try host.tap(at: CGPoint(x: bar.midX, y: bar.midY))
        #expect(shared == 1)
    }

    // MARK: - Section index labels

    @Test("A section index label can be a string")
    func stringSectionIndexLabel() {
        let letter = "B"
        let host = ViewHost(
            List {
                Section("A") { Text("A one") }.sectionIndexLabel("A")
                Section(letter) { Text("B one") }.sectionIndexLabel(letter)
            }, device: screen)
        let labels = host.root.allNodes.compactMap { $0.attributes["sectionIndexLabel"] }
        #expect(labels == ["A", "B"])
    }
}
