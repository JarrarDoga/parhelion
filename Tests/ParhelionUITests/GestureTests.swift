import Foundation
import Testing

@testable import ParhelionUI

/// A 200 × 200 screen with no safe-area insets.
private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

/// What the views in these tests did, in order.
@MainActor
private final class Log {
    var lines: [String] = []
}

/// A 40-point square at the center of the screen, which only a tap gesture
/// responds to.
private struct TapTarget: View {
    let log: Log
    var count = 1

    var body: some View {
        Color.red.frame(width: 40, height: 40)
            .onTapGesture(count: count) { log.lines.append("tap") }
    }
}

private struct SpatialTarget: View {
    let log: Log

    var body: some View {
        Color.red.frame(width: 40, height: 40)
            .onTapGesture { location in log.lines.append("tap \(location.x),\(location.y)") }
    }
}

private struct LongPressTarget: View {
    let log: Log
    var duration = 0.5

    var body: some View {
        Color.red.frame(width: 40, height: 40)
            .onLongPressGesture(
                minimumDuration: duration,
                perform: { log.lines.append("long press") },
                onPressingChanged: { log.lines.append("pressing \($0)") })
    }
}

/// A thumb that follows a drag one to one.
private struct Thumb: View {
    let log: Log
    @State private var offset = CGSize.zero
    @State private var start = CGSize.zero
    @GestureState private var isDragging = false

    var body: some View {
        Color.blue
            .frame(width: 30, height: 30)
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        offset = CGSize(
                            width: start.width + value.translation.width,
                            height: start.height + value.translation.height)
                    }
                    .onEnded { value in
                        start = offset
                        log.lines.append("ended \(Int(value.translation.width))")
                    }
            )
            .overlay(alignment: .top) {
                Text(isDragging ? "dragging" : "idle")
            }
    }
}

@MainActor
@Suite("Gestures")
struct GestureTests {
    // MARK: Outlines

