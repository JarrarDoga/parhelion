/// A piece of user interface, described as a value.
///
/// Parhelion mirrors SwiftUI's `View` protocol. A custom view composes other
/// views in ``body``; primitive views such as ``Text`` and ``VStack`` have a
/// body of type `Never` and are resolved directly by the ``ViewHost``.
@MainActor
@preconcurrency
public protocol View {
    associatedtype Body: View

    @ViewBuilder
    var body: Body { get }
}

extension Never: View {
    public var body: Never {
        fatalError("Never has no body.")
    }
}

/// A view that displays nothing.
public struct EmptyView: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("EmptyView is a primitive view and has no body.")
    }
}

/// A view built from several child views, produced by ``ViewBuilder``.
public struct TupleView<T>: View {
    public typealias Body = Never

    public var value: T
    let elements: [any View]

    init(value: T, elements: [any View]) {
        self.value = value
        self.elements = elements
    }

    public var body: Never {
        fatalError("TupleView is a primitive view and has no body.")
    }
}

/// A view that shows one of two views, produced by `if`/`else` in a
/// ``ViewBuilder``.
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View {
    public typealias Body = Never

    enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    let storage: Storage

    public var body: Never {
        fatalError("_ConditionalContent is a primitive view and has no body.")
    }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Optional is a primitive view and has no body.")
    }
}

/// Builds views from closures, mirroring SwiftUI's `ViewBuilder`.
@MainActor
@resultBuilder
public enum ViewBuilder {
    public static func buildExpression<Content: View>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<each Content: View>(
        _ content: repeat each Content
    ) -> TupleView<(repeat each Content)> {
        var elements: [any View] = []
        for element in repeat each content {
            elements.append(element)
        }
        return TupleView(value: (repeat each content), elements: elements)
    }

    public static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .falseContent(second))
    }

    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> Content {
        content
    }
}
