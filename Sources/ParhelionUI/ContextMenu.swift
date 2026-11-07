extension View {
    /// A compile-only stub that ignores the menu. Issue #58 shows it on a
    /// long press.
    public func contextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        self
    }

    /// A compile-only stub that ignores the menu and the preview. Issue #58
    /// shows them on a long press.
    public func contextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        self
    }
}
