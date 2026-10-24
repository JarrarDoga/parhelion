#if canImport(Foundation)
import Foundation
#endif

/// A container that arranges views in rows and columns, mirroring
/// SwiftUI's `Grid`.
///
/// Each `GridRow` in the content is a row, and every other view spans all
/// the columns in a row of its own. A column is as wide as its widest
/// cell, and a row as tall as its tallest; columns and rows with flexible
/// cells, such as a `Color`, share the space that is left.
public struct Grid<Content: View>: View {
    public typealias Body = Never

    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content

    public init(
        alignment: Alignment = .center,
        horizontalSpacing: CGFloat? = nil,
        verticalSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    public var body: Never {
        fatalError("Grid is a primitive view and has no body.")
    }
}

/// A row of a `Grid`, mirroring SwiftUI's `GridRow`. Each view in it is a
/// cell.
public struct GridRow<Content: View>: View {
    public typealias Body = Never

    let alignment: VerticalAlignment?
    let content: Content

    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("GridRow is a primitive view and has no body.")
    }
}

extension Grid: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.name }
        if let horizontalSpacing {
            attributes["horizontalSpacing"] = formatPoints(horizontalSpacing)
        }
        if let verticalSpacing { attributes["verticalSpacing"] = formatPoints(verticalSpacing) }
        let ownPath = path.appending("Grid")
        return [
            ViewNode(
                id: ownPath.id, kind: "Grid", attributes: attributes,
                children: evaluator.evaluate(content, at: ownPath))
        ]
    }
}

extension GridRow: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if let alignment { attributes["alignment"] = alignment.rawValue }
        let ownPath = path.appending("GridRow")
        return [
            ViewNode(
                id: ownPath.id, kind: "GridRow", attributes: attributes,
                children: evaluator.evaluate(content, at: ownPath))
        ]
    }
}

extension View {
    /// Makes this cell of a `Grid` span a number of columns.
    public func gridCellColumns(_ count: Int) -> some View {
        attributeModifier("gridCellColumns", String(max(count, 1)))
    }

    /// Aligns this cell, and every other cell in its column of a `Grid`,
    /// horizontally with a guide. Set it on one cell in a column.
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        attributeModifier("gridColumnAlignment", guide.rawValue)
    }

    /// Keeps a `Grid` from offering this cell more size than the other
    /// cells need along some axes, so a flexible view such as a `Divider`
    /// does not widen the grid.
    public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
        let name: String
        switch (axes.contains(.horizontal), axes.contains(.vertical)) {
        case (true, true): name = "both"
        case (true, false): name = "horizontal"
        case (false, true): name = "vertical"
        case (false, false): name = "none"
        }
        return attributeModifier("gridCellUnsizedAxes", name)
    }

    /// Aligns a point of this cell's view with the same point of its cell
    /// in a `Grid`, instead of the row's and column's guides.
    public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
        attributeModifier("gridCellAnchor", anchor.name)
    }
}
