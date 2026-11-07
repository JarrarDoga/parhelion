extension View {
    /// A compile-only stub that never calls the action. Issue #74 adds
    /// pull to refresh.
    public func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
        self
    }
}
