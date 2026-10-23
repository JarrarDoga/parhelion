import Testing

@testable import ParhelionUI

private enum Flavor: String, CaseIterable, Hashable {
    case chocolate, vanilla
}

private struct Options: View {
    var body: some View {
        Text("Chocolate").tag(Flavor.chocolate)
        Text("Strict").tag(Flavor.vanilla, includeOptional: false)
        ForEach(["x", "y"], id: \.self) { Text($0) }
        ForEach([1], id: \.self) { _ in Text("Explicit").tag(Flavor.vanilla) }
        Text("Twice").tag(1).tag(2)
        VStack { Text("Inner").tag(9) }.tag(3)
    }
}

@MainActor
@Suite("Tags")
struct TagTests {
    @Test("A tagged view records its tag as an attribute")
    func outline() {
        let host = ViewHost(
            VStack {
                Text("One").tag(1)
                Text("Vanilla").tag(Flavor.vanilla)
            })
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "One" tag=1
                   └─ Text "Vanilla" tag=vanilla
                """)
    }

    @Test("A container reads the tags of the views it evaluates, by type")
    func collector() throws {
        let evaluator = Evaluator(host: ViewHost(EmptyView()))
        let (nodes, tags) = evaluator.evaluateTagged(Options(), at: ViewPath())
        func id(_ label: String) throws -> NodeID {
            try #require(nodes.first { $0.label == label }).id
        }

        #expect(tags.tag(of: try id("Chocolate"), as: Flavor.self) == .chocolate)
        #expect(tags.tag(of: try id("Chocolate"), as: Int.self) == nil)
        // A ForEach element's views are tagged with its identifier, unless
        // they set their own tag.
        #expect(tags.tag(of: try id("x"), as: String.self) == "x")
        #expect(tags.tag(of: try id("y"), as: String.self) == "y")
        #expect(tags.tag(of: try id("Explicit"), as: Flavor.self) == .vanilla)
        // The outermost tag wins, and tags inside a tagged view are its own.
        #expect(tags.tag(of: try id("Twice"), as: Int.self) == 2)
        #expect(tags.tag(of: try id("Inner"), as: Int.self) == 3)
        #expect(nodes.first { $0.label == "Inner" }?.attributes["tag"] == "3")
    }

    @Test("A tag matches an optional selection unless it excludes optionals")
    func optionalSelection() throws {
        let evaluator = Evaluator(host: ViewHost(EmptyView()))
        let (nodes, tags) = evaluator.evaluateTagged(Options(), at: ViewPath())
        let chocolate = try #require(nodes.first { $0.label == "Chocolate" }).id
        let strict = try #require(nodes.first { $0.label == "Strict" }).id

        let optional: Flavor?? = tags.tag(of: chocolate, as: Flavor?.self)
        #expect(optional == .some(.some(.chocolate)))
        let excluded: Flavor?? = tags.tag(of: strict, as: Flavor?.self)
        #expect(excluded == .none)
        #expect(tags.tag(of: strict, as: Flavor.self) == .vanilla)
    }
}
