import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// A view that shows progress: a spinner when the amount is unknown, or a
/// ring or a bar when it is, mirroring SwiftUI's `ProgressView`.
///
/// The default style draws a spinner for an unknown amount and a bar for a
/// known one; ``View/progressViewStyle(_:)`` picks ``CircularProgressViewStyle``
/// or ``LinearProgressViewStyle``. The node is a `ProgressView` that records
/// its `style`, and for a known amount its `value` and `total`. Its children
/// are the label views and a `ProgressIndicator` node with the `shape`
/// (`spinner`, `ring`, or `bar`) and, for a known amount, the `fraction`
/// completed. A spinner and an indeterminate bar also record a `phase`, the
/// fraction of the current turn that the host's clock has reached, so they
/// animate with ``ViewHost/advanceTime(by:)`` and follow the host's frames
/// like a `TimelineView` with an `.animation` schedule.
///
/// Assumed, from iOS 26: the spinner is 20 points across with eight spokes
/// and turns once a second, in steps of one spoke; the ring is 20 points
/// across and 2.5 points thick; the bar is 4 points thick, as wide as it is
/// offered, with its label above it at the leading edge and its current
/// value label below it. A spinner's or a ring's label sits below it. Labels
/// draw in the secondary color.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    public typealias Body = Never

    let label: Label
    let currentValueLabel: CurrentValueLabel
    let hasLabel: Bool
    let hasCurrentValueLabel: Bool
    /// The value and the total, or `nil` for an unknown amount.
    let amount: (value: Double, total: Double)?

    init(
        label: Label, currentValueLabel: CurrentValueLabel, amount: (Double, Double)?,
        hasLabel: Bool? = nil, hasCurrentValueLabel: Bool? = nil
    ) {
        self.label = label
        self.currentValueLabel = currentValueLabel
        self.hasLabel = hasLabel ?? (Label.self != EmptyView.self)
        self.hasCurrentValueLabel =
            hasCurrentValueLabel ?? (CurrentValueLabel.self != EmptyView.self)
        self.amount = amount.map { (value: $0.0, total: $0.1) }
    }

    public var body: Never {
        fatalError("ProgressView is a primitive view and has no body.")
    }
}

extension ProgressView {
    private static func amount<V: BinaryFloatingPoint>(_ value: V?, _ total: V) -> (Double, Double)?
    {
        value.map { (Double($0), Double(total)) }
    }
}

extension ProgressView
where
    Label == ProgressViewStyleConfiguration.Label,
    CurrentValueLabel == ProgressViewStyleConfiguration.CurrentValueLabel
{
    /// Creates a progress view from a style's configuration, drawn in the
    /// default look, so that a custom style can wrap it.
    public init(_ configuration: ProgressViewStyleConfiguration) {
        self.init(
            label: configuration.label ?? .init(content: EmptyView()),
            currentValueLabel: configuration.currentValueLabel ?? .init(content: EmptyView()),
            amount: configuration.fractionCompleted.map { ($0, 1) },
            hasLabel: configuration.label != nil,
            hasCurrentValueLabel: configuration.currentValueLabel != nil)
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    /// Creates a spinner.
    public init() {
        self.init(label: EmptyView(), currentValueLabel: EmptyView(), amount: nil)
    }

    /// Creates a bar that shows `value` out of `total`, or a spinner when
    /// `value` is `nil`.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        self.init(
            label: EmptyView(), currentValueLabel: EmptyView(), amount: Self.amount(value, total))
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// Creates a spinner with a title.
    public init(_ title: some StringProtocol) {
        self.init(label: Text(title), currentValueLabel: EmptyView(), amount: nil)
    }

    /// Creates a bar with a title that shows `value` out of `total`, or a
    /// spinner when `value` is `nil`.
    public init<V: BinaryFloatingPoint>(
        _ title: some StringProtocol, value: V?, total: V = 1.0
    ) {
        self.init(
            label: Text(title), currentValueLabel: EmptyView(), amount: Self.amount(value, total))
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    /// Creates a spinner with a label.
    public init(@ViewBuilder label: () -> Label) {
        self.init(label: label(), currentValueLabel: EmptyView(), amount: nil)
    }

    /// Creates a bar with a label that shows `value` out of `total`, or a
    /// spinner when `value` is `nil`.
    public init<V: BinaryFloatingPoint>(
        value: V?, total: V = 1.0, @ViewBuilder label: () -> Label
    ) {
        self.init(
            label: label(), currentValueLabel: EmptyView(), amount: Self.amount(value, total))
    }
}

extension ProgressView {
    /// Creates a bar with a label and a current value label that shows
    /// `value` out of `total`, or a spinner when `value` is `nil`.
    public init<V: BinaryFloatingPoint>(
        value: V?, total: V = 1.0, @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.init(
            label: label(), currentValueLabel: currentValueLabel(),
            amount: Self.amount(value, total))
    }
}

// MARK: - Styles

/// The appearance of a ``ProgressView``, mirroring SwiftUI's
/// `ProgressViewStyle`.
@MainActor
@preconcurrency
public protocol ProgressViewStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    typealias Configuration = ProgressViewStyleConfiguration
}

