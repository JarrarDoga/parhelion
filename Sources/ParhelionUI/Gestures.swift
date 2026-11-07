import Foundation

// Gestures: the `Gesture` protocol, the gestures SwiftUI has for taps, long
// presses, and drags, the combinations of them, and the modifiers that attach
// one to a view. The recognizers are in GestureRecognizers.swift, and the
// host's side (hit testing, arbitration with buttons and scroll views) is in
// ViewHost+Gestures.swift. See docs/adr/0015-gesture-arbitration.md.

/// A gesture, mirroring SwiftUI's `Gesture`.
@MainActor
@preconcurrency
public protocol Gesture<Value> {
    /// A gesture built from another has that gesture's value.
    associatedtype Value = Body.Value
    associatedtype Body: Gesture

    var body: Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

/// A gesture that Parhelion recognizes itself, instead of through `body`.
@MainActor
protocol PrimitiveGesture {
    func makeRecognizer() -> GestureRecognizer
}

/// The recognizer for a gesture: its own, or the one of the gesture its
/// `body` returns.
@MainActor
func makeRecognizer<G: Gesture>(for gesture: G) -> GestureRecognizer {
    if let primitive = gesture as? any PrimitiveGesture { return primitive.makeRecognizer() }
    return makeRecognizer(for: gesture.body)
}

// MARK: - Coordinate spaces

/// What a gesture's location is measured in, mirroring SwiftUI's
/// `CoordinateSpaceProtocol`.
public protocol CoordinateSpaceProtocol {}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol {
    let name: AnyHashable
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(name))
    }
}

// MARK: - Gestures

/// A gesture that recognizes taps.
public struct TapGesture: Gesture, PrimitiveGesture {
    public typealias Value = Void
    public typealias Body = Never

    public var count: Int

    public init(count: Int = 1) {
        self.count = count
    }

    public var body: Never { fatalError("TapGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        TapRecognizer(count: count) { _ in () }
    }
}

/// A gesture that recognizes taps and reports where they were.
public struct SpatialTapGesture: Gesture, PrimitiveGesture {
    public typealias Body = Never

    public struct Value: Equatable, Sendable {
        /// Where the tap was, in the gesture's coordinate space.
        public var location: CGPoint
    }

    public var count: Int

    private let space: any CoordinateSpaceProtocol

    public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.count = count
        self.space = coordinateSpace
    }

    public var body: Never { fatalError("SpatialTapGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        let space = space
        return TapRecognizer(count: count, label: "spatialTap") { input in
            Value(location: input.location(in: space))
        }
    }
}

/// A gesture that recognizes a long press.
public struct LongPressGesture: Gesture, PrimitiveGesture {
    public typealias Value = Bool
    public typealias Body = Never

    public var minimumDuration: Double
    public var maximumDistance: CGFloat

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    public var body: Never { fatalError("LongPressGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        LongPressRecognizer(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
    }
}

/// A gesture that recognizes a drag.
public struct DragGesture: Gesture, PrimitiveGesture {
    public typealias Body = Never

    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize {
            CGSize(
                width: location.x - startLocation.x, height: location.y - startLocation.y)
        }
        /// How fast the pointer moved over its last 0.2 seconds, in points
        /// per second.
        public var velocity: CGSize = .zero
        /// Where the drag would come to rest if it coasted, as a scroll view
        /// does: half a second of the velocity.
        public var predictedEndLocation: CGPoint {
            CGPoint(x: location.x + velocity.width / 2, y: location.y + velocity.height / 2)
        }
        public var predictedEndTranslation: CGSize {
            CGSize(
                width: translation.width + velocity.width / 2,
                height: translation.height + velocity.height / 2)
        }

        init(time: Date, location: CGPoint, startLocation: CGPoint) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
        }
    }

    public var minimumDistance: CGFloat

    private let space: any CoordinateSpaceProtocol

    public init(
        minimumDistance: CGFloat = 10,
        coordinateSpace: some CoordinateSpaceProtocol = .local
    ) {
        self.minimumDistance = minimumDistance
        self.space = coordinateSpace
    }

    public var body: Never { fatalError("DragGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        DragRecognizer(minimumDistance: minimumDistance, space: space)
    }
}

// MARK: - Callbacks

/// A gesture with callbacks attached, returned by `onChanged(_:)`,
/// `onEnded(_:)`, and `updating(_:body:)`.
public struct _ModifiedGesture<Base: Gesture>: Gesture, PrimitiveGesture {
    public typealias Value = Base.Value

