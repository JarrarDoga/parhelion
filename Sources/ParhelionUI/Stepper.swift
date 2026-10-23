#if canImport(Foundation)
import Foundation
#endif

/// A control that increments and decrements a value, mirroring SwiftUI's
/// `Stepper`.
///
/// The label sits at the leading edge and the 92 × 32 control at the
/// trailing edge of the width the stepper is offered. Its halves are
/// `StepperButton` nodes labeled `Decrement` and `Increment`, as VoiceOver
/// names them, so `tapButton(labeled:)` finds them. A half turns off at the
/// end of the stepper's range, or when its action is `nil`.
public struct Stepper<Label: View>: View {
    public typealias Body = Never

    let label: Label
    let onIncrement: (@MainActor () -> Void)?
    let onDecrement: (@MainActor () -> Void)?
    let onEditingChanged: (Bool) -> Void
    /// The value, bounds, and step of a stepper made with a value, as the
    /// node records them.
    var attributes: [String: String] = [:]

    /// Creates a stepper that runs actions when its halves are tapped.
    public init(
        @ViewBuilder label: () -> Label,
        onIncrement: (@MainActor () -> Void)?,
        onDecrement: (@MainActor () -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.label = label()
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
        self.onEditingChanged = onEditingChanged
    }

    /// Creates a stepper that changes a value by `step`, within `bounds`.
    public init<V: Strideable>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(value: value, bounds: bounds, step: step, label: label(), onEditingChanged)
    }

    /// Creates a stepper that changes a value by `step`, without limits.
    public init<V: Strideable>(
        value: Binding<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(value: value, bounds: nil, step: step, label: label(), onEditingChanged)
    }

    private init<V: Strideable>(
        value: Binding<V>, bounds: ClosedRange<V>?, step: V.Stride, label: Label,
        _ onEditingChanged: @escaping (Bool) -> Void
    ) {
        let current = value.wrappedValue
        self.label = label
        self.onEditingChanged = onEditingChanged
        func change(by stride: V.Stride) -> @MainActor () -> Void {
            { value.wrappedValue = Self.clamp(value.wrappedValue.advanced(by: stride), bounds) }
        }
        let canIncrement = bounds.map { current < $0.upperBound } ?? true
        let canDecrement = bounds.map { current > $0.lowerBound } ?? true
        onIncrement = canIncrement ? change(by: step) : nil
        onDecrement = canDecrement ? change(by: -step) : nil
        attributes["value"] = String(describing: current)
        if let bounds {
            attributes["bounds"] = "\(bounds.lowerBound)...\(bounds.upperBound)"
        }
        if step != 1 { attributes["step"] = String(describing: step) }
    }

    private static func clamp<V: Comparable>(_ value: V, _ bounds: ClosedRange<V>?) -> V {
        guard let bounds else { return value }
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    public var body: Never {
        fatalError("Stepper is a primitive view and has no body.")
    }
}

extension Stepper where Label == Text {
    /// Creates a stepper with a text label that runs actions when its halves
    /// are tapped.
    public init(
        _ title: some StringProtocol,
        onIncrement: (@MainActor () -> Void)?,
        onDecrement: (@MainActor () -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            label: { Text(title) }, onIncrement: onIncrement, onDecrement: onDecrement,
            onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper with a text label that changes a value by `step`,
    /// within `bounds`.
    public init<V: Strideable>(
        _ title: some StringProtocol,
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value, in: bounds, step: step, label: { Text(title) },
            onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper with a text label that changes a value by `step`,
    /// without limits.
    public init<V: Strideable>(
        _ title: some StringProtocol,
        value: Binding<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value, step: step, label: { Text(title) }, onEditingChanged: onEditingChanged)
    }
}

extension Stepper: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Stepper")
        var attributes = attributes
        evaluator.markDisabled(&attributes)
        let isEnabled = evaluator.environment.isEnabled
        let onEditingChanged = onEditingChanged
        func half(_ name: String, label: String, action: (@MainActor () -> Void)?) -> ViewNode {
            let id = ownPath.appending(name).id
            var attributes = ["label": label]
            if isEnabled, let action {
                evaluator.registerAction(
                    {
                        onEditingChanged(true)
                        action()
                        onEditingChanged(false)
                    }, for: id)
            } else {
                attributes["disabled"] = "true"
            }
            return ViewNode(id: id, kind: "StepperButton", attributes: attributes)
        }
        let children =
            evaluator.evaluate(label, at: ownPath)
            + [
                half("decrement", label: "Decrement", action: onDecrement),
                half("increment", label: "Increment", action: onIncrement),
            ]
        return [
            ViewNode(id: ownPath.id, kind: "Stepper", attributes: attributes, children: children)
        ]
    }
}