    @Test("The gesture modifiers show in the outline, in the order they were applied")
    func outline() {
        let log = Log()
        let host = ViewHost(
            VStack {
                Text("a").onTapGesture { log.lines.append("") }
                Text("b").onTapGesture(count: 2) {}
                Text("c").onLongPressGesture(minimumDuration: 1) {}
                Text("d").gesture(DragGesture(minimumDistance: 0))
                Text("e").highPriorityGesture(TapGesture())
                Text("f").simultaneousGesture(LongPressGesture())
                Text("g").gesture(TapGesture(), including: .subviews).padding(4)
                Text("h").gesture(TapGesture()).gesture(DragGesture())
                Text("i").gesture(TapGesture(), isEnabled: false)
                Text("j").gesture(
                    LongPressGesture().sequenced(before: DragGesture()))
            },
            device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "a" onTapGesture
                   ├─ Text "b" onTapGesture(count: 2)
                   ├─ Text "c" onLongPressGesture(minimumDuration: 1)
                   ├─ Text "d" gesture(drag(minimumDistance: 0))
                   ├─ Text "e" highPriorityGesture(tap)
                   ├─ Text "f" simultaneousGesture(longPress)
                   ├─ Text "g" gesture(tap) padding(4)
                   ├─ Text "h" gesture(tap) gesture(drag)
                   ├─ Text "i"
                   └─ Text "j" gesture(sequenced(longPress, drag))
                """)
    }

    // MARK: Taps

    @Test("A tap gesture runs on a tap, and only where the view is")
    func tap() throws {
        let log = Log()
        let host = ViewHost(TapTarget(log: log), device: square)
        try host.tap(at: CGPoint(x: 100, y: 100))
        #expect(log.lines == ["tap"])
        #expect(throws: InteractionError.nothingTappable(at: CGPoint(x: 10, y: 10))) {
            try host.tap(at: CGPoint(x: 10, y: 10))
        }
        #expect(log.lines == ["tap"])
    }

    @Test("A tap that moves too far is not a tap")
    func tapMoved() {
        let log = Log()
        let host = ViewHost(TapTarget(log: log), device: square)
        host.pointerDown(at: CGPoint(x: 90, y: 100))
        host.pointerMoved(to: CGPoint(x: 112, y: 100))
        host.pointerUp(at: CGPoint(x: 112, y: 100))
        #expect(log.lines.isEmpty)
    }

    @Test("A double tap needs two taps close together, in place and in time")
    func doubleTap() {
        let log = Log()
        let host = ViewHost(TapTarget(log: log, count: 2), device: square)
        let point = CGPoint(x: 100, y: 100)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(log.lines.isEmpty)
        host.advanceTime(by: 0.1)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(log.lines == ["tap"])

        // Too slow.
        log.lines = []
        host.advanceTime(by: 1)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        host.advanceTime(by: 0.5)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(log.lines.isEmpty)
    }

    @Test("A tap with a location reports it in the view's coordinates")
    func spatialTap() throws {
        let log = Log()
        let host = ViewHost(SpatialTarget(log: log), device: square)
        try host.tap(at: CGPoint(x: 90, y: 110))
        #expect(log.lines == ["tap 10.0,30.0"])
    }

    @Test("A tap on a button runs the button, not a tap gesture on a view around it")
    func buttonWinsOverParent() throws {
        let log = Log()
        let host = ViewHost(
            VStack { Button("Go") { log.lines.append("button") } }
                .padding(30)
                .onTapGesture { log.lines.append("parent") },
            device: square)
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" })
        let center = CGPoint(x: button.frame!.midX, y: button.frame!.midY)
        try host.tap(at: center)
        #expect(log.lines == ["button"])
        // The padding is part of the parent only.
        try host.tap(at: CGPoint(x: center.x + 40, y: center.y))
        #expect(log.lines == ["button", "parent"])
    }

    @Test("A tap gesture on a button replaces its action; a high priority one wins over a child")
    func gesturePriority() throws {
        let log = Log()
        let host = ViewHost(
            VStack {
                Button("A") { log.lines.append("A button") }
                    .onTapGesture { log.lines.append("A gesture") }
                Button("B") { log.lines.append("B button") }
                    .highPriorityGesture(TapGesture().onEnded { log.lines.append("B high") })
                Button("C") { log.lines.append("C button") }
                    .simultaneousGesture(TapGesture().onEnded { log.lines.append("C both") })
            },
            device: square)
        for label in ["A", "B", "C"] {
            let node = try #require(
                host.root.allNodes.first { $0.kind == "Button" && $0.label == label })
            try host.tap(at: CGPoint(x: node.frame!.midX, y: node.frame!.midY))
        }
        #expect(log.lines == ["A gesture", "B high", "C button", "C both"])
    }

    @Test("A single tap waits for a double tap on the same view to fail")
    func singleWaitsForDouble() {
        let log = Log()
        let host = ViewHost(
            Color.red.frame(width: 40, height: 40)
                .onTapGesture(count: 2) { log.lines.append("double") }
                .onTapGesture { log.lines.append("single") },
            device: square)
        let point = CGPoint(x: 100, y: 100)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(log.lines.isEmpty)
        host.advanceTime(by: 0.5)
        #expect(log.lines == ["single"])

        log.lines = []
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        host.advanceTime(by: 0.1)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        host.advanceTime(by: 0.5)
        #expect(log.lines == ["double"])
    }

    // MARK: Long press

    @Test("A long press runs its action after the minimum duration, while the pointer is down")
    func longPress() {
        let log = Log()
        let host = ViewHost(LongPressTarget(log: log), device: square)
        let point = CGPoint(x: 100, y: 100)
        host.pointerDown(at: point)
        #expect(log.lines == ["pressing true"])
        host.advanceTime(by: 0.4)
        #expect(log.lines == ["pressing true"])
        host.advanceTime(by: 0.2)
        #expect(log.lines == ["pressing true", "pressing false", "long press"])
        host.pointerUp(at: point)
        #expect(log.lines.count == 3)
    }

    @Test("A press released early, or moved away, is not a long press")
    func longPressFails() {
        let log = Log()
        let host = ViewHost(LongPressTarget(log: log), device: square)
        let point = CGPoint(x: 100, y: 100)
        host.pointerDown(at: point)
        host.advanceTime(by: 0.3)
        host.pointerUp(at: point)
        #expect(log.lines == ["pressing true", "pressing false"])

        log.lines = []
        host.pointerDown(at: point)
        host.pointerMoved(to: CGPoint(x: 100, y: 125))
        host.advanceTime(by: 1)
        host.pointerUp(at: CGPoint(x: 100, y: 125))
        #expect(log.lines == ["pressing true", "pressing false"])
    }

    @Test("ViewHost.longPress holds a press for the duration")
    func hostLongPress() throws {
        let log = Log()
        let host = ViewHost(LongPressTarget(log: log, duration: 1), device: square)
        try host.longPress(at: CGPoint(x: 100, y: 100), duration: 0.5)
        #expect(!log.lines.contains("long press"))
        log.lines = []
        try host.longPress(at: CGPoint(x: 100, y: 100), duration: 1.2)
        #expect(log.lines == ["pressing true", "pressing false", "long press"])
        #expect(throws: InteractionError.nothingTappable(at: CGPoint(x: 5, y: 5))) {
            try host.longPress(at: CGPoint(x: 5, y: 5))
        }
    }

    @Test("A long press beats a tap on the same view once it is recognized")
    func longPressBeatsTap() {
        let log = Log()
        let host = ViewHost(
            Color.red.frame(width: 40, height: 40)
                .onTapGesture { log.lines.append("tap") }
                .onLongPressGesture { log.lines.append("long") },
            device: square)
        let point = CGPoint(x: 100, y: 100)
        host.pointerDown(at: point)
        host.advanceTime(by: 0.6)
        host.pointerUp(at: point)
        #expect(log.lines == ["long"])

        // Released early, the long press fails and the tap on the view
        // outside it is recognized.
        log.lines = []
        host.pointerDown(at: point)
        host.advanceTime(by: 0.1)
        host.pointerUp(at: point)
        #expect(log.lines == ["tap"])
    }

    // MARK: Drag

    @Test("A drag moves a thumb one to one with the pointer")
    func dragThumb() throws {
        let log = Log()
        let host = ViewHost(Thumb(log: log), device: square)
        func thumb() -> CGRect { host.root.allNodes.first { $0.kind == "Color" }!.frame! }
        let origin = thumb().origin
        let start = CGPoint(x: origin.x + 15, y: origin.y + 15)
        host.pointerDown(at: start)
        #expect(host.root.allNodes.contains { $0.text == "dragging" })
        for step in 1...5 {
            let point = CGPoint(x: start.x + CGFloat(step) * 7, y: start.y - CGFloat(step) * 3)
            host.advanceTime(by: 0.016)
            host.pointerMoved(to: point)
            #expect(thumb().origin.x == origin.x + CGFloat(step) * 7)
            #expect(thumb().origin.y == origin.y - CGFloat(step) * 3)
        }
        host.pointerUp(at: CGPoint(x: start.x + 35, y: start.y - 15))
        #expect(log.lines == ["ended 35"])
        #expect(host.root.allNodes.contains { $0.text == "idle" })
        #expect(thumb().origin.x == origin.x + 35)

        // A second drag carries on from where the first ended.
        host.drag(from: start, to: CGPoint(x: start.x + 20, y: start.y), duration: 0.3)
        #expect(thumb().origin.x == origin.x + 55)
    }

    @Test("A drag starts after its minimum distance, and reports where it started")
    func dragMinimumDistance() {
        let values = Log()
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .gesture(
                    DragGesture()
                        .onChanged { values.lines.append("changed \($0.translation.width)") }
                        .onEnded {
                            values.lines.append(
                                "ended \($0.translation.width) \($0.location.x) \($0.startLocation.x)"
                            )
                        }),
            device: square)
        host.pointerDown(at: CGPoint(x: 60, y: 100))
        host.pointerMoved(to: CGPoint(x: 66, y: 100))
        #expect(values.lines.isEmpty)
        host.pointerMoved(to: CGPoint(x: 75, y: 100))
        host.pointerMoved(to: CGPoint(x: 90, y: 100))
        host.pointerUp(at: CGPoint(x: 90, y: 100))
        // The location is in the view's own space: the view starts at x = 50.
        #expect(values.lines == ["changed 15.0", "changed 30.0", "ended 30.0 40.0 10.0"])
    }

    @Test("A drag reports its velocity and where it would come to rest")
    func dragVelocity() {
        let velocities = Log()
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded {
                        velocities.lines.append(
                            "\(Int($0.velocity.width)) \(Int($0.predictedEndLocation.x))")
                    }),
            device: square)
        host.drag(from: CGPoint(x: 60, y: 100), to: CGPoint(x: 120, y: 100), duration: 0.3)
        // 60 points in 0.2 s over the last stretch of the drag.
        #expect(velocities.lines.count == 1)
        let parts = velocities.lines[0].split(separator: " ").compactMap { Int($0) }
        #expect(parts[0] > 190 && parts[0] < 210)
        #expect(parts[1] > 70 + 90 && parts[1] < 70 + 110)
    }

    @Test("A drag in the global coordinate space reports screen points")
    func globalSpace() {
        let log = Log()
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global).onEnded {
                        log.lines.append("\($0.location.x)")
                    }),
            device: square)
        host.drag(from: CGPoint(x: 60, y: 100), to: CGPoint(x: 120, y: 100))
        #expect(log.lines == ["120.0"])
    }

    // MARK: Combinations

    @Test("A long press followed by a drag runs the drag after the hold")
    func sequence() {
        let log = Log()
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            switch value {
                            case .first: log.lines.append("first")
                            case .second(_, let drag):
                                log.lines.append(
                                    "second \(drag.map { Int($0.translation.width) } ?? -1)")
                            }
                        }
                        .onEnded { value in
                            if case .second(true, let drag?) = value {
                                log.lines.append("ended \(Int(drag.translation.width))")
                            } else {
                                log.lines.append("ended without drag")
                            }
                        }),
            device: square)
        // Moved before the hold is long enough: nothing.
        host.pointerDown(at: CGPoint(x: 100, y: 100))
        host.advanceTime(by: 0.1)
        host.pointerMoved(to: CGPoint(x: 140, y: 100))
        host.pointerUp(at: CGPoint(x: 140, y: 100))
        #expect(!log.lines.contains { $0.hasPrefix("second") })

        log.lines = []
        host.pointerDown(at: CGPoint(x: 100, y: 100))
        host.advanceTime(by: 0.5)
        host.pointerMoved(to: CGPoint(x: 120, y: 100))
        host.pointerMoved(to: CGPoint(x: 130, y: 100))
        host.pointerUp(at: CGPoint(x: 130, y: 100))
        #expect(log.lines.first == "first")
        #expect(log.lines.contains("second 20"))
        #expect(log.lines.last == "ended 30")

        log.lines = []
        host.pointerDown(at: CGPoint(x: 100, y: 100))
        host.advanceTime(by: 0.5)
        host.pointerUp(at: CGPoint(x: 100, y: 100))
        // A drag with no minimum distance begins as the hold ends.
        #expect(log.lines.last == "ended 0")
    }

    @Test(
        "Simultaneous gestures both report, and exclusive ones leave the second to the first's failure"
    )
    func simultaneousAndExclusive() {
        let log = Log()
        let host = ViewHost(
            VStack {
                Color.red.frame(width: 100, height: 40)
                    .gesture(
                        TapGesture().simultaneously(with: LongPressGesture(minimumDuration: 0.2))
                            .onEnded { value in
                                log.lines.append(
                                    "simul \(value.first != nil) \(value.second ?? false)")
                            })
                Color.blue.frame(width: 100, height: 40)
                    .gesture(
                        DragGesture(minimumDistance: 20).exclusively(before: TapGesture())
                            .onEnded { value in
                                switch value {
                                case .first: log.lines.append("exclusive drag")
                                case .second: log.lines.append("exclusive tap")
                                }
                            })
            },
            device: square)
        let red = host.root.allNodes.first { $0.kind == "Color" }!.frame!
        let blue = host.root.allNodes.last { $0.kind == "Color" }!.frame!
        let redPoint = CGPoint(x: red.midX, y: red.midY)
        host.pointerDown(at: redPoint)
        host.advanceTime(by: 0.1)
        host.pointerUp(at: redPoint)
        host.pointerDown(at: redPoint)
        host.advanceTime(by: 0.3)
        host.pointerUp(at: redPoint)
        // Each press ends the pair once: a tap, and a tap held for the long press.
        #expect(log.lines == ["simul true true", "simul true true"])

        log.lines = []
        let bluePoint = CGPoint(x: blue.midX, y: blue.midY)
        host.pointerDown(at: bluePoint)
        host.pointerUp(at: bluePoint)
        host.drag(from: bluePoint, to: CGPoint(x: bluePoint.x + 40, y: bluePoint.y))
        #expect(log.lines == ["exclusive tap", "exclusive drag"])
    }

    @Test("A custom gesture's body is the gesture it recognizes")
    func customGesture() {
        struct Swipe: Gesture {
            var body: some Gesture<DragGesture.Value> { DragGesture(minimumDistance: 0) }
        }
        let log = Log()
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .gesture(Swipe().onEnded { _ in log.lines.append("swiped") }),
            device: square)
        host.drag(from: CGPoint(x: 80, y: 100), to: CGPoint(x: 120, y: 100))
        #expect(log.lines == ["swiped"])
    }

    // MARK: Masks

    @Test("A gesture's mask decides whether it and the gestures inside it count")
    func masks() throws {
        let log = Log()
        func make(_ mask: GestureMask) -> ViewHost {
            ViewHost(
                Color.red.frame(width: 40, height: 40)
                    .onTapGesture { log.lines.append("inner") }
                    .gesture(TapGesture().onEnded { log.lines.append("outer") }, including: mask),
                device: square)
        }
        let point = CGPoint(x: 100, y: 100)
        try make(.all).tap(at: point)
        #expect(log.lines == ["inner"])
        log.lines = []
        // Without `gesture`, the outer gesture is off and the inner one stays.
        try make(.subviews).tap(at: point)
        #expect(log.lines == ["inner"])
        log.lines = []
        // Without `subviews`, the inner gesture is off.
        try make(.gesture).tap(at: point)
        #expect(log.lines == ["outer"])
        log.lines = []
        try make(.none).tap(at: point)
        #expect(log.lines.isEmpty)
    }

    // MARK: Gestures and scroll views

    /// A horizontal pager of three pages in a vertical scroll view.
    private struct PagerInScroll: View {
        let log: Log
        @State private var page = 0

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(0..<3) { index in
                            Color(red: Double(index) / 2, green: 0.4, blue: 0.8)
                                .frame(width: 200, height: 100)
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                    .offset(x: CGFloat(-page) * 200)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if value.translation.width < -50 { page = min(page + 1, 2) }
                                if value.translation.width > 50 { page = max(page - 1, 0) }
                                log.lines.append("page \(page)")
                            })
                    Color.gray.frame(width: 200, height: 400)
                }
            }
        }
    }

    @Test("A swipe on a pager inside a scroll view turns the page without scrolling")
    func pagerInScrollView() throws {
        let log = Log()
        let host = ViewHost(PagerInScroll(log: log), device: square)
        let scroll = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
        host.drag(from: CGPoint(x: 150, y: 50), to: CGPoint(x: 40, y: 56), duration: 0.2)
        #expect(log.lines == ["page 1"])
        #expect(host.scrollOffset(of: scroll)?.y == 0)
        host.drag(from: CGPoint(x: 150, y: 50), to: CGPoint(x: 40, y: 56), duration: 0.2)
        host.drag(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 150, y: 50), duration: 0.2)
        #expect(log.lines == ["page 1", "page 2", "page 1"])
        #expect(host.scrollOffset(of: scroll)?.y == 0)
        host.advanceTime(by: 1)
        #expect(host.scrollOffset(of: scroll)?.y == 0)
    }

    @Test("A press outside the pager still scrolls the scroll view")
    func scrollOutsideTheGesture() throws {
        let log = Log()
        let host = ViewHost(PagerInScroll(log: log), device: square)
        let scroll = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
        host.drag(from: CGPoint(x: 100, y: 180), to: CGPoint(x: 100, y: 140), duration: 0.3)
        #expect((host.scrollOffset(of: scroll)?.y ?? 0) > 20)
        #expect(log.lines.isEmpty)
    }

    @Test("A gesture on a view around a scroll view yields to it, unless it has priority")
    func scrollWinsOverOuterGesture() throws {
        let log = Log()
        func make(high: Bool) -> ViewHost {
            let drag = DragGesture().onEnded { _ in log.lines.append("outer drag") }
            let scroll = ScrollView { Color.gray.frame(width: 200, height: 600) }
            return ViewHost(
                high ? AnyView(scroll.highPriorityGesture(drag)) : AnyView(scroll.gesture(drag)),
                device: square)
        }
        let normal = make(high: false)
        normal.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 100), duration: 0.3)
        #expect(
            (normal.scrollOffset(
                of: try #require(normal.root.allNodes.first { $0.kind == "ScrollView" }).id)?.y ?? 0)
                > 20)
        #expect(log.lines.isEmpty)

        let high = make(high: true)
        high.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 100), duration: 0.3)
        #expect(
            high.scrollOffset(
                of: try #require(high.root.allNodes.first { $0.kind == "ScrollView" }).id)?.y == 0)
        #expect(log.lines == ["outer drag"])
    }

    @Test("A simultaneous drag and a scroll view both get the press")
    func simultaneousWithScroll() throws {
        let log = Log()
        let host = ViewHost(
            ScrollView {
                Color.gray.frame(width: 200, height: 600)
                    .simultaneousGesture(DragGesture().onEnded { _ in log.lines.append("drag") })
            },
            device: square)
        let scroll = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
        host.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 100), duration: 0.3)
        #expect((host.scrollOffset(of: scroll)?.y ?? 0) > 20)
        #expect(log.lines == ["drag"])
    }

    // MARK: Gesture state across updates

    @Test("A gesture's state goes back when the gesture ends or is taken")
    func gestureStateResets() {
        struct Holder: View {
            @GestureState private var pressing = false
            var body: some View {
                Text(pressing ? "pressing" : "idle")
                    .frame(width: 100, height: 100)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3).updating($pressing) {
                            value, state, _ in
                            state = value
                        })
            }
        }
        let host = ViewHost(Holder(), device: square)
        func label() -> String? { host.root.allNodes.first { $0.kind == "Text" }?.text }
        #expect(label() == "idle")
        host.pointerDown(at: CGPoint(x: 100, y: 100))
        #expect(label() == "pressing")
        host.advanceTime(by: 0.4)
        host.update()
        #expect(label() == "idle")
        host.pointerUp(at: CGPoint(x: 100, y: 100))

        host.pointerDown(at: CGPoint(x: 100, y: 100))
        #expect(label() == "pressing")
        host.pointerUp(at: CGPoint(x: 100, y: 100))
        #expect(label() == "idle")
    }
}
