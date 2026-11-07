import Foundation

/// The values of a scroll view's geometry, mirroring SwiftUI's
/// `ScrollGeometry`.
public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize

    public var visibleRect: CGRect {
        CGRect(origin: contentOffset, size: containerSize)
    }

    public var bounds: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    public init(
        contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets,
        containerSize: CGSize
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }
}

/// A scroll view's position, mirroring SwiftUI's `ScrollPosition`.
public struct ScrollPosition: Equatable {
    public var edge: Edge?
    public var point: CGPoint?
    public var x: CGFloat?
    public var y: CGFloat?
    public internal(set) var isPositionedByUser: Bool = false
    var id: AnyHashable?
    var anchor: UnitPoint?

    public init() {}

    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        self.id = AnyHashable(id)
        self.anchor = anchor
    }

    public init(edge: Edge) {
        self.edge = edge
    }

    public init(point: CGPoint) {
        self.point = point
    }

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public var viewID: (any Hashable)? { id?.base as? any Hashable }

    public func viewID<ID: Hashable>(type: ID.Type) -> ID? { id?.base as? ID }

    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        self = ScrollPosition(id: id, anchor: anchor)
    }

    public mutating func scrollTo(edge: Edge) { self = ScrollPosition(edge: edge) }
    public mutating func scrollTo(point: CGPoint) { self = ScrollPosition(point: point) }
    public mutating func scrollTo(x: CGFloat) { self.x = x }
    public mutating func scrollTo(y: CGFloat) { self.y = y }
}

/// How a scroll view settles, mirroring SwiftUI's `ScrollTargetBehavior`.
/// Custom behaviors are not supported.
public protocol ScrollTargetBehavior {}

public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {}
}

public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    public struct LimitBehavior: Hashable, Sendable {
        let name: String

        public static let automatic = LimitBehavior(name: "automatic")
        public static let always = LimitBehavior(name: "always")
        public static let never = LimitBehavior(name: "never")
    }

    public init() {}

    public init(limitBehavior: LimitBehavior = .automatic) {}
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    public static var viewAligned: ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior()
    }

    public static func viewAligned(
        limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior = .automatic
    ) -> ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }
}

extension View {
    /// A compile-only stub: the binding never changes. Issue #60 tracks the
    /// scroll position.
    public func scrollPosition<ID: Hashable>(
        id: Binding<ID?>, anchor: UnitPoint? = nil
    ) -> some View {
        self
    }

    /// A compile-only stub: the binding never changes. Issue #60 tracks the
    /// scroll position.
    public func scrollPosition(
        _ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil
    ) -> some View {
        self
    }

    /// A compile-only stub. Issue #60 settles on pages.
    public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        self
    }

    /// A compile-only stub. Issue #60 lays out scroll targets.
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        self
    }

    /// A compile-only stub that never calls the action. Issue #60 reports
    /// the geometry.
    public func onScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        self
    }
}
