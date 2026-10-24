#if canImport(Foundation)
import Foundation
#endif

// Layout for `LazyVGrid`, `LazyHGrid`, and `Grid`, which the layout engine
// calls for the kinds it does not handle itself.
//
// Assumed: the default spacing, with `nil`, is 8 points between columns
// and between rows, Parhelion's stack spacing, because Apple's
// documentation says only "a default distance".

extension LayoutEngine {
    /// The size of a grid for a proposal, or `nil` for other nodes.
    func gridSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize? {
        switch node.kind {
        case "LazyVGrid": lazyGridLayout(node, proposal, axis: .vertical).size
        case "LazyHGrid": lazyGridLayout(node, proposal, axis: .horizontal).size
        case "Grid": gridLayout(node, proposal).size
        default: nil
        }
    }

    /// Places a grid's cells, or returns `nil` for other nodes.
    func placeGrid(_ node: ViewNode, in rect: CGRect) -> [ViewNode]? {
        switch node.kind {
        case "LazyVGrid": placeLazyGrid(node, in: rect, axis: .vertical)
        case "LazyHGrid": placeLazyGrid(node, in: rect, axis: .horizontal)
        case "Grid": placeGrid(gridLayout(node, ProposedSize(rect.size)), node, in: rect)
        default: nil
        }
    }

    // MARK: - Lazy grids

    /// A column of a lazy vertical grid, or a row of a horizontal one.
    struct GridTrack {
        /// The distance from the grid's first track.
        var offset: CGFloat
        var length: CGFloat
        var alignment: Alignment?
    }

    /// The tracks that grid items make in a length, or at their smallest
    /// sizes when the length is `nil`.
    ///
    /// Assumed, from Apple's description of `GridItem.Size`: fixed items
    /// and the spacing come first; flexible and adaptive items share the
    /// rest equally, each clamped to its bounds, and the space a clamped
    /// item does not use goes to the others. An adaptive item's share holds
    /// as many columns of its minimum, with its spacing between them, as
    /// fit, and they grow to fill it up to its maximum.
    func lazyGridTracks(_ items: [GridItem], length: CGFloat?) -> [GridTrack] {
        func spacing(_ index: Int) -> CGFloat {
            items[index].spacing ?? LayoutDefaults.stackSpacing
        }
        var shares: [Int: CGFloat] = [:]
        let flexible = items.indices.filter {
            if case .fixed = items[$0].size { return false }
            return true
        }
        func bounds(_ index: Int) -> (CGFloat, CGFloat) {
            switch items[index].size {
            case .fixed(let length): (length, length)
            case .flexible(let minimum, let maximum), .adaptive(let minimum, let maximum):
                (minimum, max(maximum, minimum))
            }
        }
        if let length, length.isFinite {
            var free = length - items.indices.dropLast().reduce(0) { $0 + spacing($1) }
            for index in items.indices {
                if case .fixed(let size) = items[index].size { free -= size }
            }
            var unresolved = flexible
            while !unresolved.isEmpty {
                let share = max(free, 0) / CGFloat(unresolved.count)
                let clamped = unresolved.filter {
                    let (low, high) = bounds($0)
                    return share < low || share > high
                }
                guard !clamped.isEmpty else {
                    for index in unresolved { shares[index] = share }
                    break
                }
                for index in clamped {
                    let (low, high) = bounds(index)
                    shares[index] = min(max(share, low), high)
                    free -= shares[index]!
                }
                unresolved.removeAll { clamped.contains($0) }
            }
        } else {
            for index in flexible { shares[index] = bounds(index).0 }
        }

        var tracks: [GridTrack] = []
        var cursor: CGFloat = 0
        for (index, item) in items.enumerated() {
            let gap = spacing(index)
            switch item.size {
            case .fixed(let size):
                tracks.append(GridTrack(offset: cursor, length: size, alignment: item.alignment))
                cursor += size + gap
            case .flexible:
                let size = shares[index] ?? 0
                tracks.append(GridTrack(offset: cursor, length: size, alignment: item.alignment))
                cursor += size + gap
            case .adaptive(let minimum, let maximum):
                let share = shares[index] ?? minimum
                let count = max(1, Int(((share + gap) / max(minimum + gap, 1)).rounded(.down)))
                let size = min(
                    (share - CGFloat(count - 1) * gap) / CGFloat(count), max(maximum, minimum))
                for _ in 0..<count {
                    tracks.append(
                        GridTrack(offset: cursor, length: size, alignment: item.alignment))
                    cursor += size + gap
                }
            }
        }
        return tracks
    }

