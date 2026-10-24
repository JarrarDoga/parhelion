#if canImport(Foundation)
import Foundation
#endif

/// A description of a row or a column in a lazy grid, mirroring SwiftUI's
/// `GridItem`.
public struct GridItem: Sendable, Hashable {
    /// The size of a grid item.
    public enum Size: Sendable, Hashable {
        /// One item of a fixed size.
        case fixed(CGFloat)
        /// One item that shares the space left after fixed items and
        /// spacing equally with other flexible items, within its bounds.
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        /// As many items of at least `minimum` as fit in the space of one
        /// flexible item, each at most `maximum`.
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: Size
    /// The spacing to the next item, or `nil` for the default.
    public var spacing: CGFloat?
    /// How to align views in this item's cells, or `nil` for the center.
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }

    /// The item as a grid's node records it, such as `flexible`,
    /// `fixed(100)`, or `adaptive(80...120) spacing 4 alignment leading`.
    var outlineDescription: String {
        func range(_ minimum: CGFloat, _ maximum: CGFloat) -> String {
            "\(formatPoints(minimum))...\(formatPoints(maximum))"
        }
        var parts: [String]
        switch size {
        case .fixed(let length):
            parts = ["fixed(\(formatPoints(length)))"]
        case .flexible(let minimum, let maximum):
            parts = [
                minimum == 10 && maximum == .infinity
                    ? "flexible" : "flexible(\(range(minimum, maximum)))"
            ]
        case .adaptive(let minimum, let maximum):
            parts = [
                maximum == .infinity
                    ? "adaptive(\(formatPoints(minimum)))" : "adaptive(\(range(minimum, maximum)))"
            ]
        }
        if let spacing { parts.append("spacing \(formatPoints(spacing))") }
        if let alignment { parts.append("alignment \(alignment.name)") }
        return parts.joined(separator: " ")
    }

    /// The items a grid's node records, read back.
    static func items(from description: String?) -> [GridItem] {
        guard let description, !description.isEmpty else { return [] }
        return description.components(separatedBy: ", ").map { item in
            let words = item.split(separator: " ")
            var result = GridItem()
            func bounds(_ text: Substring) -> (CGFloat, CGFloat) {
                let parts = text.components(separatedBy: "...")
                let low = parts.first.flatMap(Double.init).map { CGFloat($0) } ?? 10
                let high =
                    parts.count > 1
                    ? (Double(parts[1]).map { CGFloat($0) } ?? .infinity) : .infinity
                return (low, high)
            }
            if let size = words.first {
                let inner = size.drop { $0 != "(" }.dropFirst().dropLast()
                if size.hasPrefix("fixed") {
                    result.size = .fixed(CGFloat(Double(inner) ?? 0))
                } else if size.hasPrefix("adaptive") {
                    let (low, high) = bounds(inner)
                    result.size = .adaptive(minimum: low, maximum: high)
                } else if size.hasPrefix("flexible(") {
                    let (low, high) = bounds(inner)
                    result.size = .flexible(minimum: low, maximum: high)
                }
            }
            var index = 1
            while index + 1 < words.count {
                switch words[index] {
                case "spacing": result.spacing = Double(words[index + 1]).map { CGFloat($0) }
                case "alignment": result.alignment = Alignment(name: String(words[index + 1]))
                default: break
                }
                index += 2
            }
            return result
        }
    }
}

/// The kinds of views a lazy stack or grid pins to the bounds of a scroll
/// view, mirroring SwiftUI's `PinnedScrollableViews`. Parhelion accepts
/// them and pins nothing yet.
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

/// A grid that fills each row with its views, leading to trailing, then
/// the next row, mirroring SwiftUI's `LazyVGrid`.
///
/// Parhelion evaluates every cell, not only those on screen, so the tree
/// lists all of them.
public struct LazyVGrid<Content: View>: View {
    public typealias Body = Never

    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVGrid is a primitive view and has no body.")
    }
}

/// A grid that fills each column with its views, top to bottom, then the
/// next column, mirroring SwiftUI's `LazyHGrid`.
///
/// Parhelion evaluates every cell, not only those on screen, so the tree
/// lists all of them.
public struct LazyHGrid<Content: View>: View {
    public typealias Body = Never

    let rows: [GridItem]
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHGrid is a primitive view and has no body.")
    }
}

extension LazyVGrid: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes = ["columns": columns.map(\.outlineDescription).joined(separator: ", ")]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        let ownPath = path.appending("LazyVGrid")
        return [
            ViewNode(
                id: ownPath.id, kind: "LazyVGrid", attributes: attributes,
                children: evaluator.evaluate(content, at: ownPath))
        ]
    }
}

extension LazyHGrid: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes = ["rows": rows.map(\.outlineDescription).joined(separator: ", ")]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        let ownPath = path.appending("LazyHGrid")
        return [
            ViewNode(
                id: ownPath.id, kind: "LazyHGrid", attributes: attributes,
                children: evaluator.evaluate(content, at: ownPath))
        ]
    }
}
