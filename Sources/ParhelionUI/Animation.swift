#if canImport(Foundation)
import Foundation
#endif

/// How a change moves from its old value to its new one over time, mirroring
/// SwiftUI's `Animation`.
///
/// Animations run on the host's clock, which advances only through
/// ``ViewHost/advanceTime(by:)``, so the same changes at the same times always
/// produce the same frames. Repeating animations are not supported yet.
public struct Animation: Hashable, Sendable {
    enum Curve: Hashable, Sendable {
        /// A cubic Bézier timing curve from (0, 0) to (1, 1) with two control
        /// points.
        case timing(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double)
        /// A damped spring.
        case spring(response: Double, dampingFraction: Double)
    }

    let curve: Curve
    var delay: Double = 0
    var speed: Double = 1

    init(curve: Curve) {
        self.curve = curve
    }

    /// The default animation: a spring without bounce.
    public static let `default` = Animation.spring(
        response: LayoutDefaults.defaultSpringResponse, dampingFraction: 1)

    // MARK: Timing curves

    public static func linear(duration: Double) -> Animation {
        Animation(curve: .timing(x1: 0, y1: 0, x2: 1, y2: 1, duration: duration))
    }

    public static var linear: Animation { .linear(duration: LayoutDefaults.animationDuration) }

    public static func easeIn(duration: Double) -> Animation {
        Animation(curve: .timing(x1: 0.42, y1: 0, x2: 1, y2: 1, duration: duration))
    }

    public static var easeIn: Animation { .easeIn(duration: LayoutDefaults.animationDuration) }

    public static func easeOut(duration: Double) -> Animation {
        Animation(curve: .timing(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: duration))
    }

    public static var easeOut: Animation { .easeOut(duration: LayoutDefaults.animationDuration) }

    public static func easeInOut(duration: Double) -> Animation {
        Animation(curve: .timing(x1: 0.42, y1: 0, x2: 0.58, y2: 1, duration: duration))
    }

    public static var easeInOut: Animation {
        .easeInOut(duration: LayoutDefaults.animationDuration)
    }

    /// A timing curve with two control points, for a duration in seconds.
    public static func timingCurve(
        _ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35
    ) -> Animation {
        Animation(curve: .timing(x1: c0x, y1: c0y, x2: c1x, y2: c1y, duration: duration))
    }

    // MARK: Springs

    /// A spring with a response time in seconds and a damping fraction: 1
    /// settles without overshooting, and smaller values bounce.
    @_disfavoredOverload
    public static func spring(
        response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0
    ) -> Animation {
        Animation(
            curve: .spring(response: max(response, 0.01), dampingFraction: max(dampingFraction, 0)))
    }

    /// A spring with a perceptual duration in seconds and a bounce: 0 settles
    /// without overshooting, and larger values bounce more.
    public static func spring(
        duration: Double = 0.5, bounce: Double = 0, blendDuration: Double = 0
    ) -> Animation {
        let damping = bounce >= 0 ? 1 - bounce : 1 / (1 + bounce)
        return Animation(
            curve: .spring(response: max(duration, 0.01), dampingFraction: max(damping, 0)))
    }

    public static var spring: Animation { .spring() }

    public static func interactiveSpring(
        response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25
    ) -> Animation {
        .spring(response: response, dampingFraction: dampingFraction)
    }

    public static var interactiveSpring: Animation { .interactiveSpring() }

