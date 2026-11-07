/// Where a tab view's bottom accessory is, mirroring SwiftUI's
/// `TabViewBottomAccessoryPlacement`.
public enum TabViewBottomAccessoryPlacement: Equatable, Sendable {
    case expanded
    case inline
}

struct TabViewBottomAccessoryPlacementKey: EnvironmentKey {
    static var defaultValue: TabViewBottomAccessoryPlacement? { nil }
}

extension EnvironmentValues {
    /// Where the bottom accessory is. `nil` outside one.
    public var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement? {
        get { self[TabViewBottomAccessoryPlacementKey.self] }
        set { self[TabViewBottomAccessoryPlacementKey.self] = newValue }
    }
}

extension View {
    /// A compile-only stub that draws no accessory. Issue #55 draws it.
    public func tabViewBottomAccessory<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        self
    }

    /// A compile-only stub that draws no accessory. Issue #55 draws it.
    public func tabViewBottomAccessory<Content: View>(
        isEnabled: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        self
    }
}
