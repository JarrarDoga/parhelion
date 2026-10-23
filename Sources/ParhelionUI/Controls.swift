#if canImport(Foundation)
import Foundation
#endif

// MARK: - Enabling and disabling

struct IsEnabledKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// Whether controls in the view respond to input. ``View/disabled(_:)``
    /// turns it off for a view's content.
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

extension View {
    /// Turns off the controls in the view when `disabled` is `true`: they
    /// draw dimmed, do not respond to taps or drags, and record a `disabled`
    /// attribute. A `disabled(false)` inside a disabled view does not enable
    /// its content again.
    public func disabled(_ disabled: Bool) -> some View {
        EnvironmentWriter(content: self) { $0.isEnabled = $0.isEnabled && !disabled }
    }
}

// MARK: - Shared evaluation

extension Evaluator {
    /// Host-owned storage for a control at a structural position, kept for as
    /// long as the control is evaluated there. Writing to it does not update
    /// the tree.
    func controlBox<Value>(_ id: NodeID, _ name: String, initialValue: Value) -> StateBox<Value> {
        host.stateBox(forKey: "\(id.rawValue)#\(name)", initialValue: initialValue)
    }

    /// Animates the nodes with the given identifiers with `animation` when
    /// `value` changed since the last update, the way an
    /// `animation(_:value:)` modifier does.
    func animate<V: Equatable>(
        _ ids: [NodeID], with animation: Animation, whenChanged value: V, key: NodeID
    ) {
        guard host.animationValueChanged(forKey: "\(key.rawValue)|control", to: value) else {
            return
        }
        for id in ids where implicitAnimations[id] == nil {
            implicitAnimations[id] = .some(animation)
        }
    }

    /// Records `disabled=true` on a control's node when controls are turned
    /// off here.
    func markDisabled(_ attributes: inout [String: String]) {
        if !environment.isEnabled { attributes["disabled"] = "true" }
    }
}

extension ViewNode {
    /// Whether the node is a control turned off with ``View/disabled(_:)``.
    var isDisabled: Bool {
        attributes["disabled"] == "true"
    }
}