    private struct LazyGridLayout {
        var size: CGSize
        var tracks: [GridTrack]
        /// The size of each cell, in the order of the grid's children.
        var cellSizes: [CGSize]
        /// The thickness of each row of a vertical grid, or column of a
        /// horizontal one, across the tracks.
        var lines: [CGFloat]
        var spacing: CGFloat
        /// The length of the tracks together.
        var tracksLength: CGFloat
    }

    /// Sizes a lazy grid: its tracks across the grid, and the lines of
    /// cells along it, each as thick as its thickest cell.
    private func lazyGridLayout(
        _ node: ViewNode, _ proposal: ProposedSize, axis: LayoutAxis
    ) -> LazyGridLayout {
        let vertical = axis == .vertical
        let items = GridItem.items(from: node.attributes[vertical ? "columns" : "rows"])
        let across = vertical ? proposal.width : proposal.height
        let tracks = lazyGridTracks(items, length: across)
        let spacing =
            node.attributes["spacing"].flatMap(Double.init).map { CGFloat($0) }
            ?? LayoutDefaults.stackSpacing
        let tracksLength = tracks.last.map { $0.offset + $0.length } ?? 0
        var cellSizes: [CGSize] = []
        var lines: [CGFloat] = []
        for (index, cell) in node.children.enumerated() {
            guard !tracks.isEmpty else { break }
            let track = tracks[index % tracks.count]
            let size = sizeThatFits(
                cell,
                vertical
                    ? ProposedSize(width: track.length, height: nil)
                    : ProposedSize(width: nil, height: track.length),
                parentAxis: nil)
            cellSizes.append(size)
            let thickness = vertical ? size.height : size.width
            if index % tracks.count == 0 {
                lines.append(thickness)
            } else {
                lines[lines.count - 1] = max(lines[lines.count - 1], thickness)
            }
        }
        let along = lines.reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        // The grid takes the length it is offered across its tracks and
        // aligns them in it, which places them in its parent by its
        // alignment, as Apple's documentation describes.
        let width: CGFloat
        if let across, across.isInfinite {
            width = .infinity
        } else {
            width = across.map { max($0, tracksLength) } ?? tracksLength
        }
        return LazyGridLayout(
            size: vertical
                ? CGSize(width: width, height: along) : CGSize(width: along, height: width),
            tracks: tracks, cellSizes: cellSizes, lines: lines, spacing: spacing,
            tracksLength: tracksLength)
    }

    private func placeLazyGrid(_ node: ViewNode, in rect: CGRect, axis: LayoutAxis) -> [ViewNode] {
        let vertical = axis == .vertical
        let layout = lazyGridLayout(node, ProposedSize(rect.size), axis: axis)
        guard !layout.tracks.isEmpty else { return node.children }
        let room = (vertical ? rect.width : rect.height) - layout.tracksLength
        let start: CGFloat
        switch node.attributes["alignment"] {
        case "leading", "top": start = 0
        case "trailing", "bottom": start = room
        default: start = room / 2
        }
        var line: CGFloat = 0
        var placed = node.children
        for (index, cell) in node.children.enumerated() where index < layout.cellSizes.count {
            let row = index / layout.tracks.count
            if index % layout.tracks.count == 0, row > 0 {
                line += layout.lines[row - 1] + layout.spacing
            }
            let track = layout.tracks[index % layout.tracks.count]
            let slot =
                vertical
                ? CGRect(
                    x: rect.minX + start + track.offset, y: rect.minY + line, width: track.length,
                    height: layout.lines[row])
                : CGRect(
                    x: rect.minX + line, y: rect.minY + start + track.offset,
                    width: layout.lines[row], height: track.length)
            placed[index] = place(
                cell, in: align(layout.cellSizes[index], in: slot, track.alignment ?? .center),
                parentAxis: nil)
        }
        return placed
    }

    // MARK: - Grid

    private struct GridCell {
        var index: (row: Int, cell: Int?)
        var column: Int
        var span: Int
        var unsized: (horizontal: Bool, vertical: Bool)
    }

    private struct GridLayout {
        var size: CGSize
        var columns: [CGFloat]
        var rows: [CGFloat]
        var horizontalSpacing: CGFloat
        var verticalSpacing: CGFloat
        var cells: [GridCell]
    }

