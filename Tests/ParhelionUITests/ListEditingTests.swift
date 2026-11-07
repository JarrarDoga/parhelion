import Foundation
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test", screenSize: CGSize(width: 320, height: 640), safeAreaInsets: EdgeInsets())

/// A list of names whose editing the test controls through `mode`.
private struct Queue: View {
    @State var names = ["Ant", "Bee", "Cat", "Dog"]
    @State var mode = EditMode.inactive
    var allowMove = true
    var allowDelete = true

    var body: some View {
        VStack {
            Text(names.joined(separator: ","))
            Button("Toggle") { mode = mode.isEditing ? .inactive : .active }
            List {
                ForEach(names, id: \.self) { name in
                    Text(name)
                }
                .onMove(perform: allowMove ? { names.move(fromOffsets: $0, toOffset: $1) } : nil)
                .onDelete(perform: allowDelete ? { names.remove(atOffsets: $0) } : nil)
            }
            .environment(\.editMode, $mode)
        }
    }
}

extension Array {
    /// Moves elements the way SwiftUI's `move(fromOffsets:toOffset:)` does.
    fileprivate mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { self[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.reversed() { remove(at: index) }
        insert(contentsOf: moved, at: destination - before)
    }

    fileprivate mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.reversed() { remove(at: index) }
    }
}

@MainActor
@Suite("List editing")
struct ListEditingTests {
    private func names(_ host: ViewHost) -> String {
        host.root.allNodes.first { $0.kind == "Text" }?.text ?? ""
    }

    private func edit(_ host: ViewHost) throws {
        try host.tap("Queue/VStack/1/Button")
    }

    @Test("Outside edit mode the rows have no controls")
    func inactive() {
        let host = ViewHost(Queue(), device: screen)
        #expect(host.root.allNodes.filter { $0.kind == "Image" }.isEmpty)
        #expect(host.root.allNodes.filter { $0.kind == "HStack" }.isEmpty)
    }

    @Test("In edit mode each row gets a delete button and a reorder handle")
    func outline() throws {
        let host = ViewHost(Queue(names: ["Ant", "Bee"]), device: screen)
        try edit(host)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(
            list.outline()
                == """
                List contentOffset=0, 0 contentSize=320 × 124
                └─ Section
                   ├─ HStack listRow spacing=12
                   │  ├─ Button accessibilityLabel=Delete
                   │  │  └─ Image foregroundStyle=red systemName=minus.circle.fill
                   │  ├─ Text "Ant"
                   │  ├─ Spacer
                   │  └─ Image accessibilityLabel=Reorder foregroundStyle=secondary systemName=line.3.horizontal
                   └─ HStack listRow spacing=12
                      ├─ Button accessibilityLabel=Delete
                      │  └─ Image foregroundStyle=red systemName=minus.circle.fill
                      ├─ Text "Bee"
                      ├─ Spacer
                      └─ Image accessibilityLabel=Reorder foregroundStyle=secondary systemName=line.3.horizontal
                """)
    }

    @Test("Only the handlers that are set add controls")
    func partial() throws {
        let moveOnly = ViewHost(Queue(allowDelete: false), device: screen)
        try edit(moveOnly)
        #expect(moveOnly.root.allNodes.filter { $0.kind == "Button" }.count == 1)
        #expect(moveOnly.root.allNodes.filter { $0.kind == "Image" }.count == 4)
        let deleteOnly = ViewHost(Queue(allowMove: false), device: screen)
        try edit(deleteOnly)
        #expect(deleteOnly.root.allNodes.filter { $0.kind == "Button" }.count == 5)
        let images = deleteOnly.root.allNodes.compactMap { $0.attributes["systemName"] }
        #expect(!images.contains("line.3.horizontal"))
    }

