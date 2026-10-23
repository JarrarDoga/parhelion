import Foundation
import Testing

@testable import ParhelionUI

private struct Grouped: View {
    var body: some View {
        VStack {
            Group {
                Text("One")
                Text("Two")
            }
            .foregroundStyle(.secondary)
            Text("Three")
        }
    }
}

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        Button("Count: \(count)") { count += 1 }
    }
}

private struct Erased: View {
    @State private var showsCounter = true

    var body: some View {
        VStack {
            Button("Switch") { showsCounter.toggle() }
            content
        }
    }

    private var content: AnyView {
        showsCounter ? AnyView(Counter()) : AnyView(erasing: Text("No counter"))
    }
}

@MainActor
@Suite("Group and AnyView")
struct GroupTests {
    @Test("A group adds its views to its parent, and its modifiers apply to each")
    func group() {
        let host = ViewHost(Grouped())
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "One" foregroundStyle=secondary
                   ├─ Text "Two" foregroundStyle=secondary
                   └─ Text "Three"
                """
        )
        let ids = host.root.allNodes.map(\.id.rawValue)
        #expect(ids.contains("Grouped/VStack/0/0/Text"))
    }

    @Test("A group lays out as its views would without it")
    func groupLayout() {
        let grouped = ViewHost(Grouped()).root.allNodes.compactMap(\.frame)
        let plain = ViewHost(
            VStack {
                Text("One").foregroundStyle(.secondary)
                Text("Two").foregroundStyle(.secondary)
                Text("Three")
            }
        ).root.allNodes.compactMap(\.frame)
        #expect(grouped == plain)
    }

    @Test("AnyView resolves to the view it wraps")
    func anyView() throws {
        let host = ViewHost(Erased())
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Button
                   │  └─ Text "Switch"
                   └─ Button
                      └─ Text "Count: 0"
                """
        )
        #expect(AnyView(_fromValue: Text("Hi")) != nil)
        #expect(AnyView(_fromValue: 42) == nil)
    }

    @Test("A wrapped view of another type starts with new state")
    func anyViewIdentity() throws {
        let host = ViewHost(Erased())
        try host.tapButton(labeled: "Count: 0")
        try host.tapButton(labeled: "Count: 1")
        try host.tapButton(labeled: "Switch")
        #expect(host.nodes(withText: "No counter").count == 1)
        try host.tapButton(labeled: "Switch")
        #expect(host.nodes(withText: "Count: 0").count == 1)
    }
}