    /// The cells of a grid: each `GridRow`'s views, one column after
    /// another as their spans take them, and each other view across all
    /// the columns.
    private func gridCells(_ node: ViewNode) -> (cells: [GridCell], columns: Int) {
        var cells: [GridCell] = []
        var columnCount = 0
        for (rowIndex, row) in node.children.enumerated() where row.kind == "GridRow" {
            var column = 0
            for (cellIndex, cell) in row.children.enumerated() {
                let span = cell.attributes["gridCellColumns"].flatMap(Int.init) ?? 1
                cells.append(
                    GridCell(
                        index: (rowIndex, cellIndex), column: column, span: span,
                        unsized: Self.unsizedAxes(cell)))
                column += span
            }
            columnCount = max(columnCount, column)
        }
        for (rowIndex, row) in node.children.enumerated() where row.kind != "GridRow" {
            cells.append(
                GridCell(
                    index: (rowIndex, nil), column: 0, span: max(columnCount, 1),
                    unsized: Self.unsizedAxes(row)))
        }
        return (cells, max(columnCount, node.children.isEmpty ? 0 : 1))
    }

    private static func unsizedAxes(_ cell: ViewNode) -> (horizontal: Bool, vertical: Bool) {
        let axes = cell.attributes["gridCellUnsizedAxes"]
        return (axes == "horizontal" || axes == "both", axes == "vertical" || axes == "both")
    }

    private func gridCellNode(_ node: ViewNode, _ cell: GridCell) -> ViewNode {
        let row = node.children[cell.index.row]
        return cell.index.cell.map { row.children[$0] } ?? row
    }

    /// Sizes a grid. A column is as wide as the widest of its cells that
    /// span only it, and a row as tall as its tallest cell. When the grid
    /// is offered more, columns with flexible cells share it, or, if only
    /// a cell across several columns is flexible, every column does, as
    /// Apple's documentation describes for a `Divider`. Assumed: the
    /// remaining height goes to rows with flexible cells the same way.
    private func gridLayout(_ node: ViewNode, _ proposal: ProposedSize) -> GridLayout {
        let horizontalSpacing =
            node.attributes["horizontalSpacing"].flatMap(Double.init).map { CGFloat($0) }
            ?? LayoutDefaults.stackSpacing
        let verticalSpacing =
            node.attributes["verticalSpacing"].flatMap(Double.init).map { CGFloat($0) }
            ?? LayoutDefaults.stackSpacing
        let (cells, columnCount) = gridCells(node)
        let rowCount = node.children.count

        // Columns.
        var columns = [CGFloat](repeating: 0, count: columnCount)
        var flexibleColumns = Set<Int>()
        var spansFlexibly = false
        for cell in cells where !cell.unsized.horizontal {
            let view = gridCellNode(node, cell)
            let ideal = sizeThatFits(view, .unspecified, parentAxis: nil).width
            let largest = sizeThatFits(
                view, ProposedSize(width: .infinity, height: nil), parentAxis: nil
            ).width
            let flexible = largest > ideal + 0.5
            if cell.span == 1 {
                columns[cell.column] = max(columns[cell.column], ideal)
                if flexible { flexibleColumns.insert(cell.column) }
            } else if flexible {
                spansFlexibly = true
            }
        }
        let horizontalGaps = horizontalSpacing * CGFloat(max(columnCount - 1, 0))
        if let width = proposal.width, width.isFinite {
            distribute(
                width - horizontalGaps, among: &columns,
                flexible: flexibleColumns.isEmpty && spansFlexibly
                    ? Set(columns.indices) : flexibleColumns)
        }

        // Rows.
        func cellWidth(_ cell: GridCell) -> CGFloat {
            let end = min(cell.column + cell.span, columnCount)
            guard cell.column < end else { return 0 }
            return columns[cell.column..<end].reduce(0, +)
                + horizontalSpacing * CGFloat(end - cell.column - 1)
        }
        var rows = [CGFloat](repeating: 0, count: rowCount)
        var flexibleRows = Set<Int>()
        for cell in cells where !cell.unsized.vertical {
            let view = gridCellNode(node, cell)
            let width = cellWidth(cell)
            let ideal = sizeThatFits(
                view, ProposedSize(width: width, height: nil), parentAxis: nil
            ).height
            let largest = sizeThatFits(
                view, ProposedSize(width: width, height: .infinity), parentAxis: nil
            ).height
            rows[cell.index.row] = max(rows[cell.index.row], ideal)
            if largest > ideal + 0.5 { flexibleRows.insert(cell.index.row) }
        }
        let verticalGaps = verticalSpacing * CGFloat(max(rowCount - 1, 0))
        if let height = proposal.height, height.isFinite {
            distribute(height - verticalGaps, among: &rows, flexible: flexibleRows)
        }

        let size = CGSize(
            width: proposal.width?.isInfinite == true
                && !(flexibleColumns.isEmpty && !spansFlexibly)
                ? .infinity : columns.reduce(0, +) + horizontalGaps,
            height: proposal.height?.isInfinite == true && !flexibleRows.isEmpty
                ? .infinity : rows.reduce(0, +) + verticalGaps)
        return GridLayout(
            size: size, columns: columns, rows: rows, horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing, cells: cells)
    }

