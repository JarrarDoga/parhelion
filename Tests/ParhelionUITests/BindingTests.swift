import Foundation
import Observation
import Testing

@testable import ParhelionUI

private struct Item: Identifiable {
    var id: Int
    var title: String
    var isDone = false
}

@Observable
private final class Checklist {
    var name = "Groceries"
    var items = [
        Item(id: 1, title: "Milk"),
        Item(id: 2, title: "Eggs"),
    ]
}

private struct ItemRow: View {
    @Binding var item: Item

    var body: some View {
        Button(item.isDone ? "✓ \(item.title)" : item.title) { item.isDone.toggle() }
    }
}

private struct ChecklistView: View {
    @Bindable var checklist: Checklist

    var body: some View {
        VStack {
            TextField("Name", text: $checklist.name)
            ForEach($checklist.items) { $item in
                ItemRow(item: $item)
            }
        }
    }
}

private struct EnvironmentChecklistView: View {
    @Environment(Checklist.self) private var checklist

    var body: some View {
        @Bindable var checklist = checklist
        VStack {
            Text(checklist.name)
            TextField("Name", text: $checklist.name)
        }
    }
}

private struct Settings {
    var nickname = "Ada"
    var volume = 3
}

private struct SettingsView: View {
    @State private var settings = Settings()

    var body: some View {
        VStack {
            Text("\(settings.nickname) \(settings.volume)")
            TextField("Nickname", text: $settings.nickname)
        }
    }
}

private struct KeyedRows: View {
    @State private var items = [Item(id: 1, title: "Milk"), Item(id: 2, title: "Eggs")]

    var body: some View {
        VStack {
            ForEach($items, id: \.title) { $item in
                Text(item.title)
            }
            Button("Reverse") { items.reverse() }
        }
    }
}

@MainActor
@Suite("Bindings")
struct BindingTests {
    @Test("ForEach over a binding gives each row a binding to its element")
    func forEachBinding() throws {
        let checklist = Checklist()
        let host = ViewHost(ChecklistView(checklist: checklist))
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ TextField placeholder=Name value=Groceries
                   ├─ Button
                   │  └─ Text "Milk"
                   └─ Button
                      └─ Text "Eggs"
                """
        )
        let ids = host.root.allNodes.filter { $0.kind == "Button" }.map(\.id.rawValue)
        #expect(
            ids == [
                "ChecklistView/VStack/1/ForEach[1]/ItemRow/Button",
                "ChecklistView/VStack/1/ForEach[2]/ItemRow/Button",
            ])

        try host.tapButton(labeled: "Eggs")
        #expect(checklist.items[1].isDone)
        #expect(host.nodes(withText: "✓ Eggs").count == 1)
    }

    @Test("ForEach over a binding with a key path uses it for identity")
    func forEachBindingWithKeyPath() throws {
        let host = ViewHost(KeyedRows())
        let first = host.root.allNodes.filter { $0.kind == "Text" }.map(\.id.rawValue)
        #expect(first.first == "KeyedRows/VStack/0/ForEach[Milk]/Text")
        try host.tapButton(labeled: "Reverse")
        let texts = host.root.allNodes.filter { $0.kind == "Text" }.compactMap(\.text)
        #expect(texts == ["Eggs", "Milk", "Reverse"])
    }

    @Test("@Bindable makes bindings to an object's properties")
    func bindable() throws {
        let checklist = Checklist()
        let host = ViewHost(ChecklistView(checklist: checklist))
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        try host.focus(field.id)
        host.typeText("!")
        #expect(checklist.name == "Groceries!")
        #expect(host.root.node(withID: field.id)?.attributes["value"] == "Groceries!")
    }

    @Test("A local @Bindable binds to an object from the environment")
    func localBindable() throws {
        let checklist = Checklist()
        let host = ViewHost(EnvironmentChecklistView().environment(checklist))
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        try host.focus(field.id)
        host.typeText(" list")
        #expect(checklist.name == "Groceries list")
        #expect(host.nodes(withText: "Groceries list").count == 1)
    }

    @Test("A binding's dynamic members bind to parts of a value")
    func dynamicMember() throws {
        let host = ViewHost(SettingsView())
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        try host.focus(field.id)
        host.typeText("!")
        #expect(host.nodes(withText: "Ada! 3").count == 1)
    }

    @Test("A binding to a collection is a collection of bindings")
    func collection() {
        var values = [1, 2, 3]
        let binding = Binding(get: { values }, set: { values = $0 })
        for element in binding {
            element.wrappedValue *= 10
        }
        #expect(values == [10, 20, 30])
        binding[1].wrappedValue = 5
        #expect(values == [10, 5, 30])
        #expect(binding.count == 3)
        #expect(binding.reversed().map(\.wrappedValue) == [30, 5, 10])
    }

    @Test("A binding to a removed element keeps its last value and ignores writes")
    func removedElement() {
        var values = ["a", "b", "c"]
        let binding = Binding(get: { values }, set: { values = $0 })
        let last = binding[2]
        values.removeLast()
        #expect(last.wrappedValue == "c")
        last.wrappedValue = "z"
        #expect(values == ["a", "b"])
    }

    @Test("Bindings to identifiable values are identifiable")
    func identifiable() {
        let item = Binding.constant(Item(id: 7, title: "Tea"))
        #expect(item.id == 7)
        #expect(item.title.wrappedValue == "Tea")
    }
}
