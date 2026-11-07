import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe-area insets. List rows are 268 points
/// wide, from x = 16, and 52 points tall.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets()
)

/// Where a test list records what ran.
@MainActor
private final class Log {
    var events: [String] = []
}

@MainActor
private func songList(
    _ log: Log, trailingFullSwipe: Bool = true, rowTap: Bool = false
) -> some View {
    List {
        Text("One")
            .swipeActions(edge: .trailing, allowsFullSwipe: trailingFullSwipe) {
                Button("Delete", role: .destructive) { log.events.append("delete") }
                Button("Flag") { log.events.append("flag") }.tint(.orange)
            }
            .swipeActions(edge: .leading) {
                Button("Queue") { log.events.append("queue") }.tint(.blue)
            }
        if rowTap {
            Button("Two") { log.events.append("row two") }
                .swipeActions { Button("Remove") { log.events.append("remove") } }
        } else {
            Text("Two")
                .swipeActions { Button("Remove") { log.events.append("remove") } }
        }
    }
}

/// The y of the middle of the first row, and of the second.
private let firstRow: CGFloat = 26
private let secondRow: CGFloat = 78

@MainActor
private func swipe(_ host: ViewHost, row y: CGFloat, by distance: CGFloat) {
    let from = distance < 0 ? 270 : 40
    host.drag(from: CGPoint(x: CGFloat(from), y: y), to: CGPoint(x: CGFloat(from) + distance, y: y))
}

@MainActor
@Suite("swipeActions", .serialized)
struct SwipeActionsTests {
    @Test("A row records its actions in an overlay, and its edges")
    func outline() {
        let host = ViewHost(songList(Log()), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=300 × 124
                   └─ Section
                      ├─ Text "One" overlay(alignment: trailing) swipeClip overlay(alignment: leading) listRow swipeActions=trailing,leading
                      │  ├─ Overlay
                      │  │  └─ SwipeActions edge=trailing
                      │  │     ├─ Button role=destructive
                      │  │     │  └─ Text "Delete" font=body.medium
                      │  │     └─ Button tint=orange
                      │  │        └─ Text "Flag" font=body.medium
                      │  └─ Overlay
                      │     └─ SwipeActions edge=leading
                      │        └─ Button tint=blue
                      │           └─ Text "Queue" font=body.medium
                      └─ Text "Two" overlay(alignment: trailing) swipeClip listRow swipeActions=trailing
                         └─ Overlay
                            └─ SwipeActions edge=trailing
                               └─ Button
                                  └─ Text "Remove" font=body.medium
                """)
    }

    @Test("allowsFullSwipe: false is recorded")
    func noFullSwipeOutline() {
        let host = ViewHost(songList(Log(), trailingFullSwipe: false), device: screen)
        let strips = host.root.allNodes.filter { $0.kind == "SwipeActions" }
        #expect(strips.map { $0.attributes["allowsFullSwipe"] } == ["false", nil, nil])
    }

    @Test("Outside a list, swipeActions changes nothing")
    func outsideList() {
        let host = ViewHost(
            VStack {
                Text("One").swipeActions { Button("Delete") {} }
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   └─ Text "One"
                """)
    }

    @Test("Actions at rest are laid out beside the row and cannot be pressed")
    func atRest() throws {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
        // The actions are past the cell's edge, where a tap finds nothing.
        #expect(throws: InteractionError.self) { try host.tap(at: CGPoint(x: 292, y: firstRow)) }
        #expect(throws: InteractionError.self) { try host.tap(at: CGPoint(x: 8, y: firstRow)) }
        #expect(log.events.isEmpty)
    }