    /// Shares the room beyond some lengths' total equally among the
    /// flexible ones, never shrinking one below its length.
    private func distribute(_ room: CGFloat, among lengths: inout [CGFloat], flexible: Set<Int>) {
        let fixed = lengths.indices.filter { !flexible.contains($0) }.reduce(0) { $0 + lengths[$1] }
        var free = room - fixed
        var unresolved = flexible.sorted()
        while !unresolved.isEmpty {
            let share = free / CGFloat(unresolved.count)
            let larger = unresolved.filter { lengths[$0] > share }
            guard !larger.isEmpty else {
                for index in unresolved { lengths[index] = share }
                return
            }
            for index in larger { free -= lengths[index] }
            unresolved.removeAll { larger.contains($0) }
        }
    }

    private func placeGrid(_ layout: GridLayout, _ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        let gridAlignment = Alignment(name: node.attributes["alignment"]) ?? .center
        var columnX: [CGFloat] = []
        var x = rect.minX
        for width in layout.columns {
            columnX.append(x)
            x += width + layout.horizontalSpacing
        }
        var rowY: [CGFloat] = []
        var y = rect.minY
        for height in layout.rows {
            rowY.append(y)
            y += height + layout.verticalSpacing
        }
        // A column takes the alignment that one of its cells sets.
        var columnAlignment: [Int: HorizontalAlignment] = [:]
        for cell in layout.cells where cell.span == 1 {
            if let name = gridCellNode(node, cell).attributes["gridColumnAlignment"],
                let alignment = HorizontalAlignment(rawValue: name)
            {
                columnAlignment[cell.column] = alignment
            }
        }

        var children = node.children
        for (rowIndex, row) in node.children.enumerated() where row.kind == "GridRow" {
            children[rowIndex].frame = CGRect(
                x: rect.minX, y: rowY[rowIndex], width: layout.size.width,
                height: layout.rows[rowIndex])
        }
        for cell in layout.cells {
            let view = gridCellNode(node, cell)
            let end = min(cell.column + cell.span, layout.columns.count)
            guard cell.column < end else { continue }
            let width =
                layout.columns[cell.column..<end].reduce(0, +)
                + layout.horizontalSpacing * CGFloat(end - cell.column - 1)
            let slot = CGRect(
                x: columnX[cell.column], y: rowY[cell.index.row], width: width,
                height: layout.rows[cell.index.row])
            let size = sizeThatFits(view, ProposedSize(slot.size), parentAxis: nil)
            let rowAlignment =
                cell.index.cell == nil
                ? nil
                : VerticalAlignment(
                    rawValue: node.children[cell.index.row].attributes["alignment"] ?? "")
            let frame: CGRect
            if let anchor = view.attributes["gridCellAnchor"].flatMap({ UnitPoint(name: $0) }) {
                frame = CGRect(
                    x: slot.minX + anchor.x * (slot.width - size.width),
                    y: slot.minY + anchor.y * (slot.height - size.height), width: size.width,
                    height: size.height)
            } else {
                // A cell across several columns aligns by the grid's own
                // alignment, as an anchor would.
                let horizontal =
                    cell.span == 1
                    ? columnAlignment[cell.column] ?? gridAlignment.horizontal
                    : gridAlignment.horizontal
                frame = align(
                    size, in: slot,
                    Alignment(
                        horizontal: horizontal, vertical: rowAlignment ?? gridAlignment.vertical))
            }
            let placed = place(view, in: frame, parentAxis: nil)
            if let cellIndex = cell.index.cell {
                children[cell.index.row].children[cellIndex] = placed
            } else {
                children[cell.index.row] = placed
            }
        }
        return children
    }
}
