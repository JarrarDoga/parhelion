#if canImport(Foundation)
import Foundation
#endif

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
public struct ViewNode: Hashable, Sendable {
    /// The structural identifier of this node.
    public var id: NodeID

    /// The primitive kind, such as `"Text"`, `"VStack"`, or `"Button"`.
    public var kind: String

    /// Properties of the node, including style values applied by modifiers.
    public var attributes: [String: String]

    /// Layout modifiers applied to this node, innermost first.
    public var modifiers: [LayoutModifier]

    /// The node's bounds in screen points, excluding its outer padding and
    /// frames. `nil` until layout has run.
    public var frame: CGRect?

    /// The bounds each layout modifier was placed in, in the same order as
    /// ``modifiers``. A `background` fills its entry. Empty until layout has
    /// run.
    public var modifierFrames: [CGRect] = []

    public var children: [ViewNode]

    public init(
        id: NodeID,
        kind: String,
        attributes: [String: String] = [:],
        modifiers: [LayoutModifier] = [],
        frame: CGRect? = nil,
        children: [ViewNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.attributes = attributes
        self.modifiers = modifiers
        self.frame = frame
        self.children = children
    }

    /// The string a `Text` node displays, or `nil` for other kinds.
    public var text: String? {
        kind == "Text" ? attributes["text"] : nil
    }

    /// The text of this node and its descendants, in reading order, or the
    /// node's `label` attribute when it has one. A back button, which shows
    /// only a chevron, records the title of the view it returns to there.
    public var label: String {
        if let label = attributes["label"] { return label }
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
        // An overlay's views are not part of the label of the view they
        // cover.
        for child in children where child.kind != "Overlay" {
            child.collectText(into: &parts)
        }
    }
}

extension ViewNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, attributes, modifiers, frame, modifierFrames, children
    }

    /// Frames are encoded as `{"x": 0, "y": 0, "width": 0, "height": 0}`,
    /// which is easier for tools to read than `CGRect`'s nested arrays.
    private struct EncodedRect: Codable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        init(_ rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NodeID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        attributes =
            try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        modifiers = try container.decodeIfPresent([LayoutModifier].self, forKey: .modifiers) ?? []
        frame = try container.decodeIfPresent(EncodedRect.self, forKey: .frame)?.rect
        modifierFrames =
            try container.decodeIfPresent([EncodedRect].self, forKey: .modifierFrames)?.map(\.rect)
            ?? []
        children = try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if !attributes.isEmpty { try container.encode(attributes, forKey: .attributes) }
        if !modifiers.isEmpty { try container.encode(modifiers, forKey: .modifiers) }
        if let frame { try container.encode(EncodedRect(frame), forKey: .frame) }
        if !modifierFrames.isEmpty {
            try container.encode(modifierFrames.map(EncodedRect.init), forKey: .modifierFrames)
        }
        if !children.isEmpty { try container.encode(children, forKey: .children) }
    }
}

extension ViewNode {
    /// A human-readable outline of this subtree.
    ///
    /// ```
    /// Root
    /// └─ VStack padding(16)
    ///    ├─ Image foregroundStyle=tint imageScale=large systemName=globe
    ///    └─ Text "Hello, world!"
    /// ```
    public func outline(includeIDs: Bool = false, includeFrames: Bool = false) -> String {
        var lines: [String] = []
        appendOutline(
            to: &lines,
            prefix: "",
            childPrefix: "",
            includeIDs: includeIDs,
            includeFrames: includeFrames
        )
        return lines.joined(separator: "\n")
    }

    private func appendOutline(
        to lines: inout [String],
        prefix: String,
        childPrefix: String,
        includeIDs: Bool,
        includeFrames: Bool
    ) {
        var line = prefix + kind
        if let text { line += " \"\(text)\"" }
        for modifier in modifiers {
            line += " \(modifier.outlineDescription)"
        }
        for key in attributes.keys.sorted() where !(kind == "Text" && key == "text") {
            line += " \(key)=\(attributes[key]!)"
        }
        if includeFrames, let frame {
            line += "  [\(formatPoints(frame.minX)), \(formatPoints(frame.minY)), "
            line += "\(formatPoints(frame.width)) × \(formatPoints(frame.height))]"
        }
        if includeIDs, !id.rawValue.isEmpty { line += "  #\(id)" }
        lines.append(line)

        for (index, child) in children.enumerated() {
            let isLast = index == children.count - 1
            child.appendOutline(
                to: &lines,
                prefix: childPrefix + (isLast ? "└─ " : "├─ "),
                childPrefix: childPrefix + (isLast ? "   " : "│  "),
                includeIDs: includeIDs,
                includeFrames: includeFrames
            )
        }
    }
}

/// Formats a point value with at most two decimal places: `16`, `20.5`,
/// `120.33`.
func formatPoints(_ value: CGFloat) -> String {
    if value.isInfinite { return value < 0 ? "-inf" : "inf" }
    let rounded = (Double(value) * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(format: "%.2f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    return text
}