/// What a ``ProgressViewStyle`` draws, mirroring SwiftUI's
/// `ProgressViewStyleConfiguration`.
public struct ProgressViewStyleConfiguration {
    /// The progress view's label, as a view.
    public struct Label: View {
        public typealias Body = Never

        let content: any View

        public var body: Never {
            fatalError("Label is a primitive view and has no body.")
        }
    }

    /// The progress view's current value label, as a view.
    public struct CurrentValueLabel: View {
        public typealias Body = Never

        let content: any View

        public var body: Never {
            fatalError("CurrentValueLabel is a primitive view and has no body.")
        }
    }

    /// The fraction of the work that is done, from 0 to 1, or `nil` when the
    /// amount is unknown.
    public let fractionCompleted: Double?
    /// The progress view's label, or `nil` if it has none.
    public var label: Label?
    /// The progress view's current value label, or `nil` if it has none.
    public var currentValueLabel: CurrentValueLabel?
}

extension ProgressViewStyleConfiguration.Label: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path.appending("label"))
    }
}

extension ProgressViewStyleConfiguration.CurrentValueLabel: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path.appending("currentValueLabel"))
    }
}

/// The progress view styles Parhelion draws itself.
enum BuiltInProgressViewStyle: String, Sendable {
    case automatic, circular, linear
}

/// A progress view style that Parhelion draws itself.
protocol BuiltInProgressViewStyleProtocol: ProgressViewStyle {
    var builtIn: BuiltInProgressViewStyle { get }
    var tintColor: Color? { get }
}

/// The default style: a spinner for an unknown amount and a bar for a known
/// one. Mirrors SwiftUI's `DefaultProgressViewStyle`.
public struct DefaultProgressViewStyle: BuiltInProgressViewStyleProtocol {
    var builtIn: BuiltInProgressViewStyle { .automatic }
    var tintColor: Color? { nil }
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}

/// A spinner, or a ring for a known amount. Mirrors SwiftUI's
/// `CircularProgressViewStyle`.
public struct CircularProgressViewStyle: BuiltInProgressViewStyleProtocol {
    var builtIn: BuiltInProgressViewStyle { .circular }
    let tintColor: Color?
    public init() { tintColor = nil }
    /// Creates a style whose ring is drawn in `tint`.
    public init(tint: Color) { tintColor = tint }

    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}

/// A horizontal bar. Mirrors SwiftUI's `LinearProgressViewStyle`.
public struct LinearProgressViewStyle: BuiltInProgressViewStyleProtocol {
    var builtIn: BuiltInProgressViewStyle { .linear }
    let tintColor: Color?
    public init() { tintColor = nil }
    /// Creates a style whose bar is drawn in `tint`.
    public init(tint: Color) { tintColor = tint }

    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}

extension ProgressViewStyle where Self == DefaultProgressViewStyle {
    public static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}

/// The progress view style in the environment: a built-in style with its
/// tint, or a custom ``ProgressViewStyle`` whose body is evaluated.
enum ResolvedProgressViewStyle {
    case builtIn(BuiltInProgressViewStyle, tint: String?)
    case custom(any ProgressViewStyle)
}

struct ProgressViewStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedProgressViewStyle { .builtIn(.automatic, tint: nil) }
}

