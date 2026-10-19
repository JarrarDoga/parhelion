/// A property of a view that the host updates before evaluating `body`.
public protocol DynamicProperty {}

/// Storage that the ``ViewHost`` owns and keeps across view updates.
final class StateBox<Value> {
    var value: Value
    weak var host: ViewHost?

    init(_ value: Value) {
        self.value = value
    }
}

/// The per-instance handle a ``State`` uses to reach its storage.
///
/// Views are values and are recreated on every update. Each new instance of
/// a view starts with a fresh location, and the evaluator points it at the
/// storage that belongs to the view's structural position.
final class StateLocation<Value> {
    var box: StateBox<Value>

    init(_ box: StateBox<Value>) {
        self.box = box
    }
}

@MainActor
protocol StateInstallable {
    func install(in host: ViewHost, key: String)
}

/// A value that a view owns and that triggers an update when it changes.
///
/// Parhelion keeps the value for as long as the view stays at the same position
/// in the tree, the same lifetime rules as SwiftUI's `State`.
@propertyWrapper
public struct State<Value>: DynamicProperty {
    private let initialValue: Value
    let location: StateLocation<Value>

    public init(wrappedValue value: Value) {
        initialValue = value
        location = StateLocation(StateBox(value))
    }

    public init(initialValue value: Value) {
        self.init(wrappedValue: value)
    }

    @MainActor
    public var wrappedValue: Value {
        get { location.box.value }
        nonmutating set {
            location.box.value = newValue
            location.box.host?.setNeedsUpdate()
        }
    }

    @MainActor
    public var projectedValue: Binding<Value> {
        let location = location
        return Binding(
            get: { location.box.value },
            set: { newValue in
                location.box.value = newValue
                location.box.host?.setNeedsUpdate()
            }
        )
    }
}

extension State: StateInstallable {
    func install(in host: ViewHost, key: String) {
        location.box = host.stateBox(forKey: key, initialValue: initialValue)
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() {
        self.init(wrappedValue: nil)
    }
}

/// A two-way connection to a value owned by something else.
@propertyWrapper
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    public init(
        get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value) -> Void
    ) {
        getValue = get
        setValue = set
    }

    /// A binding to a value that never changes.
    @MainActor
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    @MainActor
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }

    public var projectedValue: Binding<Value> { self }
}