    let base: Base
    let handlers: GestureHandlers

    init(base: Base, handlers: GestureHandlers = GestureHandlers()) {
        self.base = base
        self.handlers = handlers
    }

    public var body: Base { base }

    func makeRecognizer() -> GestureRecognizer {
        ModifiedRecognizer(base: ParhelionUI.makeRecognizer(for: base), handlers: handlers)
    }
}

/// A value that a gesture sets while it is active and resets after,
/// mirroring SwiftUI's `GestureState`.
@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    let initialValue: Value
    let resetTransaction: Transaction
    let location: StateLocation<Value>

    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, resetTransaction: Transaction())
    }

    public init(initialValue: Value) {
        self.init(wrappedValue: initialValue, resetTransaction: Transaction())
    }

    public init(wrappedValue: Value, resetTransaction: Transaction) {
        initialValue = wrappedValue
        self.resetTransaction = resetTransaction
        location = StateLocation(StateBox(wrappedValue))
    }

    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: initialValue, resetTransaction: resetTransaction)
    }

    public init(
        wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void
    ) {
        self.init(wrappedValue: wrappedValue, resetTransaction: Transaction())
    }

    public init(
        initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void
    ) {
        self.init(wrappedValue: initialValue, resetTransaction: Transaction())
    }

    public var wrappedValue: Value { location.box.value }

    public var projectedValue: GestureState<Value> { self }

    /// Sets the value, and asks the host to evaluate the views again.
    @MainActor
    func set(_ value: Value, animation: Animation? = nil) {
        let box = location.box
        if let animation {
            withAnimation(animation) {
                box.value = value
                box.host?.setNeedsUpdate()
            }
        } else {
            box.value = value
            box.host?.setNeedsUpdate()
        }
    }

    /// Puts the initial value back, as the end of the gesture does.
    @MainActor
    func reset() {
        set(initialValue, animation: resetTransaction.animation)
    }
}

extension GestureState: StateInstallable {
    func install(in host: ViewHost, key: String) {
        location.box = host.stateBox(forKey: key, initialValue: initialValue)
    }
}

extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) {
        self.init(wrappedValue: nil, resetTransaction: resetTransaction)
    }
}

extension Gesture {
    public func onChanged(_ action: @escaping (Value) -> Void) -> _ModifiedGesture<Self> {
        _ModifiedGesture(
            base: self,
            handlers: GestureHandlers(onChanged: { action($0 as! Value) }))
    }

    public func onEnded(_ action: @escaping (Value) -> Void) -> _ModifiedGesture<Self> {
        _ModifiedGesture(
            base: self,
            handlers: GestureHandlers(onEnded: { action($0 as! Value) }))
    }

    public func updating<State>(
        _ state: GestureState<State>,
        body: @escaping (Value, inout State, inout Transaction) -> Void
    ) -> _ModifiedGesture<Self> {
        _ModifiedGesture(
            base: self,
            handlers: GestureHandlers(updating: { value in
                guard let value else {
                    state.reset()
                    return
                }
                var current = state.wrappedValue
                var transaction = Transaction()
                body(value as! Value, &current, &transaction)
                state.set(current, animation: transaction.animation)
            }))
    }
}

// MARK: - Combinations

/// A gesture that runs two gestures one after the other, mirroring SwiftUI's
/// `SequenceGesture`: the second begins when the first ends.
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    public typealias Body = Never

    public enum Value {
        case first(First.Value)
        case second(First.Value, Second.Value?)
    }

    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public var body: Never { fatalError("SequenceGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        SequenceRecognizer(
            first: ParhelionUI.makeRecognizer(for: first),
            second: ParhelionUI.makeRecognizer(for: second),
            wrapFirst: { Value.first($0 as! First.Value) },
            wrapSecond: { Value.second($0 as! First.Value, $1.map { $0 as! Second.Value }) })
    }
}

extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SequenceGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