extension EnvironmentValues {
    var progressViewStyle: ResolvedProgressViewStyle {
        get { self[ProgressViewStyleKey.self] }
        set { self[ProgressViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style of progress views in this view and its content.
    public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
        let resolved: ResolvedProgressViewStyle =
            (style as? any BuiltInProgressViewStyleProtocol).map {
                .builtIn($0.builtIn, tint: $0.tintColor?.styleName)
            } ?? .custom(style)
        return EnvironmentWriter(content: self) { $0.progressViewStyle = resolved }
    }
}

// MARK: - Nodes

extension ProgressView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        ProgressViewBehavior.register()
        let ownPath = path.appending("ProgressView")
        var attributes: [String: String] = [:]
        if let amount {
            attributes["value"] = ProgressViewBehavior.format(amount.value)
            attributes["total"] = ProgressViewBehavior.format(amount.total)
        }
        let fraction = amount.map { ProgressViewBehavior.fraction(of: $0.value, in: $0.total) }

        var shape: ProgressViewBehavior.Shape
        let children: [ViewNode]
        switch evaluator.environment.progressViewStyle {
        case .custom(let style):
            attributes["style"] = baseTypeName(of: type(of: style))
            // The style's body draws with the default style, so a progress
            // view inside it does not evaluate the style again.
            let body = customBody(style, fraction: fraction)
            children = evaluator.withEnvironment({
                $0.progressViewStyle = ProgressViewStyleKey.defaultValue
            }) { evaluator.evaluate(body, at: ownPath) }
            return [
                ViewNode(
                    id: ownPath.id, kind: "ProgressView", attributes: attributes,
                    children: children)
            ]
        case .builtIn(let style, let tint):
            if let tint { attributes["tint"] = tint }
            shape =
                switch style {
                case .circular: fraction == nil ? .spinner : .ring
                case .linear: .bar
                case .automatic: fraction == nil ? .spinner : .bar
                }
            attributes["style"] = shape == .bar ? "linear" : "circular"
        }

        var indicatorAttributes = ["shape": shape.rawValue]
        if let fraction {
            indicatorAttributes["fraction"] = ProgressViewBehavior.format(fraction)
        } else {
            // The turn of the animation, from the host's clock.
            let indicatorID = ownPath.appending("indicator").id
            let period = shape == .bar ? ProgressViewBehavior.barPeriod : 1
            let state = evaluator.host.resolveTimeline(
                id: indicatorID, schedule: AnimationTimelineSchedule())
            let seconds = state.date.timeIntervalSince(evaluator.host.referenceDate)
            var phase = (seconds / period).truncatingRemainder(dividingBy: 1)
            if phase < 0 { phase += 1 }
            indicatorAttributes["phase"] = String(format: "%.3f", (phase * 1000).rounded() / 1000)
        }
        let indicator = ViewNode(
            id: ownPath.appending("indicator").id, kind: "ProgressIndicator",
            attributes: indicatorAttributes)

        let labelNodes = hasLabel ? evaluator.evaluate(label, at: ownPath.appending("label")) : []
        let valueNodes =
            hasCurrentValueLabel
            ? evaluator.evaluate(currentValueLabel, at: ownPath.appending("currentValueLabel"))
            : []
        // A bar has its label above it, a spinner or a ring below.
        children =
            shape == .bar
            ? labelNodes + [indicator] + valueNodes : [indicator] + labelNodes + valueNodes
        return [
            ViewNode(
                id: ownPath.id, kind: "ProgressView", attributes: attributes, children: children)
        ]
    }

    private func customBody<S: ProgressViewStyle>(_ style: S, fraction: Double?) -> any View {
        style.makeBody(
            configuration: ProgressViewStyleConfiguration(
                fractionCompleted: fraction,
                label: hasLabel ? .init(content: label) : nil,
                currentValueLabel: hasCurrentValueLabel
                    ? .init(content: currentValueLabel) : nil))
    }
}

// MARK: - Layout and drawing

/// The sizes, layout, and drawing of progress views.
enum ProgressViewBehavior {
    enum Shape: String {
        case spinner, ring, bar
    }

