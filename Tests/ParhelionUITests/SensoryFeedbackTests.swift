import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 300),
    safeAreaInsets: EdgeInsets()
)

/// A button that changes the trigger of a `selection` feedback.
private struct SelectionScreen: View {
    @State private var choice = 0

    var body: some View {
        Button("Next") { choice += 1 }
            .sensoryFeedback(.selection, trigger: choice)
    }
}

/// Feedback that depends on the values: a decrease or an increase, and none
/// at all when the count reaches 3.
private struct CountScreen: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Button("Up") { count += 1 }
            Button("Down") { count -= 1 }
        }
        .sensoryFeedback(trigger: count) { old, new in
            if new == 3 { return nil }
            return new > old ? .increase : .decrease
        }
    }
}

/// Feedback only when the count is even.
private struct ConditionScreen: View {
    @State private var count = 0

    var body: some View {
        Button("Tick") { count += 1 }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.5), trigger: count) { _, new in
                new.isMultiple(of: 2)
            }
    }
}

/// Text that shows the Reduce Motion setting it reads.
private struct MotionLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(reduceMotion ? "calm" : "lively")
    }
}

@MainActor
@Suite("sensoryFeedback and Reduce Motion")
struct SensoryFeedbackTests {
    @Test("A changed trigger leaves one selection event, and the tree lists it")
    func selection() throws {
        let host = ViewHost(SelectionScreen(), device: square)
        #expect(host.sensoryFeedbackEvents.isEmpty)
        #expect(
            host.root.outline()
                == "Root\n└─ Button sensoryFeedback=selection\n   └─ Text \"Next\"")

        try host.tapButton(labeled: "Next")
        let events = host.sensoryFeedbackEvents
        #expect(events.map(\.feedback) == ["selection"])
        #expect(events.first?.sequence == 1)
        #expect(events.first?.node == NodeID("SelectionScreen/Button"))
        #expect(
            host.root.outline()
                == """
                Root sensoryFeedback=selection
                └─ Button sensoryFeedback=selection
                   └─ Text "Next"
                """)
        #expect(host.root.attributes["sensoryFeedback"] == "selection")

        try host.tapButton(labeled: "Next")
        #expect(host.sensoryFeedbackEvents.map(\.sequence) == [1, 2])
    }

    @Test("The first value is not a change, and an update that changes nothing plays nothing")
    func firstValue() {
        let host = ViewHost(SelectionScreen(), device: square)
        host.update()
        host.advanceTime(by: 1)
        #expect(host.sensoryFeedbackEvents.isEmpty)
        #expect(host.root.attributes["sensoryFeedback"] == nil)
    }

    @Test("The closure form chooses the feedback from the old and new values")
    func closureForm() throws {
        let host = ViewHost(CountScreen(), device: square)
        try host.tapButton(labeled: "Up")
        try host.tapButton(labeled: "Up")
        try host.tapButton(labeled: "Up")  // 3: the closure returns nil.
        try host.tapButton(labeled: "Down")
        #expect(host.sensoryFeedbackEvents.map(\.feedback) == ["increase", "increase", "decrease"])
        #expect(host.root.attributes["sensoryFeedback"] == "increase,increase,decrease")
        #expect(
            host.root.outline().contains("VStack sensoryFeedback=dynamic"))
    }

    @Test("The condition form plays only when the condition holds, and impacts name their strength")
    func conditionForm() throws {
        let host = ViewHost(ConditionScreen(), device: square)
        for _ in 0..<4 { try host.tapButton(labeled: "Tick") }
        #expect(
            host.sensoryFeedbackEvents.map(\.feedback) == [
                "impact.heavy x0.5", "impact.heavy x0.5",
            ])
    }

    @Test("Feedback names follow SwiftUI's")
    func names() {
        #expect(SensoryFeedback.success.name == "success")
        #expect(SensoryFeedback.impact.name == "impact")
        #expect(SensoryFeedback.impact(weight: .light).name == "impact.light")
        #expect(
            SensoryFeedback.impact(flexibility: .soft, intensity: 0.25).name == "impact.soft x0.25")
    }

    @Test("The log keeps the last 50 events, and the root lists the newest ten")
    func capacity() throws {
        let host = ViewHost(SelectionScreen(), device: square)
        for _ in 0..<60 { try host.tapButton(labeled: "Next") }
        #expect(host.sensoryFeedbackEvents.count == 50)
        #expect(host.sensoryFeedbackEvents.first?.sequence == 11)
        #expect(host.sensoryFeedbackEvents.last?.sequence == 60)
        let listed = host.root.attributes["sensoryFeedback"]?.split(separator: ",")
        #expect(listed?.count == 10)
    }

    @Test("Clearing forgets the events and the root's list")
    func clearing() throws {
        let host = ViewHost(SelectionScreen(), device: square)
        try host.tapButton(labeled: "Next")
        host.clearSensoryFeedback()
        #expect(host.sensoryFeedbackEvents.isEmpty)
        #expect(host.root.attributes["sensoryFeedback"] == nil)
        try host.tapButton(labeled: "Next")
        #expect(host.sensoryFeedbackEvents.map(\.sequence) == [2])
    }

    @Test("The sensoryFeedback command lists the events, and clears them on request")
    func command() throws {
        let host = ViewHost(SelectionScreen(), device: square)
        #expect(
            host.execute(.sensoryFeedback(clear: false)).message
                == "No sensory feedback has played.")
        try host.tapButton(labeled: "Next")
        let reply = host.execute(.sensoryFeedback(clear: true))
        #expect(reply.ok)
        #expect(
            reply.message
                == "1 sensory feedback event:\n1. selection at SelectionScreen/Button (t=0 s)")
        #expect(host.sensoryFeedbackEvents.isEmpty)
    }

    @Test("Reduce Motion is off by default and a view reads it from the environment")
    func reduceMotion() {
        let host = ViewHost(MotionLabel(), device: square)
        #expect(!host.reduceMotion)
        #expect(host.root.outline() == "Root\n└─ Text \"lively\"")

        host.reduceMotion = true
        #expect(host.root.outline() == "Root reduceMotion=true\n└─ Text \"calm\"")

        host.reduceMotion = false
        #expect(host.root.outline() == "Root\n└─ Text \"lively\"")
        #expect(
            ViewHost(MotionLabel(), device: square, reduceMotion: true).root.outline()
                == "Root reduceMotion=true\n└─ Text \"calm\"")
    }

    @Test("The setReduceMotion command switches the setting")
    func reduceMotionCommand() {
        let host = ViewHost(MotionLabel(), device: square)
        let on = host.execute(.setReduceMotion(true))
        #expect(on.ok)
        #expect(on.message == "Reduce Motion is on.")
        #expect(host.reduceMotion)
        #expect(
            host.execute(.setAppearance(colorScheme: "dark", dynamicTypeSize: nil)).message
                == "The device is set to dark at Dynamic Type size large with Reduce Motion on.")
        #expect(host.execute(.setReduceMotion(false)).message == "Reduce Motion is off.")
        #expect(!host.reduceMotion)
    }

    @Test("Presentations inherit Reduce Motion")
    func presentation() throws {
        struct Screen: View {
            @State private var shown = true
            var body: some View {
                Text("Behind").sheet(isPresented: $shown) { MotionLabel() }
            }
        }
        let host = ViewHost(Screen(), device: square, reduceMotion: true)
        #expect(host.root.outline().contains("Text \"calm\""))
    }
}
