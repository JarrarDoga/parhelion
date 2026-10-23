import Observation

// MARK: - Bindings to parts of a value

extension Binding {
    /// A binding to a property of the value, such as `$profile.name`.
    @MainActor
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

extension Binding: @MainActor Identifiable where Value: Identifiable {
    /// The identifier of the value.
    @MainActor
    public var id: Value.ID { wrappedValue.id }
}

extension Binding where Value: MutableCollection {
    /// A binding to the element at `position`.
    ///
    /// When the element is `Identifiable`, the binding finds it by its
    /// identifier on every read and write, so it stays with its element
    /// when elements before it are inserted or removed. Otherwise it follows
    /// `position`.
    @MainActor
    func element(at position: Value.Index) -> Binding<Value.Element> {
        element(at: position, identifiedBy: identifier(of:))
    }

    /// A binding to the element at `position`, which finds the element again
    /// by the value `identity` gives it, or by `position` when `identity`
    /// gives `nil`.
    ///
    /// Once the element is gone, for example because a row's element was
    /// removed while the row was still on screen, reading the binding
    /// returns the last value it read or wrote, and writing it does nothing.
    @MainActor
    func element(
        at position: Value.Index,
        identifiedBy identity: @escaping (Value.Element) -> AnyHashable?
    ) -> Binding<Value.Element> {
        let last = LastValue(wrappedValue[position])
        let id = identity(last.value)
        func index(in collection: Value) -> Value.Index? {
            let hasPosition = position >= collection.startIndex && position < collection.endIndex
            guard let id else { return hasPosition ? position : nil }
            if hasPosition, identity(collection[position]) == id { return position }
            return collection.firstIndex { identity($0) == id }
        }
        return Binding<Value.Element>(
            get: {
                let collection = self.wrappedValue
                if let index = index(in: collection) { last.value = collection[index] }
                return last.value
            },
            set: { newValue in
                var collection = self.wrappedValue
                guard let index = index(in: collection) else { return }
                collection[index] = newValue
                last.value = newValue
                self.wrappedValue = collection
            }
        )
    }
}

/// The identifier of a value that is `Identifiable`, or `nil`.
private func identifier(of value: Any) -> AnyHashable? {
    guard let value = value as? any Identifiable else { return nil }
    return identifier(value)
}

private func identifier<Element: Identifiable>(_ element: Element) -> AnyHashable {
    AnyHashable(element.id)
}

/// The last value an element binding read or wrote.
private final class LastValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// A binding reads its value on the main actor, so a binding to a collection
// is a collection only there.

extension Binding: @MainActor Sequence where Value: MutableCollection {
    public typealias Element = Binding<Value.Element>
    public typealias Iterator = IndexingIterator<Binding<Value>>
    public typealias SubSequence = Slice<Binding<Value>>
}

@MainActor
extension Binding: @MainActor Collection where Value: MutableCollection {
    public typealias Index = Value.Index
    public typealias Indices = Value.Indices

    public var startIndex: Index { wrappedValue.startIndex }

    public var endIndex: Index { wrappedValue.endIndex }

    public var indices: Value.Indices { wrappedValue.indices }

    public func index(after i: Index) -> Index {
        wrappedValue.index(after: i)
    }

    public func formIndex(after i: inout Index) {
        wrappedValue.formIndex(after: &i)
    }

    public subscript(position: Index) -> Binding<Value.Element> {
        element(at: position)
    }
}

@MainActor
extension Binding: @MainActor BidirectionalCollection
where Value: BidirectionalCollection, Value: MutableCollection {
    public func index(before i: Index) -> Index {
        wrappedValue.index(before: i)
    }

    public func formIndex(before i: inout Index) {
        wrappedValue.formIndex(before: &i)
    }
}

extension Binding: @MainActor RandomAccessCollection
where Value: MutableCollection, Value: RandomAccessCollection {}

// MARK: - Bindable

/// A property wrapper that makes bindings to the properties of an
/// observable object, mirroring SwiftUI's `Bindable`.
///
/// `$model.name` is a `Binding` that reads and writes `model.name`. Use it
/// for a model that a view receives, or declare a local one in `body` for a
/// model read from the environment:
///
/// ```swift
/// @Environment(Library.self) private var library
///
/// var body: some View {
///     @Bindable var library = library
///     TextField("Name", text: $library.name)
/// }
/// ```
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value> {
    /// The object.
    public var wrappedValue: Value

    /// The bindable itself, so that `$model.name` makes a binding.
    public var projectedValue: Bindable<Value> { self }

    @available(*, unavailable, message: "Bindable needs an object that conforms to Observable")
    public init(wrappedValue: Value) {
        fatalError("Bindable needs an object that conforms to Observable.")
    }

    @available(*, unavailable, message: "Bindable needs an object that conforms to Observable")
    public init(projectedValue: Bindable<Value>) {
        fatalError("Bindable needs an object that conforms to Observable.")
    }
}

extension Bindable where Value: AnyObject, Value: Observable {
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public init(_ wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue)
    }

    public init(projectedValue: Bindable<Value>) {
        self = projectedValue
    }
}

extension Bindable where Value: AnyObject {
    /// A binding to a property of the object.
    @MainActor
    public subscript<Subject>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        let object = wrappedValue
        return Binding(
            get: { object[keyPath: keyPath] },
            set: { object[keyPath: keyPath] = $0 }
        )
    }
}

extension Bindable: Identifiable where Value: Identifiable {
    /// The identifier of the object.
    public var id: Value.ID { wrappedValue.id }
}

extension Bindable: Sendable where Value: Sendable {}

extension Bindable: DynamicProperty {}