    /// The width and height of a spinner or a ring.
    static let circleSize: CGFloat = 20
    /// The thickness of a ring.
    static let ringThickness: CGFloat = 2.5
    /// The thickness of a bar.
    static let barThickness: CGFloat = 4
    /// Assumed: the width of a bar that is offered no width.
    static let idealBarWidth: CGFloat = 100
    /// The spokes of a spinner.
    static let spokeCount = 8
    /// The length and thickness of a spinner's spokes, and the radius of
    /// their inner ends.
    static let spokeLength: CGFloat = 5.5
    static let spokeThickness: CGFloat = 2
    /// The opacity of the spoke furthest behind the leading one.
    static let faintestSpoke = 0.25
    /// The seconds an indeterminate bar's highlight takes to cross it.
    static let barPeriod = 1.5
    /// The width of that highlight, as a fraction of the bar.
    static let highlightWidth: CGFloat = 0.35
    /// The space between a label and the indicator.
    static let barSpacing: CGFloat = 6
    static let circleSpacing: CGFloat = 8

    static func register() {
        NodeExtensions.registerOnce(kind: "ProgressView") { containerBehavior }
        NodeExtensions.registerOnce(kind: "ProgressIndicator") { indicatorBehavior }
    }

    static func format(_ value: Double) -> String {
        formatPoints(CGFloat(value))
    }

    /// The fraction `value` is of `total`, from 0 to 1. Assumed: a total
    /// that is not above zero counts as nothing done.
    static func fraction(of value: Double, in total: Double) -> Double {
        guard total > 0, value.isFinite else { return 0 }
        return min(max(value / total, 0), 1)
    }

    /// The labels and the indicator, stacked: a bar's at the leading edge,
    /// a spinner's and a ring's in the middle.
    static func stack(_ node: ViewNode) -> ViewNode {
        let isLinear = node.attributes["style"] == "linear"
        return ViewNode(
            id: node.id, kind: "VStack",
            attributes: [
                "alignment": isLinear ? "leading" : "center",
                "spacing": formatPoints(isLinear ? barSpacing : circleSpacing),
            ], children: node.children)
    }

    static let containerBehavior = NodeBehavior(
        size: { engine, node, proposal, _ in
            engine.sizeThatFits(stack(node), proposal, parentAxis: nil)
        },
        place: { engine, node, rect in
            engine.place(stack(node), in: rect, parentAxis: nil).children
        },
        draw: { _, node, drawing, _ in
            // Labels are secondary text.
            drawing.foreground = drawing.foreground ?? "secondary"
        })

    static let indicatorBehavior = NodeBehavior(
        size: { _, node, proposal, _ in
            switch Shape(rawValue: node.attributes["shape"] ?? "") {
            case .bar:
                return CGSize(width: proposal.width ?? idealBarWidth, height: barThickness)
            default:
                return CGSize(width: circleSize, height: circleSize)
            }
        },
        draw: { _, node, drawing, canvas in
            let fraction = node.attributes["fraction"].flatMap(Double.init)
            let phase = node.attributes["phase"].flatMap(Double.init) ?? 0
            switch Shape(rawValue: node.attributes["shape"] ?? "") {
            case .spinner:
                drawSpinner(phase: phase, drawing: drawing, into: &canvas)
            case .ring:
                drawRing(fraction: fraction ?? 0, drawing: drawing, into: &canvas)
            case .bar:
                drawBar(fraction: fraction, phase: phase, drawing: drawing, into: &canvas)
            case nil:
                break
            }
        })

    /// A rounded line between two points.
    static func capsule(from start: CGPoint, to end: CGPoint, thickness: CGFloat) -> Path {
        let angle = atan2(Double(end.y - start.y), Double(end.x - start.x))
        let radius = thickness / 2
        var path = Path()
        path.addArc(
            center: end, radius: radius, startAngle: Angle(radians: angle - .pi / 2),
            endAngle: Angle(radians: angle + .pi / 2), clockwise: false)
        path.addArc(
            center: start, radius: radius, startAngle: Angle(radians: angle + .pi / 2),
            endAngle: Angle(radians: angle + 3 * .pi / 2), clockwise: false)
        path.closeSubpath()
        return path
    }

