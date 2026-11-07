/// A haptic or sound, mirroring SwiftUI's `SensoryFeedback`.
public struct SensoryFeedback: Equatable, Sendable {
    let name: String

    public struct Weight: Equatable, Sendable {
        let name: String
        public static let light = Weight(name: "light")
        public static let medium = Weight(name: "medium")
        public static let heavy = Weight(name: "heavy")
    }

    public struct Flexibility: Equatable, Sendable {
        let name: String
        public static let rigid = Flexibility(name: "rigid")
        public static let solid = Flexibility(name: "solid")
        public static let soft = Flexibility(name: "soft")
    }

    public static let success = SensoryFeedback(name: "success")
    public static let warning = SensoryFeedback(name: "warning")
    public static let error = SensoryFeedback(name: "error")
    public static let selection = SensoryFeedback(name: "selection")
    public static let increase = SensoryFeedback(name: "increase")
    public static let decrease = SensoryFeedback(name: "decrease")
    public static let start = SensoryFeedback(name: "start")
    public static let stop = SensoryFeedback(name: "stop")
    public static let alignment = SensoryFeedback(name: "alignment")
    public static let levelChange = SensoryFeedback(name: "levelChange")
    public static let impact = SensoryFeedback(name: "impact")

    public static func impact(
        weight: Weight = .medium, intensity: Double = 1.0
    )
        -> SensoryFeedback
    {
        SensoryFeedback(name: "impact.\(weight.name)")
    }

    public static func impact(
        flexibility: Flexibility, intensity: Double = 1.0
    )
        -> SensoryFeedback
    {
        SensoryFeedback(name: "impact.\(flexibility.name)")
    }
}

extension View {
    /// A compile-only stub that plays nothing. Issue #62 records the
    /// feedback.
    public func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback, trigger: T
    ) -> some View {
        self
    }

    /// A compile-only stub that plays nothing. Issue #62 records the
    /// feedback.
    public func sensoryFeedback<T: Equatable>(
        trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?
    ) -> some View {
        self
    }

    /// A compile-only stub that plays nothing. Issue #62 records the
    /// feedback.
    public func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback, trigger: T, condition: @escaping (T, T) -> Bool
    ) -> some View {
        self
    }
}