    /// A spring without bounce.
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        .spring(duration: duration, bounce: extraBounce)
    }

    public static var smooth: Animation { .smooth() }

    /// A spring with a little bounce.
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        .spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    public static var snappy: Animation { .snappy() }

    /// A spring with a visible bounce.
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        .spring(duration: duration, bounce: 0.3 + extraBounce)
    }

    public static var bouncy: Animation { .bouncy() }

    // MARK: Modifiers

    /// The same animation, starting `delay` seconds later.
    public func delay(_ delay: Double) -> Animation {
        var copy = self
        copy.delay += max(delay, 0)
        return copy
    }

    /// The same animation, running `speed` times as fast.
    public func speed(_ speed: Double) -> Animation {
        var copy = self
        copy.speed *= max(speed, 0.01)
        return copy
    }

    // MARK: Evaluation

    /// How far the animation has gone after `elapsed` seconds: 0 at the
    /// start and 1 at the end. A bouncing spring passes 1 before it settles.
    func progress(at elapsed: Double) -> Double {
        let time = (elapsed - delay) * speed
        guard time > 0 else { return 0 }
        switch curve {
        case .timing(let x1, let y1, let x2, let y2, let duration):
            guard duration > 0, time < duration else { return 1 }
            return Self.bezier(x1, y1, x2, y2, at: time / duration)
        case .spring(let response, let damping):
            guard time < Self.settleTime(response: response, damping: damping) else { return 1 }
            return 1 - Self.springEnvelope(response: response, damping: damping, at: time).value
        }
    }

    /// The time from the change until the animation ends, in seconds.
    var totalDuration: Double {
        let active: Double =
            switch curve {
            case .timing(_, _, _, _, let duration): duration
            case .spring(let response, let damping):
                Self.settleTime(response: response, damping: damping)
            }
        return delay + active / speed
    }

    /// The y value of a cubic Bézier timing curve at an x value in 0...1.
    private static func bezier(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, at x: Double
    ) -> Double {
        func coordinate(_ a: Double, _ b: Double, _ t: Double) -> Double {
            3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
        }
        func slope(_ a: Double, _ b: Double, _ t: Double) -> Double {
            3 * a * (1 - t) * (1 - t) + 6 * (b - a) * t * (1 - t) + 3 * (1 - b) * t * t
        }
        // Find the curve parameter whose x is the input, by Newton's method
        // with bisection as a fallback.
        var t = x
        for _ in 0..<8 {
            let error = coordinate(x1, x2, t) - x
            if abs(error) < 1e-6 { return coordinate(y1, y2, t) }
            let derivative = slope(x1, x2, t)
            guard abs(derivative) > 1e-6 else { break }
            t -= error / derivative
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<30 {
            let value = coordinate(x1, x2, t)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return coordinate(y1, y2, t)
    }

    /// The remaining fraction of a spring's displacement at a time, and an
    /// upper bound on its size from then on.
    private static func springEnvelope(
        response: Double, damping: Double, at time: Double
    ) -> (value: Double, bound: Double) {
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let decay = damping * omega
            let damped = omega * (1 - damping * damping).squareRoot()
            let envelope = exp(-decay * time)
            let value = envelope * (cos(damped * time) + decay / damped * sin(damped * time))
            return (value, envelope * (1 + decay / damped))
        }
        let value = exp(-omega * time) * (1 + omega * time)
        return (value, value)
    }

    /// When a spring has settled to within a thousandth of its target.
    private static func settleTime(response: Double, damping: Double) -> Double {
        var time = 0.0
        while time < 10,
            springEnvelope(response: response, damping: damping, at: time).bound > 0.001
        {
            time += 1.0 / 240
        }
        return time
    }
}

/// The animation of the change being made, set by ``withAnimation(_:_:)``.
@MainActor
enum AnimationContext {
    /// `nil` outside `withAnimation`; `.some(nil)` inside `withAnimation(nil)`.
    static var current: Animation??
}

/// Runs `body` and animates the changes it makes to state, mirroring
/// SwiftUI's `withAnimation`. Pass `nil` to make the changes without
/// animation.
@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default, _ body: () throws -> Result
) rethrows -> Result {
    let outer = AnimationContext.current
    AnimationContext.current = .some(animation)
    defer { AnimationContext.current = outer }
    return try body()
}

// MARK: - Transitions

/// How a view enters and leaves the tree when the change is animated,
/// mirroring SwiftUI's `AnyTransition`. The default is ``opacity``.
public struct AnyTransition: Sendable {
    /// The state a view starts from when it is inserted, or ends in when it
    /// is removed.
    struct Effect: Sendable {
        enum Offset: Sendable {
            case none
            /// The view's own width or height, toward an edge.
            case edge(Edge)
            case fixed(CGSize)
        }

        var opacity: Double = 1
        var offsets: [Offset] = []

        func combined(with other: Effect) -> Effect {
            Effect(opacity: opacity * other.opacity, offsets: offsets + other.offsets)
        }

        /// The offset for a view with the given frame.
        func offset(for frame: CGRect) -> CGSize {
            offsets.reduce(CGSize.zero) { total, offset in
                switch offset {
                case .none: return total
                case .fixed(let size):
                    return CGSize(
                        width: total.width + size.width, height: total.height + size.height)
                case .edge(let edge):
                    switch edge {
                    case .leading:
                        return CGSize(width: total.width - frame.width, height: total.height)
                    case .trailing:
                        return CGSize(width: total.width + frame.width, height: total.height)
                    case .top:
                        return CGSize(width: total.width, height: total.height - frame.height)
                    case .bottom:
                        return CGSize(width: total.width, height: total.height + frame.height)
                    }
                }
            }
        }
    }

