import Foundation
import Observation
import ParhelionPreview
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

@Observable
private final class Groceries {
    var items = [
        Item(id: 1, title: "Milk"),
        Item(id: 2, title: "Eggs"),
        Item(id: 3, title: "Tea"),
    ]
}

/// Lets a test decide when a task continues.
@MainActor
private final class Latch {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private struct GroceryList: View {
    @Bindable var groceries: Groceries
    let latch: Latch

    var body: some View {
        VStack {
            ForEach($groceries.items) { $item in
                TextField("Item", text: $item.title)
            }
        }
        .task {
            await latch.wait()
            groceries.items.removeFirst()
        }
    }
}

@MainActor
@Suite("Bindings")
struct BindingTests {
    @Test("A binding to an identifiable element follows it when earlier elements go")
    func elementFollowsIdentity() {
        var items = [
            Item(id: 1, title: "Milk"), Item(id: 2, title: "Eggs"), Item(id: 3, title: "Tea"),
        ]
        let binding = Binding(get: { items }, set: { items = $0 })
        let eggs = binding[1]
        items.removeFirst()
        #expect(eggs.wrappedValue.title == "Eggs")
        eggs.wrappedValue.title = "Brown eggs"
        #expect(items.map(\.title) == ["Brown eggs", "Tea"])

        items.removeFirst()
        #expect(eggs.wrappedValue.title == "Brown eggs")
        eggs.wrappedValue.title = "Gone"
        #expect(items.map(\.title) == ["Tea"])
    }

    @Test("A preview session applies typing after a task's change to the updated rows")
    func sessionInputAfterTaskRemovedRow() async throws {
        let groceries = Groceries()
        let latch = Latch()
        // Small, so that frames fit in the socket while nothing reads them.
        let device = Device(
            name: "Test", screenSize: CGSize(width: 80, height: 120), safeAreaInsets: EdgeInsets())
        let host = ViewHost(GroceryList(groceries: groceries, latch: latch), device: device)
        let eggs = try #require(
            host.root.allNodes.first { $0.kind == "TextField" && $0.attributes["value"] == "Eggs" })
        try host.focus(eggs.id)
        while !latch.isWaiting { await Task.yield() }
        latch.open()
        while groceries.items.count == 3 { await Task.yield() }

        let (appEnd, hostEnd) = try PreviewChannel.pair()
        try hostEnd.send(.text("!"))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Groceries").run()
        #expect(groceries.items.map(\.title) == ["Eggs!", "Tea"])
    }

    @Test("A row's binding from ForEach with an id key path follows its element")
    func keyedRowFollowsIdentity() throws {
        var names = ["Ada", "Grace", "Hedy"]
        let binding = Binding(get: { names }, set: { names = $0 })
        var rows: [Binding<String>] = []
        let each = ForEach(binding, id: \.self) { name in
            rows.append(name)
            return Text(name.wrappedValue)
        }
        for element in each.data { _ = each.content(element) }
        names.removeFirst()
        #expect(rows[1].wrappedValue == "Grace")
        rows[2].wrappedValue = "Hedy Lamarr"
        #expect(names == ["Grace", "Hedy Lamarr"])
    }

    @Test("Input that arrives after a task removed an earlier row reaches its own row")
    func inputAfterTaskRemovedRow() async throws {
        let groceries = Groceries()
        let latch = Latch()
        let host = ViewHost(GroceryList(groceries: groceries, latch: latch))
        let eggs = try #require(
            host.root.allNodes.first { $0.kind == "TextField" && $0.attributes["value"] == "Eggs" })
        try host.focus(eggs.id)
        while !latch.isWaiting { await Task.yield() }

        latch.open()
        while groceries.items.count == 3 { await Task.yield() }
        // The task changed the model, and the tree has not been updated yet.
        #expect(host.needsUpdate)
        host.typeText("!")
        #expect(groceries.items.map(\.title) == ["Eggs!", "Tea"])
        #expect(host.nodes(withText: "Eggs!").isEmpty)
        #expect(host.root.node(withID: eggs.id)?.attributes["value"] == "Eggs!")
    }

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
