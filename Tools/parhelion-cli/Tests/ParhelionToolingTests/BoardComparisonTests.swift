import Foundation
import ParhelionRender
import Testing

@testable import ParhelionTooling

/// A directory for one test's files.
private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("parhelion-board-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A screen of 44 × 96 points at `scale`, white with a black bar.
private func screen(scale: Double, barHeight: Double = 10) -> Canvas {
    var canvas = Canvas(width: 44, height: 96, scale: scale, background: .white)
    canvas.fill(
        CGRect(x: 0, y: 0, width: 44, height: barHeight),
        color: RGBA(red: 0, green: 0, blue: 0))
    return canvas
}

struct BoardComparisonTests {
    @Test func comparesAtTheBoardsScaleAndWritesTheDiff() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A board at 3×, and a screen whose bar is 2 points taller.
        let board = directory.appendingPathComponent("board-07.png")
        try Data(screen(scale: 3).pngData()).write(to: board)
        let diffPath = directory.appendingPathComponent("out/diff.png").path
        var requested: [Double] = []

        let outcome = try BoardComparison.compare(
            boardPath: board.path, screenWidth: 44, screenHeight: 96, diffPath: diffPath
        ) { scale in
            requested.append(scale)
            return screen(scale: scale, barHeight: 12).pngData()
        }

        #expect(requested == [3])
        // 2 points × 44 points at 3×, of 132 × 288 pixels.
        #expect(outcome.differingPixels == 6 * 132)
        #expect(outcome.share == Double(6 * 132) / Double(132 * 288))
        #expect(outcome.summary.contains("2.08% of pixels differ"))
        #expect(outcome.summary.contains("board-07.png at 3×"))
        #expect(outcome.summary.contains("[0, 10, 44 × 2] points"))
        #expect(outcome.diffPath == diffPath)
        let written = try Bitmap(
            pngData: [UInt8](try Data(contentsOf: URL(fileURLWithPath: diffPath))))
        #expect(written.pixel(x: 5, y: 31) == ImageDiff.highlight)
        #expect(written.pixel(x: 5, y: 100) != ImageDiff.highlight)
    }

    @Test func matchingScreenReportsZero() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = directory.appendingPathComponent("board.png")
        try Data(screen(scale: 2).pngData()).write(to: board)
        let outcome = try BoardComparison.compare(
            boardPath: board.path, screenWidth: 44, screenHeight: 96,
            diffPath: directory.appendingPathComponent("diff.png").path
        ) { screen(scale: $0).pngData() }
        #expect(outcome.share == 0)
        #expect(outcome.summary.contains("0.00% of pixels differ"))
        #expect(!outcome.summary.contains("differences lie within"))
    }

    @Test func defaultDiffPathIsNamedAfterTheBoard() {
        let path = BoardComparison.defaultDiffPath(for: "/some/dir/Board 03.png")
        #expect(path.hasSuffix("/parhelion-compare/Board 03-diff.png"))
    }

    @Test func aBoardOfAnotherShapeIsRefusedWithTheSizesThatFit() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = directory.appendingPathComponent("wrong.png")
        try Data(Canvas(width: 100, height: 100, scale: 1).pngData()).write(to: board)
        do {
            _ = try BoardComparison.compare(
                boardPath: board.path, screenWidth: 44, screenHeight: 96
            ) { _ in
                Issue.record("It must not take a screenshot."); return []
            }
            Issue.record("Expected a failure.")
        } catch let failure as BoardComparison.Failure {
            #expect(failure.description.contains("100 × 100 pixels"))
            #expect(failure.description.contains("132 × 288 at 3×"))
        }
    }

    @Test func missingAndNonPNGBoardsFail() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: BoardComparison.Failure.self) {
            try BoardComparison.compare(
                boardPath: directory.appendingPathComponent("none.png").path,
                screenWidth: 44, screenHeight: 96
            ) { _ in [] }
        }
        let text = directory.appendingPathComponent("text.png")
        try Data("hello".utf8).write(to: text)
        do {
            _ = try BoardComparison.compare(
                boardPath: text.path, screenWidth: 44, screenHeight: 96
            ) { _ in [] }
            Issue.record("Expected a failure.")
        } catch let failure as BoardComparison.Failure {
            #expect(failure.description.contains("is not a PNG image"))
        }
    }

    @Test func scaleComesFromTheBoardsWidth() throws {
        let board = Bitmap(
            width: 1320, height: 2868, pixels: [UInt8](repeating: 0, count: 1320 * 2868 * 4))
        #expect(try BoardComparison.scale(for: board, screenWidth: 440, screenHeight: 956) == 3)
        #expect(throws: BoardComparison.Failure.self) {
            try BoardComparison.scale(for: board, screenWidth: 393, screenHeight: 852)
        }
    }

    @Test func warnsWhenAnOverlayWouldBeStretched() {
        #expect(
            BoardComparison.stretchWarning(
                boardWidth: 1320, boardHeight: 2868, screenWidth: 440, screenHeight: 956) == nil)
        let warning = BoardComparison.stretchWarning(
            boardWidth: 1000, boardHeight: 1000, screenWidth: 393, screenHeight: 852)
        #expect(warning?.contains("393 × 852 point screen") == true)
    }
}
