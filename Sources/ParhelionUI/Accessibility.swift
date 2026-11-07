/// How an accessibility element treats the views inside it, as
/// `accessibilityElement(children:)` takes it.
public struct AccessibilityChildBehavior: Hashable, Sendable {
    let name: String

    /// The children are hidden. The element has only the properties set on it.
    public static let ignore = AccessibilityChildBehavior(name: "ignore")
    /// The element merges its children: its label joins theirs.
    public static let combine = AccessibilityChildBehavior(name: "combine")
    /// The children stay separate elements inside this one.
    public static let contain = AccessibilityChildBehavior(name: "contain")
}

extension View {
    /// Identifies the view for tests and tools. The identifier is not
    /// visible to the user.
    ///
    /// On a view that is not an accessibility element, such as a stack, the
    /// identifier applies to every element inside it and replaces theirs, as
    /// in SwiftUI. Add `accessibilityElement(children: .contain)` first to
    /// identify the container itself.
    public func accessibilityIdentifier(_ identifier: String) -> some View {
        attributeModifier(AccessibilityKey.identifier, identifier)
    }

    /// Gives the view a label for assistive technologies and tools to use
    /// instead of its content, such as for an icon.
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View {
        attributeModifier(AccessibilityKey.label, String(label))
    }

    /// Gives the view a label for assistive technologies and tools to use
    /// instead of its content, such as for an icon.
    public func accessibilityLabel(_ label: Text) -> some View {
        attributeModifier(AccessibilityKey.label, label.content)
    }

    /// Makes the view an accessibility element and chooses what happens to
    /// the views inside it.
    public func accessibilityElement(
        children: AccessibilityChildBehavior = .ignore
    ) -> some View {
        attributeModifier(AccessibilityKey.element, children.name)
    }
}

/// The attribute keys the accessibility modifiers record.
enum AccessibilityKey {
    static let identifier = "accessibilityIdentifier"
    static let label = "accessibilityLabel"
    static let element = "accessibilityElement"
}

/// The result of looking for the one view an accessibility identifier names.
enum AccessibilityResolution: Equatable {
    /// The identifier names no view that is on screen.
    case none
    /// The identifier names views, but none of the kind the action needs.
    case wrongKind(NodeID)
    /// The identifier names several views of the kind.
    case ambiguous([NodeID])
    case found(NodeID)
}

extension ViewNode {
    /// The identifier set on this node with `accessibilityIdentifier(_:)`.
    /// ``accessibilityEntries()`` has the one that lookups use, which an
    /// ancestor can replace.
    public var accessibilityIdentifier: String? {
        attributes[AccessibilityKey.identifier]
    }

    /// The label set on this node with `accessibilityLabel(_:)`. ``label``
    /// has the one that lookups use.
    public var accessibilityLabel: String? {
        attributes[AccessibilityKey.label]
    }

    /// What `accessibilityElement(children:)` set on this node, if it was
    /// called.
    public var accessibilityChildBehavior: AccessibilityChildBehavior? {
        attributes[AccessibilityKey.element].map(AccessibilityChildBehavior.init(name:))
    }

    /// Every node in this subtree that a lookup by identifier can reach,
    /// depth first, with the identifier it has there.
    ///
    /// The identifier follows SwiftUI's rules:
    /// - An identifier on a view that is not an element passes down to the
    ///   views inside it, and replaces theirs.
    /// - `accessibilityElement(children: .contain)` stops that: its children
    ///   keep their own identifiers.
    /// - The children of an `.ignore` or `.combine` element, and of a control
    ///   such as a button, are part of that element and are not listed.
    ///   Assumed: a control with no identifier of its own takes the first one
    ///   set on a view in its label, which is what a test finds on a device
    ///   for an icon button.
    public func accessibilityEntries() -> [AccessibilityEntry] {
        var entries: [AccessibilityEntry] = []
        collectAccessibilityEntries(inherited: nil, into: &entries)
        return entries
    }

    /// The nodes in this subtree whose identifier, as ``accessibilityEntries()``
    /// resolves it, is `identifier`.
    public func nodes(withAccessibilityIdentifier identifier: String) -> [ViewNode] {
        accessibilityEntries().filter { $0.identifier == identifier }.map(\.node)
    }

    private func collectAccessibilityEntries(
        inherited: String?, into entries: inout [AccessibilityEntry]
    ) {
        var identifier = inherited ?? accessibilityIdentifier
        let behavior = accessibilityChildBehavior
        let swallowsChildren = behavior == .ignore || behavior == .combine || isControl
        if identifier == nil, swallowsChildren {
            identifier =
                children.lazy.flatMap(\.allNodes).compactMap(\.accessibilityIdentifier)
                .first
        }
        entries.append(AccessibilityEntry(node: self, identifier: identifier))
        if swallowsChildren { return }
        // A container element's children are elements of their own.
        let passed = behavior == .contain ? nil : identifier
        for child in children {
            child.collectAccessibilityEntries(inherited: passed, into: &entries)
        }
    }

    /// Finds the one node in this subtree that `identifier` names and that
    /// `isTarget` accepts.
    ///
    /// A node that is not a target, such as a toggle whose switch is inside
    /// it, stands for the targets inside it.
    func resolveAccessibilityIdentifier(
        _ identifier: String, isTarget: (ViewNode) -> Bool
    ) -> AccessibilityResolution {
        let matches = nodes(withAccessibilityIdentifier: identifier)
        guard !matches.isEmpty else { return .none }
        var targets = matches.filter(isTarget)
        if targets.isEmpty {
            var seen: Set<NodeID> = []
            targets = matches.flatMap { $0.allNodes.dropFirst() }
                .filter { isTarget($0) && seen.insert($0.id).inserted }
        }
        switch targets.count {
        case 0: return .wrongKind(matches[0].id)
        case 1: return .found(targets[0].id)
        default: return .ambiguous(targets.map(\.id))
        }
    }

    /// Whether the node is a control that merges its label into itself.
    private var isControl: Bool {
        switch kind {
        case "Button", "NavigationLink", "Toggle", "Stepper", "Slider", "TextField":
            return true
        default: return false
        }
    }

    /// Appends what a screen reader reads for this node's subtree to
    /// `parts`. See ``label``.
    func collectAccessibilityText(into parts: inout [String]) {
        if let label = accessibilityLabel {
            parts.append(label)
            return
        }
        switch accessibilityChildBehavior {
        case .ignore?:
            return
        case .combine?:
            // Assumed: SwiftUI joins the labels of the children with a pause,
            // which this writes as a comma. Apple does not document it.
            var childLabels: [String] = []
            for child in children where child.kind != "Overlay" {
                let childLabel = child.label
                if !childLabel.isEmpty { childLabels.append(childLabel) }
            }
            if !childLabels.isEmpty { parts.append(childLabels.joined(separator: ", ")) }
            return
        default:
            break
        }
        if let text { parts.append(text) }
        // An overlay's views are not part of the label of the view they
        // cover.
        for child in children where child.kind != "Overlay" {
            child.collectAccessibilityText(into: &parts)
        }
    }
}

/// A node, and the identifier a lookup finds it by.
public struct AccessibilityEntry: Equatable, Sendable {
    public var node: ViewNode
    /// The identifier after an ancestor's identifier replaced the node's own.
    public var identifier: String?
}