    let insertion: Effect
    let removal: Effect

    /// Fades the view in and out.
    public static let opacity = AnyTransition(
        insertion: Effect(opacity: 0), removal: Effect(opacity: 0))

    /// Inserts and removes the view without an effect.
    public static let identity = AnyTransition(insertion: Effect(), removal: Effect())

    /// Moves the view in from the leading edge and out toward the trailing
    /// edge.
    public static let slide = AnyTransition(
        insertion: Effect(offsets: [.edge(.leading)]),
        removal: Effect(offsets: [.edge(.trailing)]))

    /// Moves the view in from, and out toward, an edge, by its own size.
    public static func move(edge: Edge) -> AnyTransition {
        let effect = Effect(offsets: [.edge(edge)])
        return AnyTransition(insertion: effect, removal: effect)
    }

    /// Moves the view in from, and out to, an offset.
    public static func offset(_ offset: CGSize) -> AnyTransition {
        let effect = Effect(offsets: [.fixed(offset)])
        return AnyTransition(insertion: effect, removal: effect)
    }

    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        .offset(CGSize(width: x, height: y))
    }

    /// Moves and fades the view in from an edge, and out toward the opposite
    /// edge.
    public static func push(from edge: Edge) -> AnyTransition {
        let opposite: Edge =
            switch edge {
            case .leading: .trailing
            case .trailing: .leading
            case .top: .bottom
            case .bottom: .top
            }
        return AnyTransition(
            insertion: Effect(opacity: 0, offsets: [.edge(edge)]),
            removal: Effect(opacity: 0, offsets: [.edge(opposite)]))
    }

    /// One transition for insertion and another for removal.
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition
    {
        AnyTransition(insertion: insertion.insertion, removal: removal.removal)
    }

    /// Both transitions at once.
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(
            insertion: insertion.combined(with: other.insertion),
            removal: removal.combined(with: other.removal))
    }
}

// MARK: - Modifiers

extension View {
    /// Animates changes to the view and its content when `value` changes.
    /// Pass `nil` to make those changes without animation, even inside
    /// ``withAnimation(_:_:)``.
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        AnimationView(content: self, animation: animation, value: value)
    }

    /// Sets how the view enters and leaves the tree when the change is
    /// animated.
    public func transition(_ transition: AnyTransition) -> some View {
        TransitionView(content: self, transition: transition)
    }

    /// Sets the view's opacity, from 0 (transparent) to 1. Opacities applied
    /// to a view and its ancestors multiply.
    public func opacity(_ opacity: Double) -> some View {
        ModifiedContent(content: self, change: .opacity(min(max(opacity, 0), 1)))
    }

    /// Moves the view by an offset when it is drawn and tapped, without
    /// changing its layout.
    public func offset(_ offset: CGSize) -> some View {
        layoutModifier(.offset(offset))
    }

    /// Moves the view by an offset when it is drawn and tapped, without
    /// changing its layout.
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        offset(CGSize(width: x, height: y))
    }
}

/// A view whose changes animate when a value changes.
struct AnimationView<Content: View, Value: Equatable>: View {
    typealias Body = Never

    let content: Content
    let animation: Animation?
    let value: Value

    var body: Never {
        fatalError("AnimationView is a primitive view and has no body.")
    }
}

extension AnimationView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        let key = "\(path.id.rawValue)|animation|\(Value.self)"
        if evaluator.host.animationValueChanged(forKey: key, to: value) {
            // Inner modifiers registered first, and they take precedence.
            for node in nodes.flatMap(\.allNodes) where evaluator.implicitAnimations[node.id] == nil
            {
                evaluator.implicitAnimations[node.id] = .some(animation)
            }
        }
        return nodes
    }
}

/// A view with a transition for when it enters or leaves the tree.
struct TransitionView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let transition: AnyTransition

    var body: Never {
        fatalError("TransitionView is a primitive view and has no body.")
    }
}

extension TransitionView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        for node in nodes where evaluator.transitions[node.id] == nil {
            evaluator.transitions[node.id] = transition
        }
        return nodes
    }
}

extension ViewHost {
    /// Records the value of an `animation(_:value:)` modifier and reports
    /// whether it changed since the last update.
    func animationValueChanged<V: Equatable>(forKey key: String, to value: V) -> Bool {
        visitedAnimationKeys.insert(key)
        defer { animationValues[key] = value }
        guard let previous = animationValues[key] as? V else { return false }
        return previous != value
    }
}
