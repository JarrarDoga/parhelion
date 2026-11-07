import Foundation
import ParhelionRender
import Testing

@testable import ParhelionTooling

private func solid(_ width: Int, _ height: Int, _ color: RGBA) -> Bitmap {
    Bitmap(
        width: width, height: height,
        pixels: (0..<width * height).flatMap { _ in
            [color.red, color.green, color.blue, color.alpha]
        })
}

/// `bitmap` with the pixel at (x, y) replaced.
private func setting(_ bitmap: Bitmap, x: Int, y: Int, to color: RGBA) -> Bitmap {
    var pixels = bitmap.pixels
    let index = (y * bitmap.width + x) * 4
    pixels.replaceSubrange(
        index..<index + 4, with: [color.red, color.green, color.blue, color.alpha])
    return Bitmap(width: bitmap.width, height: bitmap.height, pixels: pixels)
}

struct ImageDiffTests {
    @Test func identicalImagesMatch() throws {
        let image = solid(4, 3, RGBA(red: 10, green: 20, blue: 30))
        let result = try ImageDiff.compare(image, with: image)
        #expect(result.differingPixels == 0)
        #expect(result.share == 0)
        #expect(result.bounds == nil)
        #expect(result.largestDifference == 0)
    }

    @Test func countsDifferingPixelsAndBounds() throws {
        let board = solid(10, 8, .white)
        var actual = board
        for (x, y) in [(2, 1), (5, 4), (3, 6)] {
            actual = setting(actual, x: x, y: y, to: RGBA(red: 0, green: 0, blue: 0))
        }
        let result = try ImageDiff.compare(actual, with: board)
        #expect(result.differingPixels == 3)
        #expect(result.share == 3.0 / 80.0)
        #expect(result.bounds == ImageDiff.Region(x: 2, y: 1, width: 4, height: 6))
        #expect(result.largestDifference == 255)
    }

    @Test func toleranceAbsorbsSmallDifferences() throws {
        let board = solid(2, 2, RGBA(red: 100, green: 100, blue: 100))
        let actual = setting(board, x: 1, y: 0, to: RGBA(red: 108, green: 95, blue: 100))
        #expect(try ImageDiff.compare(actual, with: board, tolerance: 8).differingPixels == 0)
        #expect(try ImageDiff.compare(actual, with: board, tolerance: 7).differingPixels == 1)
        let strict = try ImageDiff.compare(actual, with: board, tolerance: 0)
        #expect(strict.differingPixels == 1)
        #expect(strict.largestDifference == 8)
    }

    @Test func alphaCounts() throws {
        let board = solid(1, 1, RGBA(red: 5, green: 5, blue: 5, alpha: 255))
        let actual = solid(1, 1, RGBA(red: 5, green: 5, blue: 5, alpha: 100))
        #expect(try ImageDiff.compare(actual, with: board).differingPixels == 1)
    }

    @Test func diffHighlightsDifferencesAndFadesTheRest() throws {
        let board = solid(3, 1, RGBA(red: 0, green: 0, blue: 0))
        let actual = setting(board, x: 1, y: 0, to: .white)
        let diff = try ImageDiff.compare(actual, with: board).diff
        #expect(diff.pixel(x: 1, y: 0) == ImageDiff.highlight)
        // Black, a third as strong over white.
        #expect(diff.pixel(x: 0, y: 0) == RGBA(red: 170, green: 170, blue: 170))
        #expect(diff.pixel(x: 2, y: 0) == RGBA(red: 170, green: 170, blue: 170))
    }

    @Test func differentSizesFail() {
        let wide = solid(4, 2, .white)
        let tall = solid(2, 4, .white)
        #expect(
            throws: ImageDiff.Failure.sizeMismatch(
                actual: .init(width: 4, height: 2), expected: .init(width: 2, height: 4))
        ) { try ImageDiff.compare(wide, with: tall) }
    }

    @Test func comparesPNGData() throws {
        var canvas = Canvas(width: 6, height: 6, scale: 1, background: .white)
        let board = canvas.pngData()
        canvas.fill(CGRect(x: 0, y: 0, width: 3, height: 6), color: RGBA(red: 0, green: 0, blue: 0))
        let result = try ImageDiff.compare(pngData: canvas.pngData(), with: board)
        #expect(result.share == 0.5)
        #expect(throws: Bitmap.PNGError.notPNG) {
            try ImageDiff.compare(pngData: [1, 2, 3], with: board)
        }
    }

    @Test func diffPNGRoundTrips() throws {
        let board = solid(5, 4, .white)
        let result = try ImageDiff.compare(
            setting(board, x: 4, y: 3, to: RGBA(red: 0, green: 0, blue: 0)), with: board)
        #expect(try Bitmap(pngData: result.diffPNG()) == result.diff)
    }
}