/// A gesture that runs two gestures at the same time, mirroring SwiftUI's
/// `SimultaneousGesture`.
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    public typealias Body = Never

    public struct Value {
        public var first: First.Value?
        public var second: Second.Value?
    }

    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public var body: Never { fatalError("SimultaneousGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        SimultaneousRecognizer(
            first: ParhelionUI.makeRecognizer(for: first),
            second: ParhelionUI.makeRecognizer(for: second),
            combine: {
                Value(first: $0.map { $0 as! First.Value }, second: $1.map { $0 as! Second.Value })
            })
    }
}

extension SimultaneousGesture.Value: Equatable
where First.Value: Equatable, Second.Value: Equatable {}
extension SimultaneousGesture.Value: Sendable
where First.Value: Sendable, Second.Value: Sendable {}

/// A gesture that runs two gestures, and takes the first one that succeeds,
/// mirroring SwiftUI's `ExclusiveGesture`. The first has priority.
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    public typealias Body = Never

    public enum Value {
        case first(First.Value)
        case second(Second.Value)
    }

    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public var body: Never { fatalError("ExclusiveGesture is a primitive gesture.") }

    func makeRecognizer() -> GestureRecognizer {
        ExclusiveRecognizer(
            first: ParhelionUI.makeRecognizer(for: first),
            second: ParhelionUI.makeRecognizer(for: second),
            wrapFirst: { Value.first($0 as! First.Value) },
            wrapSecond: { Value.second($0 as! Second.Value) })
    }
}

extension ExclusiveGesture.Value: Equatable
where First.Value: Equatable, Second.Value: Equatable {}
extension ExclusiveGesture.Value: Sendable
where First.Value: Sendable, Second.Value: Sendable {}

extension Gesture {
    /// Combines this gesture with another that begins when this one ends.
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
        SequenceGesture(self, other)
    }

    /// Combines this gesture with another that can happen at the same time.
    public func simultaneously<Other: Gesture>(
        with other: Other
    )
        -> SimultaneousGesture<Self, Other>
    {
        SimultaneousGesture(self, other)
    }

    /// Combines this gesture with another that is recognized only if this one
    /// fails.
    public func exclusively<Other: Gesture>(
        before other: Other
    )
        -> ExclusiveGesture<Self, Other>
    {
        ExclusiveGesture(self, other)
    }
}

// MARK: - Modifiers

/// Which gestures a `gesture` modifier affects, mirroring SwiftUI's
/// `GestureMask`.
public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1 << 0)
    public static let subviews = GestureMask(rawValue: 1 << 1)
    public static let all: GestureMask = [.gesture, .subviews]
}

/// How a gesture competes with the gestures of the views around it.
enum GesturePriority: String {
    /// Views inside win over the view the gesture is on.
    case normal
    /// The gesture wins over the views inside.
    case high
    /// The gesture and the views inside all recognize the press.
    case simultaneous
}

