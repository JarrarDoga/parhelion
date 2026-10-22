import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe-area insets.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets()
)

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
    }
}

private struct Library: View {
    var body: some View {
        NavigationStack {
            VStack {
                Counter()
                NavigationLink("Details") {
                    Counter().navigationTitle("Details")
                }
            }
            .navigationTitle("Library")
        }
    }
}

private struct Numbers: View {
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("Three", value: 3)
                Button("Jump") { path = [1, 2] }
            }
            .navigationDestination(for: Int.self) { number in
                Text("Number \(number)").navigationTitle("\(number)")
            }
        }
    }
}

@MainActor
private func texts(_ host: ViewHost) -> [String] {
    host.root.allNodes.compactMap(\.text)
}

@MainActor
@Suite("Navigation")
struct NavigationTests {
    @Test("A stack shows its root view under a bar with the title")
    func outline() {
        let host = ViewHost(Library(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=large
                   │  └─ Text "Library" font=largeTitle.bold
                   └─ VStack
                      ├─ VStack
                      │  ├─ Text "Count: 0"
                      │  └─ Button
                      │     └─ Text "Increment"
                      └─ NavigationLink
                         └─ Text "Details"
                """)
    }

    @Test("The bar sits at the top, and content is centered below it")
    func layout() throws {
        let host = ViewHost(Library(), device: screen)
        let stack = host.root.children[0]
        #expect(stack.frame == CGRect(x: 0, y: 0, width: 300, height: 400))
        // A large title: a 44-point row, a 10-point gap, the 41-point title
        // line, and 10 points below it.
        let bar = try #require(stack.children[0].frame)
        #expect(bar == CGRect(x: 0, y: 0, width: 300, height: 105))
        let title = try #require(stack.children[0].children[0].frame)
        #expect(title.origin == CGPoint(x: 16, y: 54))
        #expect(title.height == 41)
        // The content is centered in the 295 points below the bar.
        let content = try #require(stack.children[1].frame)
        #expect(abs(content.midY - (105 + 295.0 / 2)) < 0.01)
    }

    @Test("An inline title is centered in the bar's top row, and the bar is 54 points tall")
    func inlineTitle() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Inbox")
                    .navigationBarTitleDisplayMode(.inline)
            },
            device: screen
        )
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=inline
                   │  └─ Text "Inbox" font=headline
                   └─ Text "Content"
                """)
        let bar = host.root.children[0].children[0]
        #expect(bar.frame == CGRect(x: 0, y: 0, width: 300, height: 54))
        let title = try #require(bar.children[0].frame)
        // Semibold 17 on a 22-point line, centered in the top 44 points.
        #expect(abs(title.midX - 150) < 0.01)
        #expect(title.minY == 11 && title.height == 22)
    }

    @Test("Toolbar items center in the bar's top row with either title")
    func toolbarRow() throws {
        for mode in [NavigationBarItem.TitleDisplayMode.large, .inline] {
            let host = ViewHost(
                NavigationStack {
                    Text("Content")
                        .navigationTitle("Title")
                        .navigationBarTitleDisplayMode(mode)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Button("Edit") {} }
                            ToolbarItem(placement: .topBarTrailing) { Button("Add") {} }
                        }
                },
                device: screen
            )
            let bar = host.root.children[0].children[0]
            for group in bar.children where group.kind == "ToolbarItemGroup" {
                let frame = try #require(group.frame)
                #expect(frame.midY == 22)
                #expect(frame.height == 22)
            }
        }
    }

    @Test("A pushed view's title takes the display mode of the view beneath")
    func inheritedDisplayMode() throws {
        func barAfterPush(
            root: NavigationBarItem.TitleDisplayMode, pushed: NavigationBarItem.TitleDisplayMode
        )
            throws -> ViewNode
        {
            let host = ViewHost(
                NavigationStack {
                    NavigationLink("Open") {
                        Text("Detail")
                            .navigationTitle("Detail")
                            .navigationBarTitleDisplayMode(pushed)
                    }
                    .navigationTitle("Root")
                    .navigationBarTitleDisplayMode(root)
                },
                device: screen
            )
            try host.tapButton(labeled: "Open")
            return host.root.children[0].children[0]
        }
        func mode(_ bar: ViewNode) -> String? { bar.attributes["titleDisplayMode"] }

        #expect(mode(try barAfterPush(root: .automatic, pushed: .automatic)) == "large")
        #expect(mode(try barAfterPush(root: .inline, pushed: .automatic)) == "inline")
        #expect(mode(try barAfterPush(root: .inline, pushed: .large)) == "large")
        #expect(mode(try barAfterPush(root: .large, pushed: .inline)) == "inline")

        // The back button stays in the top row, above the large title.
        let bar = try barAfterPush(root: .automatic, pushed: .automatic)
        let back = try #require(bar.allNodes.first { $0.id.rawValue.hasSuffix("/bar/back") })
        let title = try #require(bar.children.first { $0.kind == "Text" })
        #expect(try #require(back.frame).midY == 22)
        #expect(try #require(back.frame).maxY <= 44)
        #expect(title.attributes["font"] == "largeTitle.bold")
        #expect(try #require(title.frame).origin == CGPoint(x: 16, y: 54))
    }

    @Test("A bar with principal items or without a title uses the inline layout")
    func inlineWithoutTitle() throws {
        let principal = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Hidden")
                    .toolbar { ToolbarItem(placement: .principal) { Text("Custom") } }
            },
            device: screen
        )
        let bar = principal.root.children[0].children[0]
        #expect(bar.attributes["titleDisplayMode"] == "inline")
        #expect(bar.frame?.height == 54)
        #expect(try #require(bar.children[0].frame).midY == 22)

        let untitled = ViewHost(NavigationStack { Text("Content") }, device: screen)
        #expect(untitled.root.children[0].children[0].frame?.height == 54)
    }

    @Test("The large title draws in bold at the leading edge")
    func largeTitlePixels() {
        let host = ViewHost(
            NavigationStack { Text("Content").navigationTitle("IIIIII") }, device: screen)
        let frame = host.render(scale: 2)
        // Inter Bold's I stem at 34 points is over 4 points wide, starting a
        // few points in from x = 16.
        var dark = 0
        for x in stride(from: 16.0, to: 40.0, by: 0.5) {
            if frame.color(at: CGPoint(x: x, y: 75)).red < 64 { dark += 1 }
        }
        #expect(dark >= 8)
        // Nothing is drawn at the center of the top row, where an inline
        // title would be.
        #expect(frame.color(at: CGPoint(x: 150, y: 22)).red == 255)
    }

    @Test("A link pushes its destination, and the back button returns")
    func pushAndPop() throws {
        let host = ViewHost(Library(), device: screen)
        try host.tapButton(labeled: "Details")
        #expect(texts(host) == ["Library", "Details", "Count: 0", "Increment"])
        let back = try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix("/bar/back") })
        #expect(back.kind == "Button")
        #expect(back.label == "Library")
        try host.tap(back.id)
        #expect(texts(host).first == "Library")
        #expect(texts(host).contains("Details"))
    }

    @Test("The view beneath keeps its state; a popped view loses its own")
    func stateLifetime() throws {
        let host = ViewHost(Library(), device: screen)
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Details")
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Increment")
        #expect(texts(host).contains("Count: 2"))
        try host.tapButton(labeled: "Library")
        #expect(texts(host).contains("Count: 1"))
        try host.tapButton(labeled: "Details")
        #expect(texts(host).contains("Count: 0"))
    }

    @Test("A value link pushes through the path binding and navigationDestination")
    func valueLinks() throws {
        let host = ViewHost(Numbers(), device: screen)
        try host.tapButton(labeled: "Three")
        #expect(texts(host) == ["Back", "3", "Number 3"])
        try host.tapButton(labeled: "Back")
        try host.tapButton(labeled: "Jump")
        #expect(texts(host) == ["1", "2", "Number 2"])
        try host.tapButton(labeled: "1")
        #expect(texts(host) == ["Back", "1", "Number 1"])
    }

    @Test("A navigation path holds values of any hashable type")
    func navigationPath() {
        var path = NavigationPath()
        path.append(1)
        path.append("two")
        #expect(path.count == 2)
        path.removeLast()
        #expect(path == NavigationPath([1]))
        #expect(!path.isEmpty)
    }

    @Test("Toolbar items go to the leading and trailing ends of the bar")
    func toolbar() throws {
        let tapped = Flag()
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Title")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { tapped.isSet = true }
                        }
                    }
            },
            device: screen
        )
        let bar = host.root.children[0].children[0]
        #expect(
            bar.children.map { $0.attributes["placement"] ?? $0.kind } == [
                "leading", "Text", "trailing",
            ])
        let leading = try #require(bar.children[0].frame)
        let trailing = try #require(bar.children[2].frame)
        #expect(leading.minX == 16)
        #expect(trailing.maxX == 284)
        try host.tapButton(labeled: "Done")
        #expect(tapped.isSet)
    }

    @Test("A link in a list leaves room for its disclosure indicator")
    func listRow() throws {
        let host = ViewHost(
            NavigationStack {
                List { NavigationLink("Row") { Text("Detail") } }
            },
            device: screen
        )
        let link = try #require(host.root.allNodes.first { $0.kind == "NavigationLink" })
        guard case .listRow(let insets) = link.modifiers.last else {
            Issue.record("The link has no listRow modifier.")
            return
        }
        #expect(insets.trailing == 39)
        let cell = try #require(link.listRowFrame)
        try host.tap(at: CGPoint(x: cell.maxX - 10, y: cell.midY))
        #expect(texts(host).contains("Detail"))
    }

    @Test("A link outside a navigation stack does nothing")
    func linkOutsideStack() {
        let host = ViewHost(NavigationLink("Orphan") { Text("Detail") }, device: screen)
        #expect((try? host.tapButton(labeled: "Orphan")) == nil)
        #expect(texts(host) == ["Orphan"])
    }

    @Test("A pushed view whose link disappears is popped")
    func vanishingLink() throws {
        let host = ViewHost(Disappearing(), device: screen)
        try host.tapButton(labeled: "Open")
        #expect(texts(host).contains("Hide the link"))
        try host.tapButton(labeled: "Hide the link")
        #expect(texts(host) == ["Link hidden"])
    }

    @Test("A grouped list under the bar extends its background behind it")
    func barBackground() {
        let host = ViewHost(NavigationStack { List { Text("Row") } }, device: screen)
        let color = host.render(scale: 1).color(at: CGPoint(x: 5, y: 5))
        #expect([color.red, color.green, color.blue] == [242, 242, 247])
    }
}

private struct Disappearing: View {
    @State private var showsLink = true

    var body: some View {
        NavigationStack {
            if showsLink {
                NavigationLink("Open") {
                    Button("Hide the link") { showsLink = false }
                }
            } else {
                Text("Link hidden")
            }
        }
    }
}

@MainActor
private final class Flag {
    var isSet = false
}
