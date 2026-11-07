import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let small = Device(
    name: "Small", screenSize: CGSize(width: 200, height: 400), safeAreaInsets: EdgeInsets())

private struct Player: View {
    @State private var shuffled = 0
    @State private var name = ""
    @State private var isOn = false

    var body: some View {
        VStack {
            Text("Shuffled \(shuffled)")
                .accessibilityIdentifier("count")
            Button("Shuffle") { shuffled += 1 }
                .accessibilityIdentifier("shuffle")
            Button {
                shuffled = 0
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityIdentifier("reset")
            .accessibilityLabel("Reset the count")
            TextField("Name", text: $name)
                .accessibilityIdentifier("name")
            Toggle("Loud", isOn: $isOn)
                .accessibilityIdentifier("loud")
            ScrollView {
                ForEach(0..<20) { _ in Color.blue.frame(width: 50, height: 40) }
            }
            .frame(height: 100)
            .accessibilityIdentifier("list")
        }
    }
}

@MainActor
@Suite("Accessibility identifiers and labels")
struct AccessibilityTests {
    @Test("The modifiers record attributes that the outline prints")
    func outline() {
        let host = ViewHost(
            VStack {
                Text("Hi").accessibilityIdentifier("greeting")
                Image(systemName: "star").accessibilityLabel("Favorite")
                Image(systemName: "heart").accessibilityLabel(Text("Like"))
                HStack {
                    Text("A")
                    Text("B")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pair")
            },
            device: small)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Hi" accessibilityIdentifier=greeting
                   ├─ Image accessibilityLabel=Favorite systemName=star
                   ├─ Image accessibilityLabel=Like systemName=heart
                   └─ HStack accessibilityElement=combine accessibilityIdentifier=pair
                      ├─ Text "A"
                      └─ Text "B"
                """)
    }

    @Test("The attributes survive the JSON round trip")
    func json() throws {
        let host = ViewHost(
            Text("Hi").accessibilityIdentifier("greeting").accessibilityLabel("Hello"),
            device: small)
        let data = try JSONEncoder().encode(host.root)
        let decoded = try JSONDecoder().decode(ViewNode.self, from: data)
        let text = try #require(decoded.allNodes.first { $0.kind == "Text" })
        #expect(text.accessibilityIdentifier == "greeting")
        #expect(text.accessibilityLabel == "Hello")
    }

    @Test("A button is tapped by identifier, wherever the layout puts it")
    func tapByIdentifier() throws {
        let host = ViewHost(Player(), device: small)
        try host.tap(accessibilityIdentifier: "shuffle")
        try host.tap(accessibilityIdentifier: "shuffle")
        #expect(host.nodes(withText: "Shuffled 2").count == 1)
        #expect(host.execute(.tapAccessibilityIdentifier("shuffle")).ok)
        #expect(host.nodes(withText: "Shuffled 3").count == 1)
    }

    @Test("A toggle is tapped through its identifier")
    func toggle() throws {
        let host = ViewHost(Player(), device: small)
        let before = host.root.outline()
        try host.tap(accessibilityIdentifier: "loud")
        #expect(host.root.outline() != before)
    }

    @Test("An accessibility label replaces the content as the label")
    func labelReplacesContent() throws {
        let host = ViewHost(Player(), device: small)
        let button = try #require(host.nodes(withAccessibilityIdentifier: "reset").first)
        #expect(button.label == "Reset the count")
        try host.tapButton(labeled: "Reset the count")
        #expect(throws: InteractionError.noButton(label: "Shuffle again")) {
            try host.tapButton(labeled: "Shuffle again")
        }

        let labeledText = ViewHost(
            Button("Shuffle") {}.accessibilityLabel("Mix up"), device: small)
        #expect(throws: InteractionError.noButton(label: "Shuffle")) {
            try labeledText.tapButton(labeled: "Shuffle")
        }
        try labeledText.tapButton(labeled: "Mix up")
    }

    @Test("A label inside a button's content is the button's label")
    func labelInsideButton() throws {
        let host = ViewHost(
            Button {
            } label: {
                Image(systemName: "play").accessibilityLabel("Play")
            },
            device: small)
        try host.tapButton(labeled: "Play")
    }

    @Test("A text field is focused and a scroll view scrolled by identifier")
    func fieldAndScroll() throws {
        let host = ViewHost(Player(), device: small)
        try host.focus(accessibilityIdentifier: "name")
        host.typeText("Ada")
        #expect(host.root.outline().contains("Ada"))
        try host.scroll(accessibilityIdentifier: "list", to: CGPoint(x: 0, y: 200))
        let list = try #require(host.nodes(withAccessibilityIdentifier: "list").first)
        #expect(host.scrollOffset(of: list.id)?.y == 200)
    }

    @Test("An identifier on a container reaches the elements inside and replaces theirs")
    func containerIdentifier() {
        let host = ViewHost(
            VStack {
                Text("One").accessibilityIdentifier("inner")
                Text("Two")
            }
            .accessibilityIdentifier("outer"),
            device: small)
        let outer = host.nodes(withAccessibilityIdentifier: "outer")
        #expect(outer.map(\.kind) == ["VStack", "Text", "Text"])
        #expect(host.nodes(withAccessibilityIdentifier: "inner").isEmpty)
    }

    @Test("A container element keeps its children's own identifiers")
    func containElement() {
        let host = ViewHost(
            VStack {
                Text("One").accessibilityIdentifier("inner")
                Text("Two")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("outer"),
            device: small)
        #expect(host.nodes(withAccessibilityIdentifier: "outer").map(\.kind) == ["VStack"])
        #expect(host.nodes(withAccessibilityIdentifier: "inner").map(\.kind) == ["Text"])
    }

    @Test("An ignoring element hides its children; a combining element joins their labels")
    func ignoreAndCombine() throws {
        let content = HStack {
            Text("Track").accessibilityIdentifier("hidden")
            Text("Title")
        }
        let ignored = ViewHost(
            content.accessibilityElement(children: .ignore).accessibilityIdentifier("row"),
            device: small)
        #expect(ignored.nodes(withAccessibilityIdentifier: "hidden").isEmpty)
        #expect(ignored.nodes(withAccessibilityIdentifier: "row").map(\.label) == [""])

        let combined = ViewHost(
            content.accessibilityElement(children: .combine).accessibilityIdentifier("row"),
            device: small)
        #expect(combined.nodes(withAccessibilityIdentifier: "row").map(\.label) == ["Track, Title"])

        let named = ViewHost(
            content.accessibilityElement(children: .ignore).accessibilityLabel("Now playing"),
            device: small)
        #expect(named.root.allNodes.first { $0.kind == "HStack" }?.label == "Now playing")
    }

    @Test("A button inside a combined row is tapped through the row's identifier")
    func combinedRow() throws {
        let host = ViewHost(
            HStack {
                Text("Song")
                Button("Play") {}
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("row"),
            device: small)
        try host.tap(accessibilityIdentifier: "row")
    }

    @Test("A control takes the identifier set on a view in its label")
    func identifierInLabel() throws {
        let host = ViewHost(
            Button {
            } label: {
                Image(systemName: "xmark").accessibilityIdentifier("close")
            },
            device: small)
        try host.tap(accessibilityIdentifier: "close")
    }

    @Test("Several matching controls are an error that lists them")
    func ambiguous() {
        let host = ViewHost(
            VStack {
                Button("A") {}
                Button("B") {}
            }
            .accessibilityIdentifier("pair"),
            device: small)
        #expect(
            throws: InteractionError.ambiguousAccessibilityIdentifier(
                "pair", matches: ["VStack/0/Button", "VStack/1/Button"])
        ) {
            try host.tap(accessibilityIdentifier: "pair")
        }
        let reply = host.execute(.tapAccessibilityIdentifier("pair"))
        #expect(!reply.ok)
        #expect(reply.message.contains("Several views have the accessibility identifier \"pair\""))
    }

    @Test("Unknown identifiers and the wrong kind of view are errors")
    func errors() {
        let host = ViewHost(Player(), device: small)
        #expect(throws: InteractionError.noAccessibilityIdentifier("nope")) {
            try host.tap(accessibilityIdentifier: "nope")
        }
        #expect(
            host.execute(.tapAccessibilityIdentifier("nope")).message
                == "No view on screen has the accessibility identifier \"nope\".")
        #expect(throws: InteractionError.self) {
            try host.tap(accessibilityIdentifier: "count")
        }
        #expect(throws: InteractionError.self) {
            try host.focus(accessibilityIdentifier: "shuffle")
        }
        #expect(throws: InteractionError.self) {
            try host.scroll(accessibilityIdentifier: "shuffle", to: .zero)
        }
    }

    @Test("A disabled control cannot be tapped by identifier")
    func disabled() {
        let host = ViewHost(
            Button("Off") {}.disabled(true).accessibilityIdentifier("off"), device: small)
        #expect(throws: InteractionError.self) {
            try host.tap(accessibilityIdentifier: "off")
        }
    }

    @Test("The commands focus, type into, and scroll views by identifier")
    func commands() {
        let host = ViewHost(Player(), device: small)
        #expect(host.execute(.focusAccessibilityIdentifier("name")).ok)
        #expect(host.execute(.typeText("Ada")).ok)
        #expect(
            host.execute(.scrollToAccessibilityIdentifier("list", x: 0, y: 100)).message
                == "Scrolled the view identified \"list\".")
        #expect(!host.execute(.focusAccessibilityIdentifier("shuffle")).ok)
    }

    @Test("The preview protocol advertises the capability")
    func capability() {
        #expect(PreviewCapability.all.contains(PreviewCapability.accessibilityIdentifiers))
    }
}
