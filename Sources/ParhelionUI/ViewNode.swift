/// A stable identifier for a node in the resolved view tree.
///
/// Identifiers are structural: they are built from the position of a view in
/// its parent and the view's type, the same notion of identity SwiftUI uses.
/// A node keeps its identifier across updates as long as its position and type
/// do not change.
public struct NodeID: Hashable, Sendable, Codable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// One element of the resolved view tree.
///
/// The tree is plain data: it is `Codable` and `Sendable`, so tools and agents
/// can inspect, diff, and serialize it without touching the live views.
public struct ViewNode: Hashable, Sendable, Codable {
    /// The structural identifier of this node.
    public var id: NodeID

    /// The primitive kind, such as `"Text"`, `"VStack"`, or `"Button"`.
    public var kind: String

    /// Properties of the node, including those applied by modifiers.
    public var attributes: [String: String]

    public var children: [ViewNode]

    public init(
        id: NodeID,
        kind: String,
        attributes: [String: String] = [:],
        children: [ViewNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.attributes = attributes
        self.children = children
    }

    /// The string a `Text` node displays, or `nil` for other kinds.
    public var text: String? {
        kind == "Text" ? attributes["text"] : nil
    }

    /// The text of this node and its descendants, in reading order.
    public var label: String {
        var parts: [String] = []
        collectText(into: &parts)
        return parts.joined(separator: " ")
    }

    /// This node and all of its descendants, depth first.
    public var allNodes: [ViewNode] {
        [self] + children.flatMap(\.allNodes)
    }

    /// The first node in this subtree with the given identifier.
    public func node(withID id: NodeID) -> ViewNode? {
        if self.id == id { return self }
        for child in children {
            if let match = child.node(withID: id) { return match }
        }
        return nil
    }

    private func collectText(into parts: inout [String]) {
        if let text { parts.append(text) }
        for child in children {
            child.collectText(into: &parts)
        }
    }
}

extension ViewNode {
    /// A human-readable outline of this subtree.
    ///
    /// ```
    /// Root
    /// └─ VStack padding=all
    ///    ├─ Image imageScale=large systemName=globe
    ///    └─ Text "Hello, world!"
    /// ```
    public func outline(includeIDs: Bool = false) -> String {
        var lines: [String] = []
        appendOutline(to: &lines, prefix: "", childPrefix: "", includeIDs: includeIDs)
        return lines.joined(separator: "\n")
    }

    private func appendOutline(
        to lines: inout [String],
        prefix: String,
        childPrefix: String,
        includeIDs: Bool
    ) {
        var line = prefix + kind
        if let text { line += " \"\(text)\"" }
        for key in attributes.keys.sorted() where key != "text" || kind != "Text" {
            line += " \(key)=\(attributes[key]!)"
        }
        if includeIDs, !id.rawValue.isEmpty { line += "  #\(id)" }
        lines.append(line)

        for (index, child) in children.enumerated() {
            let isLast = index == children.count - 1
            child.appendOutline(
                to: &lines,
                prefix: childPrefix + (isLast ? "└─ " : "├─ "),
                childPrefix: childPrefix + (isLast ? "   " : "│  "),
                includeIDs: includeIDs
            )
        }
    }
}
