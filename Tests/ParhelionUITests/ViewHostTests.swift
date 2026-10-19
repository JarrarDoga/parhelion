import Foundation
import Testing

@testable import ParhelionUI

private struct Greeting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hello")
            Text("Parhelion")
        }
    }
}

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
            Button("Reset") { count = 0 }
        }
    }
}

private struct Toggle: View {
    @State private var isOn = false

    var body: some View {
        VStack {
            Button("Toggle") { isOn.toggle() }
            if isOn {
                Counter()
            } else {
                Text("Off")
            }
        }
    }
}

private struct Parent: View {
    @State private var name = "Ada"

    var body: some View {
        VStack {
            NameLabel(name: $name)
            Button("Rename") { name = "Grace" }
        }
    }
}

private struct NameLabel: View {
    @Binding var name: String

    var body: some View {
        Text(name)
    }
}

@MainActor
@Suite("ViewHost")
struct ViewHostTests {
    @Test("Resolves primitives and their attributes")
    func resolvesPrimitives() {
        let host = ViewHost(Greeting())
        #expect(
            host.root.outline() == """
                Root
                └─ VStack alignment=leading spacing=8
                   ├─ Text "Hello"
                   └─ Text "Parhelion"
                """
        )
    }

    @Test("Assigns structural identifiers")
    func structuralIdentifiers() {
        let host = ViewHost(Greeting())
        let ids = host.root.allNodes.map(\.id.rawValue)
        #expect(ids == ["", "Greeting/VStack", "Greeting/VStack/0/Text", "Greeting/VStack/1/Text"])
    }

    @Test("Tapping a button updates state and the tree")
    func tapUpdatesState() throws {
        let host = ViewHost(Counter())
        #expect(host.nodes(withText: "Count: 0").count == 1)

        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Increment")
        #expect(host.nodes(withText: "Count: 2").count == 1)

        try host.tapButton(labeled: "Reset")
        #expect(host.nodes(withText: "Count: 0").count == 1)
    }

    @Test("State survives updates while the view keeps its position")
    func statePersists() throws {
        let host = ViewHost(Toggle())
        try host.tapButton(labeled: "Toggle")
        try host.tapButton(labeled: "Increment")
        #expect(host.nodes(withText: "Count: 1").count == 1)
    }

    @Test("State is discarded when its view leaves the tree")
    func stateIsDiscarded() throws {
        let host = ViewHost(Toggle())
        try host.tapButton(labeled: "Toggle")
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Toggle")
        #expect(host.nodes(withText: "Off").count == 1)

        try host.tapButton(labeled: "Toggle")
        #expect(host.nodes(withText: "Count: 0").count == 1)
    }

    @Test("A binding writes through to its source")
    func bindingWritesThrough() throws {
        let host = ViewHost(Parent())
        #expect(host.nodes(withText: "Ada").count == 1)
        try host.tapButton(labeled: "Rename")
        #expect(host.nodes(withText: "Grace").count == 1)
    }

    @Test("Interaction errors name the problem")
    func interactionErrors() {
        let host = ViewHost(Counter())
        #expect(throws: InteractionError.noButton(label: "Missing")) {
            try host.tapButton(labeled: "Missing")
        }
        #expect(throws: InteractionError.nodeNotFound("Nope")) {
            try host.tap("Nope")
        }
        let textID = host.nodes(withText: "Count: 0")[0].id
        #expect(throws: InteractionError.notTappable(textID)) {
            try host.tap(textID)
        }
    }

    @Test("The resolved tree round-trips through JSON")
    func codable() throws {
        let host = ViewHost(Counter())
        let data = try JSONEncoder().encode(host.root)
        let decoded = try JSONDecoder().decode(ViewNode.self, from: data)
        #expect(decoded == host.root)
    }
}
