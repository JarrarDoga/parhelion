/// When a tab bar shrinks, mirroring SwiftUI's `TabBarMinimizeBehavior`.
public struct TabBarMinimizeBehavior: Hashable, Sendable {
    let name: String

    public static let automatic = TabBarMinimizeBehavior(name: "automatic")
    public static let onScrollDown = TabBarMinimizeBehavior(name: "onScrollDown")
    public static let onScrollUp = TabBarMinimizeBehavior(name: "onScrollUp")
    public static let never = TabBarMinimizeBehavior(name: "never")
}

extension View {
    /// A compile-only stub: the tab bar never shrinks. Issue #55 shrinks it.
    public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View {
        self
    }
}