    @Test("Swiping a row left reveals its trailing actions, the first at the edge")
    func revealTrailing() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: -100)
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        // Delete is 84.29 wide, Flag 74, with 8 points between and around.
        let open = try #require(Double(row.attributes["swipeOffset"] ?? ""))
        #expect(abs(open + 174.29) < 0.01)
        #expect(abs((row.frame?.minX ?? 0) - (32 - 174.29)) < 0.01)
        let delete = try #require(host.root.allNodes.first { $0.text == "Delete" })
        let buttons = host.root.allNodes.filter { $0.kind == "Button" }
        let deleteButton = try #require(buttons.first { $0.label == "Delete" })
        let flagButton = try #require(buttons.first { $0.label == "Flag" })
        #expect(deleteButton.frame?.maxX == 284)
        #expect(flagButton.frame?.maxX == (deleteButton.frame?.minX ?? 0) - 8)
        #expect(deleteButton.frame?.height == 52)
        #expect(delete.frame != nil)
        // The row's cell does not move.
        #expect(row.listRowFrame == CGRect(x: 16, y: 0, width: 268, height: 52))
    }

    @Test("Swiping right reveals the leading actions")
    func revealLeading() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: 100)
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        let open = try #require(Double(row.attributes["swipeOffset"] ?? ""))
        #expect(open > 0)
        let queue = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Queue" })
        #expect(queue.frame?.minX == 16)
    }

    @Test("A short swipe springs back")
    func shortSwipe() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: -30)
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
        #expect(row.frame?.minX == 32)
    }

    @Test("A row with no actions on a side does not swipe that way")
    func wrongSide() throws {
        let host = ViewHost(songList(Log()), device: screen)
        // The second row has only trailing actions.
        swipe(host, row: secondRow, by: 100)
        let row = try #require(host.root.allNodes.first { $0.text == "Two" })
        #expect(row.attributes["swipeOffset"] == nil)
    }

    @Test("Tapping a revealed action runs it and closes the row")
    func tapAction() throws {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        swipe(host, row: firstRow, by: -100)
        try host.tapButton(labeled: "Flag")
        #expect(log.events == ["flag"])
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
        #expect(row.frame?.minX == 32)
    }

    @Test("A revealed action responds to a tap at its position")
    func tapActionAtPoint() throws {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        swipe(host, row: firstRow, by: -100)
        let delete = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Delete" }?.frame)
        try host.tap(at: CGPoint(x: delete.midX, y: delete.midY))
        #expect(log.events == ["delete"])
    }

    @Test("Pressing a revealed action with the pointer taps it on release")
    func pointerAction() throws {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        swipe(host, row: firstRow, by: 100)
        let queue = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Queue" }?.frame)
        let point = CGPoint(x: queue.midX, y: queue.midY)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(log.events == ["queue"])
    }

    @Test("A full swipe runs the first action and closes the row")
    func fullSwipe() throws {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        swipe(host, row: firstRow, by: -230)
        // The first action is Delete, the one at the edge, not Flag.
        #expect(log.events == ["delete"])
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
    }

    @Test("A full swipe to the right runs the first leading action")
    func fullSwipeLeading() {
        let log = Log()
        let host = ViewHost(songList(log), device: screen)
        swipe(host, row: firstRow, by: 230)
        #expect(log.events == ["queue"])
    }

    @Test("While a swipe is past the threshold, the first action fills the space")
    func armed() throws {
        let host = ViewHost(songList(Log()), device: screen)
        host.pointerDown(at: CGPoint(x: 270, y: firstRow))
        host.pointerMoved(to: CGPoint(x: 250, y: firstRow))
        host.pointerMoved(to: CGPoint(x: 30, y: firstRow))
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == "-240")
        let buttons = host.root.allNodes.filter { $0.kind == "Button" }
        let delete = try #require(buttons.first { $0.label == "Delete" }?.frame)
        #expect(delete == CGRect(x: 52, y: 0, width: 232, height: 52))
        // The others are out of the way.
        let flag = try #require(buttons.first { $0.label == "Flag" }?.frame)
        #expect(flag.minX >= 300)
        host.pointerUp(at: CGPoint(x: 30, y: firstRow))
    }

    @Test("Without a full swipe, the row stops at its actions")
    func noFullSwipe() throws {
        let log = Log()
        let host = ViewHost(songList(log, trailingFullSwipe: false), device: screen)
        swipe(host, row: firstRow, by: -230)
        #expect(log.events.isEmpty)
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        let open = try #require(Double(row.attributes["swipeOffset"] ?? ""))
        #expect(abs(open + 174.29) < 0.01)
    }

    @Test("A press on an open row closes it and does nothing else")
    func tapOpenRow() throws {
        let log = Log()
        let host = ViewHost(songList(log, rowTap: true), device: screen)
        swipe(host, row: secondRow, by: -100)
        var row = try #require(host.root.allNodes.first { $0.label == "Two" })
        #expect(row.attributes["swipeOffset"] != nil)
        // The second row's button is under the finger, but the press only closes.
        host.pointerDown(at: CGPoint(x: 100, y: secondRow))
        host.pointerUp(at: CGPoint(x: 100, y: secondRow))
        row = try #require(host.root.allNodes.first { $0.label == "Two" })
        #expect(row.attributes["swipeOffset"] == nil)
        #expect(log.events.isEmpty)
        // Closed, the row taps again.
        try host.tapButton(labeled: "Two")
        #expect(log.events == ["row two"])
    }

    @Test("A drag gesture in a row keeps the press, so the row does not swipe")
    func rowDragGestureWins() throws {
        let log = Log()
        let host = ViewHost(
            List {
                Text("One")
                    .frame(maxWidth: .infinity)
                    .gesture(DragGesture().onChanged { _ in log.events.append("drag") })
                    .swipeActions { Button("Delete") { log.events.append("delete") } }
            }, device: screen)
        // Inside the row content, which is inset from the cell.
        host.drag(from: CGPoint(x: 250, y: firstRow), to: CGPoint(x: 150, y: firstRow))
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
        #expect(log.events.contains("drag"))
        #expect(!log.events.contains("delete"))
    }

    @Test("A tap gesture on a row lets the row swipe, and does not fire")
    func rowTapGestureSwipes() throws {
        let log = Log()
        let host = ViewHost(
            List {
                Text("One")
                    .frame(maxWidth: .infinity)
                    .onTapGesture { log.events.append("tap") }
                    .swipeActions { Button("Delete") { log.events.append("delete") } }
            }, device: screen)
        // Inside the row content, which is inset from the cell.
        host.drag(from: CGPoint(x: 250, y: firstRow), to: CGPoint(x: 150, y: firstRow))
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] != nil)
        #expect(log.events.isEmpty)
    }

    @Test("Opening a second row closes the first")
    func onlyOneOpen() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: -100)
        swipe(host, row: secondRow, by: -100)
        let one = try #require(host.root.allNodes.first { $0.text == "One" })
        let two = try #require(host.root.allNodes.first { $0.text == "Two" })
        #expect(one.attributes["swipeOffset"] == nil)
        #expect(two.attributes["swipeOffset"] != nil)
    }

    @Test("Dragging an open row back closes it")
    func dragClosed() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: -100)
        host.drag(from: CGPoint(x: 100, y: firstRow), to: CGPoint(x: 200, y: firstRow))
        let row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
    }

    @Test("A swipe survives an update, and the offset goes with a removed row")
    func state() throws {
        let host = ViewHost(StateRows(), device: screen)
        let cell = try #require(host.root.allNodes.first { $0.text == "One" }?.listRowFrame)
        swipe(host, row: cell.midY, by: -100)
        try host.tapButton(labeled: "Count")
        var row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] != nil)
        try host.tapButton(labeled: "Hide")
        #expect(host.root.allNodes.first { $0.text == "One" } == nil)
        try host.tapButton(labeled: "Show")
        row = try #require(host.root.allNodes.first { $0.text == "One" })
        #expect(row.attributes["swipeOffset"] == nil)
    }

    @Test("A mostly vertical drag still scrolls the list")
    func scrolls() throws {
        let host = ViewHost(
            List(0..<20) { index in
                Text("Row \(index)").swipeActions { Button("Go") {} }
            }, device: screen)
        host.drag(from: CGPoint(x: 150, y: 300), to: CGPoint(x: 140, y: 100))
        let list = host.root.children[0]
        #expect((host.scrollOffset(of: list.id)?.y ?? 0) > 100)
        #expect(host.root.allNodes.allSatisfy { $0.attributes["swipeOffset"] == nil })
    }

    @Test("The revealed actions are drawn in their tints, and the row is clipped to its cell")
    func rendering() throws {
        let host = ViewHost(songList(Log()), device: screen)
        swipe(host, row: firstRow, by: -100)
        // The row has settled.
        host.advanceTime(by: 2)
        let frame = host.render(scale: 1)
        let buttons = host.root.allNodes.filter { $0.kind == "Button" }
        let delete = try #require(buttons.first { $0.label == "Delete" }?.frame)
        let flag = try #require(buttons.first { $0.label == "Flag" }?.frame)
        func color(_ point: CGPoint) -> [UInt8] {
            let c = frame.color(at: point)
            return [c.red, c.green, c.blue, c.alpha]
        }
        // Destructive is red and a tint is its color, beside the label.
        #expect(color(CGPoint(x: delete.minX + 3, y: delete.midY)) == [255, 56, 60, 255])
        #expect(color(CGPoint(x: flag.minX + 3, y: flag.midY)) == [255, 141, 40, 255])
        // The row's text slid out of the cell, to the left of it, and is not drawn there.
        #expect(color(CGPoint(x: 8, y: firstRow)) == [242, 242, 247, 255])
    }
}

private struct StateRows: View {
    @State private var count = 0
    @State private var hidden = false

    var body: some View {
        VStack {
            Button("Count") { count += 1 }
            Button(hidden ? "Show" : "Hide") { hidden.toggle() }
            List {
                if !hidden {
                    Text("One").swipeActions { Button("Go") {} }
                }
            }
        }
    }
}
