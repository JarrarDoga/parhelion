import Foundation
import Testing

@testable import ParhelionUI

// Fixed-size views on a 400 × 400 screen without insets, so every frame
// can be computed by hand. The default spacing between columns and rows is
// 8 points.

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 400, height: 400),
    safeAreaInsets: EdgeInsets()
)

@MainActor
private func frames(_ host: ViewHost, kind: String = "Color") -> [CGRect] {
    host.root.allNodes.filter { $0.kind == kind }.compactMap(\.frame)
}

@MainActor
@Suite("Grids")
struct GridTests {
    @Test("A lazy vertical grid records its columns and spacing, and lists every cell")
    func lazyVGridNodes() {
        let host = ViewHost(
            LazyVGrid(
                columns: [
                    GridItem(.fixed(100)), GridItem(.flexible()),
                    GridItem(.adaptive(minimum: 50), spacing: 4, alignment: .leading),
                    GridItem(.flexible(minimum: 20, maximum: 60)),
                ],
                alignment: .leading, spacing: 12
            ) {
                ForEach(0..<2) { Text("\($0)") }
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ LazyVGrid alignment=leading columns=fixed(100), flexible, adaptive(50) spacing 4 alignment leading, flexible(20...60) spacing=12
                   ├─ Text "0"
                   └─ Text "1"
                """)
        let items = GridItem.items(from: host.root.children[0].attributes["columns"])
        #expect(items.count == 4)
        #expect(items[2] == GridItem(.adaptive(minimum: 50), spacing: 4, alignment: .leading))
        #expect(items[3] == GridItem(.flexible(minimum: 20, maximum: 60)))
    }

    @Test("Flexible columns share the width; rows are as tall as their tallest cell")
    func flexibleColumns() {
        let host = ViewHost(
            LazyVGrid(columns: [GridItem(), GridItem(), GridItem()]) {
                ForEach(0..<5) { index in
                    Color.red.frame(height: index == 1 ? 60 : 50)
                }
            },
            device: square
        )
        // (400 − 2 × 8) / 3 = 128 points per column, and the rows are 60
        // and 50 points tall with 8 between them: 118 points, centered.
        let cells = frames(host)
        #expect(host.root.children[0].frame == CGRect(x: 0, y: 141, width: 400, height: 118))
        #expect(cells[0] == CGRect(x: 0, y: 146, width: 128, height: 50))
        #expect(cells[1] == CGRect(x: 136, y: 141, width: 128, height: 60))
        #expect(cells[3] == CGRect(x: 0, y: 209, width: 128, height: 50))
        #expect(cells[4] == CGRect(x: 136, y: 209, width: 128, height: 50))
    }

    @Test("An adaptive item holds as many columns of its minimum as fit")
    func adaptiveColumns() {
        let host = ViewHost(
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                ForEach(0..<6) { _ in Color.red.frame(height: 30) }
            },
            device: square
        )
        // ⌊(400 + 8) / (80 + 8)⌋ = 4 columns, each (400 − 3 × 8) / 4 = 94.
        let cells = frames(host)
        #expect(cells[0].width == 94)
        #expect(cells[3].minX == 306)
        #expect(cells[5] == CGRect(x: 102, y: cells[0].minY + 38, width: 94, height: 30))
    }

    @Test("Fixed items come first, and a clamped flexible item leaves its space to the others")
    func clampedFlexibleColumns() {
        let tracks = LayoutEngine(device: square).lazyGridTracks(
            [
                GridItem(.fixed(100)), GridItem(.flexible(minimum: 50, maximum: 120)),
                GridItem(.flexible()),
            ],
            length: 400)
        #expect(tracks.map(\.offset) == [0, 108, 236])
        #expect(tracks.map(\.length) == [100, 120, 164])
    }

    @Test("A lazy horizontal grid fills each column top to bottom")
    func lazyHGrid() {
        let host = ViewHost(
            LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 10) {
                ForEach(0..<3) { _ in Color.blue.frame(width: 30) }
            },
            device: square
        )
        // The rows take 88 points of the 400 offered, centered from 156;
        // the columns are 30 points wide with 10 between them.
        let cells = frames(host)
        #expect(host.root.children[0].frame == CGRect(x: 165, y: 0, width: 70, height: 400))
        #expect(cells[0] == CGRect(x: 165, y: 156, width: 30, height: 40))
        #expect(cells[1] == CGRect(x: 165, y: 204, width: 30, height: 40))
        #expect(cells[2] == CGRect(x: 205, y: 156, width: 30, height: 40))
    }

    @Test(
        "A grid's columns are as wide as their widest cell, and its rows as tall as their tallest")
    func gridSizes() {
        let host = ViewHost(
            Grid {
                GridRow {
                    Color.red.frame(width: 50, height: 20)
                    Color.blue.frame(width: 30, height: 40)
                }
                GridRow {
                    Color.green.frame(width: 70, height: 10)
                }
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ Grid
                   ├─ GridRow
                   │  ├─ Color frame(width: 50, height: 20) color=red
                   │  └─ Color frame(width: 30, height: 40) color=blue
                   └─ GridRow
                      └─ Color frame(width: 70, height: 10) color=green
                """)
        let grid = host.root.children[0]
        #expect(grid.frame == CGRect(x: 146, y: 171, width: 108, height: 58))
        #expect(grid.children[0].frame == CGRect(x: 146, y: 171, width: 108, height: 40))
        #expect(
            frames(host) == [
                CGRect(x: 156, y: 181, width: 50, height: 20),
                CGRect(x: 224, y: 171, width: 30, height: 40),
                CGRect(x: 146, y: 219, width: 70, height: 10),
            ])
    }

