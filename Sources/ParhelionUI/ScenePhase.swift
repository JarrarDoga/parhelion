/// Where a scene is in its life cycle, mirroring SwiftUI's `ScenePhase`.
public enum ScenePhase: Hashable, Comparable, Sendable {
    case background
    case inactive
    case active

    /// The case's name, as `PreviewCommand.setScenePhase` and the root
    /// node's `scenePhase` attribute spell it.
    var name: String {
        switch self {
        case .background: "background"
        case .inactive: "inactive"
        case .active: "active"
        }
    }

    /// The phase a ``name`` names.
    init?(name: String) {
        switch name {
        case "background": self = .background
        case "inactive": self = .inactive
        case "active": self = .active
        default: return nil
        }
    }
}

struct ScenePhaseKey: EnvironmentKey {
    static var defaultValue: ScenePhase { .active }
}

extension EnvironmentValues {
    /// The phase of the scene: the host's ``ViewHost/scenePhase``, `active`
    /// by default. Read it in a view, or in an `App`, where it is the phase
    /// of the app's scenes.
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}

// MARK: - Scene.onChange

/// A scene with an `onChange(of:)` modifier. It shows the window of the scene
/// it wraps, with the action on the window's content, so the action runs
/// after the update in which the value changed, as a view's does.
struct _OnChangeScene<Content: Scene>: Scene, WindowContentProviding {
    typealias Body = Never

    let content: Content
    let observer: ChangeObserver

    var body: Never {
        fatalError("A scene with onChange is a primitive scene and has no body.")
    }

    var windowContent: any View {
        guard let window = ParhelionUI.windowContent(of: content) else { return EmptyView() }
        return LifecycleView(content: AnyView(window), handler: .change(observer))
    }
}

extension Scene {
    /// Runs `action` with the old and new values after an update in which
    /// `value` changed. With `initial`, it also runs when the scene first
    /// appears, with the value as both. Read `scenePhase` with
    /// `@Environment` in the `App` to react to it here.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some Scene {
        _OnChangeScene(
            content: self,
            observer: ChangeObserver(value: value, initial: initial, action: action))
    }

    /// Runs `action` after an update in which `value` changed. With
    /// `initial`, it also runs when the scene first appears.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some Scene {
        onChange(of: value, initial: initial) { _, _ in action() }
    }
}
