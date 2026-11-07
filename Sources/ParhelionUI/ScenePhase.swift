/// Where an app is in its life cycle, mirroring SwiftUI's `ScenePhase`.
public enum ScenePhase: Hashable, Sendable {
    case background
    case inactive
    case active
}

struct ScenePhaseKey: EnvironmentKey {
    static var defaultValue: ScenePhase { .active }
}

extension EnvironmentValues {
    /// The phase of the scene. Always `.active` until issue #63.
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}