    @Test("Cells span columns, align by column and row, and anchor themselves")
    func gridAlignment() {
        let host = ViewHost(
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Color.red.frame(width: 40, height: 40)
                    Color.blue.frame(width: 20, height: 20).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Color.green.frame(width: 60, height: 10).gridCellColumns(2)
                }
                Color.gray.frame(height: 2).gridCellUnsizedAxes(.horizontal)
                GridRow(alignment: .bottom) {
                    Color.orange.frame(width: 10, height: 10)
                    Color.purple.frame(width: 30, height: 30).gridCellAnchor(.center)
                }
            },
            device: square
        )
        let outline = host.root.outline()
        #expect(
            outline.contains("Grid alignment=topLeading horizontalSpacing=10 verticalSpacing=4"))
        #expect(outline.contains("color=blue gridColumnAlignment=trailing"))
        #expect(outline.contains("color=green gridCellColumns=2"))
        #expect(outline.contains("color=gray gridCellUnsizedAxes=horizontal"))
        #expect(outline.contains("GridRow alignment=bottom"))
        #expect(outline.contains("color=purple gridCellAnchor=center"))
        // Columns of 40 and 30 with 10 between; rows of 40, 10, 2, and 30
        // with 4 between: 80 × 94, centered at (160, 153).
        #expect(host.root.children[0].frame == CGRect(x: 160, y: 153, width: 80, height: 94))
        #expect(
            frames(host) == [
                CGRect(x: 160, y: 153, width: 40, height: 40),
                CGRect(x: 220, y: 153, width: 20, height: 20),
                CGRect(x: 160, y: 197, width: 60, height: 10),
                CGRect(x: 160, y: 211, width: 80, height: 2),
                CGRect(x: 160, y: 237, width: 10, height: 10),
                CGRect(x: 210, y: 217, width: 30, height: 30),
            ])
    }

    @Test("A flexible cell across all columns widens the grid unless its axis is unsized")
    func unsizedAxes() {
        func grid(unsized: Bool) -> some View {
            Grid {
                GridRow {
                    Color.red.frame(width: 20, height: 20)
                    Color.blue.frame(width: 20, height: 20)
                }
                if unsized {
                    Color.gray.frame(height: 1).gridCellUnsizedAxes(.horizontal)
                } else {
                    Color.gray.frame(height: 1)
                }
            }
        }
        let wide = ViewHost(grid(unsized: false), device: square)
        #expect(wide.root.children[0].frame?.width == 400)
        // Every column grows to (400 − 8) / 2 = 196, and the blue square
        // centers in the second: 204 + 88.
        #expect(frames(wide)[1].minX == 292)
        let narrow = ViewHost(grid(unsized: true), device: square)
        #expect(narrow.root.children[0].frame?.width == 48)
        #expect(frames(narrow)[2].width == 48)
    }

    @Test("Columns with flexible cells share the width that is left")
    func flexibleGridColumns() {
        let host = ViewHost(
            Grid(horizontalSpacing: 0) {
                GridRow {
                    Color.red.frame(width: 100, height: 20)
                    Color.blue.frame(height: 20)
                }
            },
            device: square
        )
        #expect(frames(host)[1] == CGRect(x: 100, y: 190, width: 300, height: 20))
    }
}