    /// Eight spokes; the leading one is the darkest and the ones behind it
    /// fade, and the leading spoke steps around once per turn.
    static func drawSpinner(phase: Double, drawing: NodeDrawing, into canvas: inout Canvas) {
        let frame = drawing.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let outer = min(frame.width, frame.height) / 2 - spokeThickness / 2
        let inner = outer - spokeLength
        let leading = Int(phase * Double(spokeCount)) % spokeCount
        for spoke in 0..<spokeCount {
            let angle = -Double.pi / 2 + Double(spoke) * 2 * .pi / Double(spokeCount)
            let behind = (leading - spoke + spokeCount) % spokeCount
            let opacity = 1 - (1 - faintestSpoke) * Double(behind) / Double(spokeCount - 1)
            func point(_ radius: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + radius * CGFloat(cos(angle)),
                    y: center.y + radius * CGFloat(sin(angle)))
            }
            var color = drawing.color(drawing.foreground ?? "secondary")
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            canvas.fill(
                capsule(from: point(inner), to: point(outer), thickness: spokeThickness),
                color: color)
        }
    }

    /// A ring in the track color with an arc of the tint on it, clockwise
    /// from the top.
    static func drawRing(fraction: Double, drawing: NodeDrawing, into canvas: inout Canvas) {
        let size = min(drawing.frame.width, drawing.frame.height)
        let square = CGRect(
            x: drawing.frame.midX - size / 2, y: drawing.frame.midY - size / 2, width: size,
            height: size)
        canvas.fill(
            Path(
                ringAround: square, cornerRadius: size / 2, lineWidth: ringThickness,
                alignment: .inside), color: drawing.palette.sliderTrack.faded(by: drawing.opacity))
        guard fraction > 0 else { return }
        let center = CGPoint(x: square.midX, y: square.midY)
        let outer = size / 2
        let inner = outer - ringThickness
        let start = -Double.pi / 2
        let end = start + 2 * .pi * fraction
        var arc = Path()
        arc.addArc(
            center: center, radius: outer, startAngle: Angle(radians: start),
            endAngle: Angle(radians: end), clockwise: false)
        arc.addArc(
            center: center, radius: inner, startAngle: Angle(radians: end),
            endAngle: Angle(radians: start), clockwise: true)
        arc.closeSubpath()
        let color = drawing.color("tint")
        canvas.fill(arc, color: color)
        if fraction < 1 {
            // Round ends.
            let middle = (outer + inner) / 2
            for angle in [start, end] {
                let cap = CGPoint(
                    x: center.x + middle * CGFloat(cos(angle)),
                    y: center.y + middle * CGFloat(sin(angle)))
                canvas.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: cap.x - ringThickness / 2, y: cap.y - ringThickness / 2,
                            width: ringThickness, height: ringThickness)), color: color)
            }
        }
    }

    /// A track with the tint over its first `fraction`, or, when the amount
    /// is unknown, a highlight that crosses the track once per period.
    static func drawBar(
        fraction: Double?, phase: Double, drawing: NodeDrawing, into canvas: inout Canvas
    ) {
        let frame = drawing.frame
        let radius = frame.height / 2
        canvas.fill(
            frame, cornerRadius: radius, style: .continuous,
            color: drawing.palette.sliderTrack.faded(by: drawing.opacity))
        let tint = drawing.color("tint")
        if let fraction {
            guard fraction > 0 else { return }
            var filled = frame
            filled.size.width = frame.width * CGFloat(fraction)
            canvas.fill(
                filled, cornerRadius: min(radius, filled.width / 2), style: .continuous,
                color: tint)
            return
        }
        let width = frame.width * highlightWidth
        let travel = frame.width + width
        var highlight = frame
        highlight.origin.x = frame.minX - width + travel * CGFloat(phase)
        highlight.size.width = width
        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        canvas.fill(highlight, cornerRadius: radius, style: .continuous, color: tint)
        canvas.clipRect = outerClip
    }
}

extension RGBA {
    /// The color with its opacity multiplied by `opacity`.
    fileprivate func faded(by opacity: Double) -> RGBA {
        var color = self
        color.alpha = UInt8((Double(alpha) * opacity).rounded())
        return color
    }
}
