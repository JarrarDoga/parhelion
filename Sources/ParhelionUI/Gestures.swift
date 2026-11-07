import Foundation

/// A gesture, mirroring SwiftUI's `Gesture`. Compile-only stubs: none of
/// them recognizes input. Issue #56 does.
@MainActor
@preconcurrency
public protocol Gesture<Value> {
    associatedtype Value
    associatedtype Body: Gesture

    var body: Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

/// A gesture with a handler attached.
public struct _ModifiedGesture<Base: Gesture>: Gesture {
    public typealias Value = Base.Value

    let base: Base

    public var body: Base { base }
}

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

/// A gesture that recognizes taps.
public struct TapGesture: Gesture {
    public typealias Value = Void
    public typealias Body = Never

    public var count: Int

    public init(count: Int = 1) {
        self.count = count
    }

    public var body: Never { fatalError("TapGesture is a primitive gesture.") }
}

/// A gesture that recognizes a long press.
public struct LongPressGesture: Gesture {
    public typealias Value = Bool
    public typealias Body = Never

    public var minimumDuration: Double
    public var maximumDistance: CGFloat

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    public var body: Never { fatalError("LongPressGesture is a primitive gesture.") }
}

/// A gesture that recognizes a drag.
public struct DragGesture: Gesture {
    public typealias Body = Never

    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize {
            CGSize(
                width: location.x - startLocation.x, height: location.y - startLocation.y)
        }
        public var velocity: CGSize = .zero
        public var predictedEndLocation: CGPoint { location }
        public var predictedEndTranslation: CGSize { translation }

        init(time: Date, location: CGPoint, startLocation: CGPoint) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
        }
    }

    public var minimumDistance: CGFloat

    public init(
        minimumDistance: CGFloat = 10,
        coordinateSpace: some CoordinateSpaceProtocol = .local
    ) {
        self.minimumDistance = minimumDistance
    }

    public var body: Never { fatalError("DragGesture is a primitive gesture.") }
}

/// A value that a gesture sets while it is active and resets after,
/// mirroring SwiftUI's `GestureState`.
@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    let box: Box

    public init(wrappedValue: Value) {
        box = Box(wrappedValue)
    }

    public init(initialValue: Value) {
        box = Box(initialValue)
    }

    public init(wrappedValue: Value, resetTransaction: Transaction) {
        box = Box(wrappedValue)
    }

    public init(initialValue: Value, resetTransaction: Transaction) {
        box = Box(initialValue)
    }

    public var wrappedValue: Value { box.value }

    public var projectedValue: GestureState<Value> { self }
}

extension Gesture {
    public func onChanged(_ action: @escaping (Value) -> Void) -> _ModifiedGesture<Self> {
        _ModifiedGesture(base: self)
    }

    public func onEnded(_ action: @escaping (Value) -> Void) -> _ModifiedGesture<Self> {
        _ModifiedGesture(base: self)
    }

    public func updating<State>(
        _ state: GestureState<State>,
        body: @escaping (Value, inout State, inout Transaction) -> Void
    ) -> _ModifiedGesture<Self> {
        _ModifiedGesture(base: self)
    }
}

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

extension View {
    public func onTapGesture(
        count: Int = 1, perform action: @escaping @MainActor () -> Void
    ) -> some View {
        self
    }

    public func onTapGesture(
        count: Int = 1,
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping @MainActor (CGPoint) -> Void
    ) -> some View {
        self
    }

    public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping @MainActor () -> Void,
        onPressingChanged: (@MainActor (Bool) -> Void)? = nil
    ) -> some View {
        self
    }

    public func gesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        self
    }

    public func simultaneousGesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        self
    }

    public func highPriorityGesture<G: Gesture>(
        _ gesture: G, including mask: GestureMask = .all
    ) -> some View {
        self
    }
}