    @Test("Edit mode turns on, a row is dragged to a new position, a row is deleted")
    func dragAndDelete() throws {
        let host = ViewHost(Queue(), device: screen)
        #expect(names(host) == "Ant,Bee,Cat,Dog")
        try edit(host)

        // Drag Ant's handle down onto the third row.
        let handles = host.root.allNodes.filter {
            $0.attributes["systemName"] == "line.3.horizontal"
        }
        #expect(handles.count == 4)
        let start = try #require(handles[0].frame).center
        let third = try #require(handles[2].frame).center
        host.drag(from: start, to: CGPoint(x: start.x, y: third.y))
        #expect(names(host) == "Bee,Cat,Ant,Dog")

        // Drag Dog's handle up above the first row.
        let again = host.root.allNodes.filter { $0.attributes["systemName"] == "line.3.horizontal" }
        let dog = try #require(again[3].frame).center
        host.drag(from: dog, to: CGPoint(x: dog.x, y: 1))
        #expect(names(host) == "Dog,Bee,Cat,Ant")

        // Delete Cat: the minus reveals Delete, and Delete deletes.
        let minus = host.root.allNodes.filter { $0.attributes["systemName"] == "minus.circle.fill" }
        try host.tap(at: try #require(minus[2].frame).center)
        let confirm = try #require(host.root.allNodes.first { $0.text == "Delete" })
        #expect(names(host) == "Dog,Bee,Cat,Ant")
        try host.tap(at: try #require(confirm.frame).center)
        #expect(names(host) == "Dog,Bee,Ant")
    }

    @Test("A press on a handle that moves and is released reorders, instead of scrolling")
    func pointerDrag() throws {
        let host = ViewHost(Queue(), device: screen)
        try edit(host)
        let handles = host.root.allNodes.filter {
            $0.attributes["systemName"] == "line.3.horizontal"
        }
        let start = try #require(handles[1].frame).center
        let end = try #require(handles[3].frame).center
        host.pointerDown(at: start)
        host.pointerMoved(to: CGPoint(x: start.x, y: start.y + 30))
        host.pointerMoved(to: end)
        #expect(names(host) == "Ant,Bee,Cat,Dog")
        host.pointerUp(at: end)
        #expect(names(host) == "Ant,Cat,Dog,Bee")
    }

    @Test("A handle drag in a list with a tap gesture reorders and does not tap")
    func handleUnderGesture() throws {
        let taps = TapCount()
        let host = ViewHost(TappableQueue(taps: taps), device: screen)
        try host.tapButton(labeled: "Edit")
        #expect(taps.count == 0)
        let handles = host.root.allNodes.filter {
            $0.attributes["systemName"] == "line.3.horizontal"
        }
        let start = try #require(handles[0].frame).center
        let end = try #require(handles[2].frame).center
        host.pointerDown(at: start)
        host.pointerMoved(to: CGPoint(x: start.x, y: start.y + 30))
        host.pointerMoved(to: end)
        host.pointerUp(at: end)
        host.advanceTime(by: 1)
        #expect(names(host) == "Bee,Cat,Ant")
        #expect(taps.count == 0)
    }

    @Test("A ForEach with onDelete can still be scrolled to by identifier")
    func scrollToEditable() throws {
        let host = ViewHost(
            ScrollViewReader { proxy in
                VStack {
                    Button("Bottom") { proxy.scrollTo(39, anchor: .top) }
                    List {
                        ForEach(0..<40, id: \.self) { Text("Row \($0)") }
                            .onDelete { _ in }
                    }
                }
            },
            device: screen)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(host.scrollOffset(of: list.id) == .zero)
        try host.tapButton(labeled: "Bottom")
        host.advanceTime(by: 1)
        #expect((host.scrollOffset(of: list.id)?.y ?? 0) > 0)
    }

    @Test("A drop on the dragged row moves nothing")
    func dropOnSelf() throws {
        let host = ViewHost(Queue(), device: screen)
        try edit(host)
        let handle = try #require(
            host.root.allNodes.first { $0.attributes["systemName"] == "line.3.horizontal" })
        let center = try #require(handle.frame).center
        host.drag(from: center, to: CGPoint(x: center.x, y: center.y + 3))
        #expect(names(host) == "Ant,Bee,Cat,Dog")
    }

    @Test("The minus button shows Delete, and tapping it again hides it")
    func reveal() throws {
        let host = ViewHost(Queue(), device: screen)
        try edit(host)
        let minus = try #require(
            host.root.allNodes.first { $0.attributes["systemName"] == "minus.circle.fill" })
        let button = try #require(host.root.allNodes.first { $0.children.contains(minus) })
        try host.tap(button.id)
        #expect(host.root.allNodes.contains { $0.text == "Delete" })
        try host.tap(button.id)
        #expect(!host.root.allNodes.contains { $0.text == "Delete" })
    }

