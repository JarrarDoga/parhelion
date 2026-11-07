/// Which geometry `matchedGeometryEffect` matches, mirroring SwiftUI's
/// `MatchedGeometryProperties`.
public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

/// How a navigation push or a presentation animates, mirroring SwiftUI's
/// `NavigationTransition`.
public protocol NavigationTransition {}

public struct AutomaticNavigationTransition: NavigationTransition {
    public init() {}
}

public struct ZoomNavigationTransition: NavigationTransition {
    let sourceID: AnyHashable
    let namespace: Namespace.ID
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    public static var automatic: AutomaticNavigationTransition {
        AutomaticNavigationTransition()
    }
}

extension NavigationTransition where Self == ZoomNavigationTransition {
    public static func zoom(
        sourceID: some Hashable, in namespace: Namespace.ID
    ) -> ZoomNavigationTransition {
        ZoomNavigationTransition(sourceID: AnyHashable(sourceID), namespace: namespace)
    }
}

extension View {
    /// A compile-only stub: nothing moves between views. Issue #78 moves it.
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        self
    }

    /// A compile-only stub. Issue #78 zooms from this view.
    public func matchedTransitionSource<ID: Hashable>(
        id: ID, in namespace: Namespace.ID
    ) -> some View {
        self
    }

    /// A compile-only stub. Issue #78 zooms.
    public func navigationTransition(_ style: some NavigationTransition) -> some View {
        self
    }
}
