/// A key for a value in ``EnvironmentValues``, mirroring SwiftUI's
/// `EnvironmentKey`.
public protocol EnvironmentKey {
    associatedtype Value

    /// The value when no view above has set one.
    static var defaultValue: Value { get }
}

/// Values that flow down the view hierarchy, mirroring SwiftUI's
/// `EnvironmentValues`.
///
/// A view reads a value with ``Environment`` and sets one for its content
/// with ``View/environment(_:_:)``.
public struct EnvironmentValues {
    private var values: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }
}

/// A property that reads a value from the environment, mirroring SwiftUI's
/// `Environment`.
///
/// The host sets the value before it reads the view's `body`.
@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    private let keyPath: KeyPath<EnvironmentValues, Value>
    let box = EnvironmentBox()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    @MainActor
    public var wrappedValue: Value {
        box.values[keyPath: keyPath]
    }
}

/// The environment an ``Environment`` property reads, set by the evaluator.
final class EnvironmentBox {
    var values = EnvironmentValues()
}

@MainActor
protocol EnvironmentInstallable {
    func install(_ values: EnvironmentValues)
}

extension Environment: EnvironmentInstallable {
    func install(_ values: EnvironmentValues) {
        box.values = values
    }
}

extension View {
    /// Sets an environment value for this view and its content.
    public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V
    ) -> some View {
        EnvironmentWriter(content: self) { $0[keyPath: keyPath] = value }
    }
}

/// A view that changes the environment of its content.
struct EnvironmentWriter<Content: View>: View {
    typealias Body = Never

    let content: Content
    let transform: (inout EnvironmentValues) -> Void

    var body: Never {
        fatalError("EnvironmentWriter is a primitive view and has no body.")
    }
}

extension EnvironmentWriter: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.withEnvironment(transform) {
            evaluator.evaluate(content, at: path)
        }
    }
}

// MARK: - Presentation values

/// An action that dismisses the view it is read from: a sheet, an alert's
/// content, or a view pushed onto a ``NavigationStack``. Mirrors SwiftUI's
/// `DismissAction`.
public struct DismissAction {
    let action: @MainActor () -> Void

    @MainActor
    public func callAsFunction() {
        action()
    }
}

struct DismissKey: EnvironmentKey {
    static var defaultValue: DismissAction { DismissAction {} }
}

struct IsPresentedKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Dismisses the current presentation: closes a sheet, or pops a view
    /// pushed onto a navigation stack. Does nothing elsewhere.
    public var dismiss: DismissAction {
        self[DismissKey.self]
    }

    /// Whether the view is in a sheet or pushed onto a navigation stack.
    public var isPresented: Bool {
        self[IsPresentedKey.self]
    }

    /// The environment of a presented view, which `dismiss` dismisses.
    func presenting(dismiss: @escaping @MainActor () -> Void) -> EnvironmentValues {
        var values = self
        values[DismissKey.self] = DismissAction(action: dismiss)
        values[IsPresentedKey.self] = true
        return values
    }
}
