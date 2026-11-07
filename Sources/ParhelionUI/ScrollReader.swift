import Foundation

// ScrollViewReader, ScrollViewProxy.scrollTo, and View.id(_:): scrolling to
// a view by its identifier. The scroll itself happens in layout; see
// ScrollPosition.swift for how a request is applied.

/// The nodes a ``ScrollViewReader``'s content resolved to, which a proxy
/// searches first.
@MainActor
final class ScrollReaderScope {
    var roots: [NodeID] = []
}

/// A proxy that scrolls the scroll views inside a ``ScrollViewReader``,
/// mirroring SwiftUI's `ScrollViewProxy`.
public struct ScrollViewProxy {
    private weak var host: ViewHost?
    private let scope: ScrollReaderScope

    init(host: ViewHost, scope: ScrollReaderScope) {
        self.host = host
        self.scope = scope
    }

    /// Scrolls the first scroll view that contains a view with the
    /// identifier `id` so that the view is at `anchor` in the visible
    /// region, or, without an anchor, by the least that makes the view
    /// visible. Both a view's `id(_:)` and the identifier of a `ForEach`
    /// element name a view. Inside `withAnimation`, the scroll animates.
    ///
    /// The scroll applies at the next update of the host, which every
    /// interaction on ``ViewHost`` runs, so it sees changes the same action
    /// made to the views.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        // Actions run on the main actor, as SwiftUI's do; the check is
        // here because the closures that call this are not marked.
        nonisolated(unsafe) let identifier = AnyHashable(id)
        let scope = scope
        let host = host
        MainActor.assumeIsolated {
            host?.requestScroll(
                ScrollRequest(
                    destination: .id(identifier, anchor), scrollView: nil, scope: scope.roots))
        }
    }
}

/// A view that gives its content a ``ScrollViewProxy``, mirroring SwiftUI's
/// `ScrollViewReader`. The reader is invisible: its node is its content's.
public struct ScrollViewReader<Content: View>: View {
    public typealias Body = Never

    let content: (ScrollViewProxy) -> Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: Never {
        fatalError("ScrollViewReader is a primitive view and has no body.")
    }
}

extension ScrollViewReader: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let scope = ScrollReaderScope()
        let proxy = ScrollViewProxy(host: evaluator.host, scope: scope)
        let nodes = evaluator.evaluate(content(proxy), at: path.appending("ScrollViewReader"))
        scope.roots = nodes.map(\.id)
        return nodes
    }
}

// MARK: - id(_:)

/// A view with an identity, from `id(_:)`.
struct IdentifiedView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let identifier: AnyHashable

    var body: Never {
        fatalError("IdentifiedView is a primitive view and has no body.")
    }
}

extension IdentifiedView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        // The identifier is part of the view's identity, so a view with a
        // new one starts with fresh state, as in SwiftUI.
        let name = Self.name(of: identifier)
        let nodes = evaluator.evaluate(content, at: path.appending("id[\(name)]"))
        return nodes.map { node in
            var node = node
            // The innermost identifier names a view, as in SwiftUI.
            if node.attributes["viewID"] == nil {
                node.attributes["viewID"] = name
                evaluator.scrollRecord.targets[node.id] = identifier
            }
            return node
        }
    }

    /// The identifier as text, with its type so that `1` and `"1"` differ.
    static func name(of identifier: AnyHashable) -> String {
        "\(type(of: identifier.base)):\(identifier.base)"
    }
}

extension View {
    /// Binds a view's identity to `id`. Another value gives the view a new
    /// identity, which resets its state. A scroll view can scroll to the
    /// view by its identifier, with ``ScrollViewProxy/scrollTo(_:anchor:)``
    /// or `scrollPosition(id:)`.
    public func id<ID: Hashable>(_ id: ID) -> some View {
        IdentifiedView(content: self, identifier: AnyHashable(id))
    }
}
