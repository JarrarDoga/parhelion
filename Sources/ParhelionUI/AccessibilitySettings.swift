struct AccessibilityReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the user asked to reduce motion. It is `false` unless the
    /// host's ``ViewHost/reduceMotion`` is on, which the preview window,
    /// `parhelion mcp`, and `PARHELION_REDUCE_MOTION=1` set.
    public var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}