extension View {
    /// Runs `action` when the view is tapped `count` times.
    public func onTapGesture(
        count: Int = 1, perform action: @escaping @MainActor () -> Void
    ) -> some View {
        let gesture = TapGesture(count: count).onEnded { _ in action() }
        return GestureView(
            content: self, name: count == 1 ? "onTapGesture" : "onTapGesture(count: \(count))",
            priority: .normal, mask: .all, isEnabled: true, isSugar: true
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Runs `action` with where the view is tapped, `count` times.
    public func onTapGesture(
        count: Int = 1,
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping @MainActor (CGPoint) -> Void
    ) -> some View {
        let gesture = SpatialTapGesture(count: count, coordinateSpace: coordinateSpace)
            .onEnded { action($0.location) }
        return GestureView(
            content: self, name: count == 1 ? "onTapGesture" : "onTapGesture(count: \(count))",
            priority: .normal, mask: .all, isEnabled: true, isSugar: true
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Runs `action` when the view is pressed for `minimumDuration` seconds
    /// without moving more than `maximumDistance` points. `onPressingChanged`
    /// runs when the press starts, with `true`, and when it ends or is
    /// recognized, with `false`.
    public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping @MainActor () -> Void,
        onPressingChanged: (@MainActor (Bool) -> Void)? = nil
    ) -> some View {
        let gesture = _ModifiedGesture(
            base: LongPressGesture(
                minimumDuration: minimumDuration, maximumDistance: maximumDistance),
            handlers: GestureHandlers(
                onChanged: { _ in onPressingChanged?(true) },
                onEnded: { _ in
                    onPressingChanged?(false)
                    action()
                },
                onFailed: { onPressingChanged?(false) }))
        let name =
            minimumDuration == 0.5
            ? "onLongPressGesture"
            : "onLongPressGesture(minimumDuration: \(formatPoints(CGFloat(minimumDuration))))"
        return GestureView(
            content: self, name: name, priority: .normal, mask: .all, isEnabled: true,
            isSugar: true
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture to the view. Gestures on views inside win over
    /// it, and `mask` chooses whether this gesture and the gestures of the
    /// views inside are recognized.
    public func gesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        GestureView(content: self, name: "gesture", priority: .normal, mask: mask, isEnabled: true)
        { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture to the view, or leaves it out while `isEnabled` is
    /// `false`.
    public func gesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        GestureView(
            content: self, name: "gesture", priority: .normal, mask: .all, isEnabled: isEnabled
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture that is recognized together with the gestures of
    /// the views inside.
    public func simultaneousGesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        GestureView(
            content: self, name: "simultaneousGesture", priority: .simultaneous, mask: mask,
            isEnabled: true
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture that is recognized together with the gestures of
    /// the views inside, or leaves it out while `isEnabled` is `false`.
    public func simultaneousGesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        GestureView(
            content: self, name: "simultaneousGesture", priority: .simultaneous, mask: .all,
            isEnabled: isEnabled
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture that wins over the gestures of the views inside.
    public func highPriorityGesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        GestureView(
            content: self, name: "highPriorityGesture", priority: .high, mask: mask,
            isEnabled: true
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }

    /// Attaches a gesture that wins over the gestures of the views inside,
    /// or leaves it out while `isEnabled` is `false`.
    public func highPriorityGesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        GestureView(
            content: self, name: "highPriorityGesture", priority: .high, mask: .all,
            isEnabled: isEnabled
        ) { ParhelionUI.makeRecognizer(for: gesture) }
    }
}

/// A view with a gesture attached.
///
/// The gesture goes on the nodes of the content as a layout modifier that
/// changes nothing but marks where the gesture sits in the chain: its bounds
/// are the gesture's area, and the outline shows it. The recognizer goes to
/// the host, which feeds it the pointer.
struct GestureView<Content: View>: View, PrimitiveView {
    typealias Body = Never

    let content: Content
    /// How the modifier is written, for the outline.
    let name: String
    let priority: GesturePriority
    let mask: GestureMask
    let isEnabled: Bool
    /// Whether `name` is the whole outline, as for `onTapGesture`, instead of
    /// the start of it.
    let isSugar: Bool
    let makeRecognizer: @MainActor () -> GestureRecognizer

    init(
        content: Content, name: String, priority: GesturePriority, mask: GestureMask,
        isEnabled: Bool, isSugar: Bool = false,
        makeRecognizer: @escaping @MainActor () -> GestureRecognizer
    ) {
        self.content = content
        self.isSugar = isSugar
        self.name = name
        self.priority = priority
        self.mask = mask
        self.isEnabled = isEnabled
        self.makeRecognizer = makeRecognizer
    }

    var body: Never { fatalError("GestureView is a primitive view.") }

    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard isEnabled else { return nodes }
        NodeExtensions.registerOnce(modifier: GestureModifier.name) {
            ModifierBehavior(outline: { $0["label"] ?? GestureModifier.name })
        }
        return nodes.map { node in
            var node = node
            let recognizer = makeRecognizer()
            // The sugar modifiers are named for what they are; `gesture`
            // names the gesture it takes.
            let label = isSugar ? name : "\(name)(\(recognizer.summary))"
            let ordinal = node.modifiers.filter(\.isGesture).count
            node.modifiers.append(
                .custom(
                    CustomModifier(
                        name: GestureModifier.name,
                        parameters: ["label": label, "priority": priority.rawValue])))
            evaluator.host.gestures.register(
                GestureRegistration(
                    nodeID: node.id, ordinal: ordinal, priority: priority, mask: mask,
                    recognizer: recognizer, make: makeRecognizer))
            return node
        }
    }
}

/// The name the gesture marker has in a node's modifier chain.
enum GestureModifier {
    static let name = "gesture"
}

extension LayoutModifier {
    /// Whether this is the marker a gesture modifier leaves.
    var isGesture: Bool {
        if case .custom(let custom) = self { return custom.name == GestureModifier.name }
        return false
    }
}
