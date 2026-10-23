#if canImport(Foundation)
import Foundation
#endif

/// A control that selects a value from a range by dragging a knob along a
/// track, mirroring SwiftUI's `Slider`.
///
/// The slider fills the width it is offered, with its minimum and maximum
/// value labels at the ends. On iOS the label is not drawn; the node records
/// its text as a `label` attribute, with `value`, `bounds`, and `step`. The
/// track is a `SliderTrack` node with the `Knob` inside.
///
/// A press on the track takes the knob: dragging from the knob moves it with
/// the pointer, and a press or tap elsewhere on the track moves the knob
/// there. A value with a step snaps to it.
public struct Slider<Label: View, ValueLabel: View>: View {
    public typealias Body = Never

    let value: Binding<Double>
    let bounds: ClosedRange<Double>
    let step: Double?
    let label: Label
    let minimumValueLabel: ValueLabel?
    let maximumValueLabel: ValueLabel?
    let onEditingChanged: (Bool) -> Void

    init<V: BinaryFloatingPoint>(
        value: Binding<V>, bounds: ClosedRange<V>, step: Double?, label: Label,
        minimumValueLabel: ValueLabel?, maximumValueLabel: ValueLabel?,
        onEditingChanged: @escaping (Bool) -> Void
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = step.flatMap { $0 > 0 ? $0 : nil }
        self.label = label
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
        self.onEditingChanged = onEditingChanged
    }

    public var body: Never {
        fatalError("Slider is a primitive view and has no body.")
    }
}

extension Slider {
    /// Creates a slider with a label and labels for the minimum and maximum
    /// values.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil, label: label(),
            minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged)
    }

    /// Creates a slider whose value moves in steps, with a label and labels
    /// for the minimum and maximum values.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: Double(step), label: label(),
            minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged)
    }
}

extension Slider where ValueLabel == EmptyView {
    /// Creates a slider with a label.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil, label: label(), minimumValueLabel: nil,
            maximumValueLabel: nil, onEditingChanged: onEditingChanged)
    }

    /// Creates a slider whose value moves in steps, with a label.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: Double(step), label: label(),
            minimumValueLabel: nil, maximumValueLabel: nil, onEditingChanged: onEditingChanged)
    }
}

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    /// Creates a slider.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil, label: EmptyView(), minimumValueLabel: nil,
            maximumValueLabel: nil, onEditingChanged: onEditingChanged)
    }

    /// Creates a slider whose value moves in steps.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: Double(step), label: EmptyView(),
            minimumValueLabel: nil, maximumValueLabel: nil, onEditingChanged: onEditingChanged)
    }
}

extension Slider: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Slider")
        let trackID = ownPath.appending("track").id
        let control = SliderControl(
            value: value, bounds: bounds, step: step, onEditingChanged: onEditingChanged)
        var attributes = [
            "value": SliderControl.format(control.clamped(value.wrappedValue)),
            "bounds":
                "\(SliderControl.format(bounds.lowerBound))...\(SliderControl.format(bounds.upperBound))",
        ]
        if let step { attributes["step"] = SliderControl.format(step) }
        // The label is not drawn on iOS, but names the slider.
        let text = evaluator.evaluate(label, at: ownPath.appending("label")).map(\.label)
            .joined(separator: " ")
        if !text.isEmpty { attributes["label"] = text }
        evaluator.markDisabled(&attributes)
        // A press reads the slider from host storage, so it keeps working
        // between updates.
        evaluator.controlBox(trackID, "slider", initialValue: SliderControl?.none).value =
            evaluator.environment.isEnabled ? control : nil
        _ = evaluator.controlBox(trackID, "drag", initialValue: SliderDrag?.none)

        let minimum = minimumValueLabel.map {
            evaluator.evaluate($0, at: ownPath.appending("minimum"))
        }
        let maximum = maximumValueLabel.map {
            evaluator.evaluate($0, at: ownPath.appending("maximum"))
        }
        let track = ViewNode(
            id: trackID, kind: "SliderTrack",
            children: [ViewNode(id: ownPath.appending("track/knob").id, kind: "Knob")])
        return [
            ViewNode(
                id: ownPath.id, kind: "Slider", attributes: attributes,
                children: (minimum ?? []) + [track] + (maximum ?? []))
        ]
    }
}

/// A slider's value and range, kept in host storage while the slider is in
/// the tree, so that a press can change the value.
struct SliderControl {
    let value: Binding<Double>
    let bounds: ClosedRange<Double>
    let step: Double?
    let onEditingChanged: (Bool) -> Void

    /// The value inside the bounds.
    func clamped(_ value: Double) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    /// How far along the track a value is, from 0 to 1.
    func fraction(of value: Double) -> Double {
        let span = bounds.upperBound - bounds.lowerBound
        return span > 0 ? (clamped(value) - bounds.lowerBound) / span : 0
    }

    /// The value at a fraction of the way along the track, snapped to the
    /// step from the lower bound.
    func value(atFraction fraction: Double) -> Double {
        let span = bounds.upperBound - bounds.lowerBound
        var value = bounds.lowerBound + min(max(fraction, 0), 1) * span
        if let step {
            value = bounds.lowerBound + ((value - bounds.lowerBound) / step).rounded() * step
        }
        return clamped(value)
    }

    /// A value as a node attribute: at most four decimal places.
    static func format(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

/// A drag of a slider's knob in progress.
struct SliderDrag {
    /// How far the pointer is from the knob's center along the track: the
    /// distance where the press started on the knob, or 0 when it started
    /// elsewhere on the track, so that the knob jumps to the pointer.
    var grabOffset: CGFloat
}
