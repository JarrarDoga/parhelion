import Foundation

/// A view that generates its content from a collection, mirroring SwiftUI's
/// `DynamicViewContent`.
public protocol DynamicViewContent: View {
    associatedtype Data: Collection

    var data: Data { get }
}

extension ForEach: DynamicViewContent {}

/// The result of `onMove` and `onDelete`: the content, unchanged.
public struct _DynamicContentModifier<Content: DynamicViewContent>: DynamicViewContent {
    let content: Content

    public var data: Content.Data { content.data }

    public var body: some View { content }
}

extension DynamicViewContent {
    /// A compile-only stub that never calls the action. Issue #75 adds
    /// reordering.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent {
        _DynamicContentModifier(content: self)
    }

    /// A compile-only stub that never calls the action. Issue #75 adds
    /// deletion.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some DynamicViewContent {
        _DynamicContentModifier(content: self)
    }
}

/// Whether a list is being edited, mirroring SwiftUI's `EditMode`.
public enum EditMode: Sendable {
    case inactive
    case transient
    case active

    public var isEditing: Bool { self != .inactive }
}

struct EditModeKey: EnvironmentKey {
    static var defaultValue: Binding<EditMode>? { nil }
}

extension EnvironmentValues {
    /// The edit mode that a view above set. `nil` until one does.
    public var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}