    @Test("Leaving edit mode removes the controls")
    func leaving() throws {
        let host = ViewHost(Queue(), device: screen)
        try edit(host)
        try edit(host)
        #expect(host.root.allNodes.filter { $0.kind == "Image" }.isEmpty)
    }

    @Test("moveDisabled and deleteDisabled leave a row without that control")
    func disabled() throws {
        let host = ViewHost(
            DisabledRows(), device: screen)
        try host.tapButton(labeled: "Edit")
        let images = host.root.allNodes.compactMap { $0.attributes["systemName"] }
        #expect(images == ["minus.circle.fill", "line.3.horizontal"])
    }

    @Test("Rows outside a list are unchanged")
    func outsideList() throws {
        let host = ViewHost(
            VStack {
                ForEach(["a", "b"], id: \.self) { Text($0) }
                    .onMove { _, _ in }
                    .onDelete { _ in }
            }
            .environment(\.editMode, .constant(.active)),
            device: screen)
        #expect(host.root.allNodes.filter { $0.kind == "Text" }.count == 2)
        #expect(host.root.allNodes.filter { $0.kind == "Image" }.isEmpty)
    }

    @Test("EditButton, moveDisabled, and deleteDisabled in the tree")
    func outlineOfControls() throws {
        let button = ViewHost(WithEditButton(), device: screen)
        #expect(
            button.root.outline()
                == """
                Root
                └─ Button
                   └─ Text "Edit"
                """)
        let rows = ViewHost(DisabledRows(), device: screen)
        try rows.tapButton(labeled: "Edit")
        let list = try #require(rows.root.allNodes.first { $0.kind == "List" })
        #expect(
            list.outline()
                == """
                List contentOffset=0, 0 contentSize=320 × 124
                └─ Section
                   ├─ HStack listRow spacing=12
                   │  ├─ Button accessibilityLabel=Delete
                   │  │  └─ Image foregroundStyle=red systemName=minus.circle.fill
                   │  ├─ Text "a" moveDisabled=true
                   │  └─ Spacer
                   └─ HStack listRow spacing=12
                      ├─ Text "b" deleteDisabled=true
                      ├─ Spacer
                      └─ Image accessibilityLabel=Reorder foregroundStyle=secondary systemName=line.3.horizontal
                """)
    }

    @Test("EditButton turns edit mode on and off")
    func editButton() throws {
        let host = ViewHost(WithEditButton(), device: screen)
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" })
        #expect(button.label == "Edit")
        try host.tap(button.id)
        #expect(host.root.allNodes.first { $0.kind == "Button" }?.label == "Done")
        try host.tap(button.id)
        #expect(host.root.allNodes.first { $0.kind == "Button" }?.label == "Edit")
    }
}

private struct DisabledRows: View {
    @State var mode = EditMode.inactive

    var body: some View {
        VStack {
            Button("Edit") { mode = .active }
            List {
                ForEach(["a"], id: \.self) { Text($0).moveDisabled(true) }
                    .onMove { _, _ in }
                    .onDelete { _ in }
                ForEach(["b"], id: \.self) { Text($0).deleteDisabled(true) }
                    .onMove { _, _ in }
                    .onDelete { _ in }
            }
            .environment(\.editMode, $mode)
        }
    }
}

@MainActor
private final class TapCount {
    var count = 0
}

private struct TappableQueue: View {
    let taps: TapCount
    @State var names = ["Ant", "Bee", "Cat"]
    @State var mode = EditMode.inactive

    var body: some View {
        VStack {
            Text(names.joined(separator: ","))
            Button("Edit") { mode = .active }
            List {
                ForEach(names, id: \.self) { Text($0) }
                    .onMove { names.move(fromOffsets: $0, toOffset: $1) }
            }
            .onTapGesture { taps.count += 1 }
            .environment(\.editMode, $mode)
        }
    }
}

private struct WithEditButton: View {
    @State var mode = EditMode.inactive

    var body: some View {
        EditButton().environment(\.editMode, $mode)
    }
}

extension CGRect {
    fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
