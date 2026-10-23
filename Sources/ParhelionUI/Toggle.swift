#if canImport(Foundation)
import Foundation
#endif

/// A control that turns a setting on and off, mirroring SwiftUI's `Toggle`.
///
/// On iOS a toggle is a switch: the label at the leading edge and the switch
/// at the trailing edge of the width it is offered. The node is `Toggle`,
/// with an `isOn` attribute, and its last child is the `Switch`, which
/// responds to taps and carries the label's text as its `label` attribute,
/// so `tapButton(labeled:)` finds it. Tapping the label does nothing, as on
/// iOS. The switch's knob slides with a spring when the value changes.
public struct Toggle<Label: View>: View {
    public typealias Body = Never

    let isOn: Binding<Bool>
    let label: Label

    /// Creates a toggle with a label.
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }

    public var body: Never {
        fatalError("Toggle is a primitive view and has no body.")
    }
}

extension Toggle where Label == Text {
    /// Creates a toggle with a text label.
    public init(_ title: some StringProtocol, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}

extension Toggle: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Toggle")
        let labelNodes = evaluator.evaluate(label, at: ownPath)
        let switchID = ownPath.appending("switch").id
        let knobID = ownPath.appending("switch/knob").id
        let value = isOn.wrappedValue
        var attributes = ["isOn": String(value)]
        evaluator.markDisabled(&attributes)
        var switchAttributes: [String: String] = [:]
        let text = labelNodes.map(\.label).joined(separator: " ")
        if !text.isEmpty { switchAttributes["label"] = text }
        if evaluator.environment.isEnabled {
            let isOn = isOn
            evaluator.registerAction({ isOn.wrappedValue.toggle() }, for: switchID)
        }
        evaluator.animate(
            [knobID], with: LayoutDefaults.switchAnimation, whenChanged: value, key: ownPath.id)
        let knob = ViewNode(id: knobID, kind: "Knob")
        let control = ViewNode(
            id: switchID, kind: "Switch", attributes: switchAttributes, children: [knob])
        return [
            ViewNode(
                id: ownPath.id, kind: "Toggle", attributes: attributes,
                children: labelNodes + [control])
        ]
    }
}

// MARK: - Toggle styles

/// The appearance of a ``Toggle``, set with ``View/toggleStyle(_:)``.
///
/// Parhelion draws every toggle as a switch, iOS's default, and has only
/// the built-in styles.
@MainActor
@preconcurrency
public protocol ToggleStyle {}

/// The platform's default toggle style: a switch on iOS.
public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
}

/// A toggle drawn as a switch.
public struct SwitchToggleStyle: ToggleStyle {
    public init() {}
}

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

extension View {
    /// Sets the style of toggles in this view. Parhelion draws every toggle
    /// as a switch.
    public func toggleStyle(_ style: some ToggleStyle) -> some View {
        self
    }
}
