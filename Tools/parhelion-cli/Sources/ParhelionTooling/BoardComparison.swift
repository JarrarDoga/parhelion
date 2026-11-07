import Foundation
import ParhelionRender

/// Compares the screen with a design board: a PNG of the screen at some
/// whole scale, such as 1320 × 2868 pixels for an iPhone 18 Pro Max's
/// 440 × 956 points at 3×.
public enum BoardComparison {
    /// What a comparison found, for a tool result.
    public struct Outcome: Sendable {
        public var summary: String
        /// The highlighted comparison, as a PNG image.
        public var diffPNG: [UInt8]
        public var diffPath: String
        public var share: Double
        public var differingPixels: Int
    }

    /// Why a board could not be compared.
    public struct Failure: Error, CustomStringConvertible {
        public var description: String

        public init(description: String) {
            self.description = description
        }
    }

    /// The scale at which the screen is the board's size, or a failure that
    /// says what size a board for this screen has.
    public static func scale(
        for board: Bitmap, screenWidth: Double, screenHeight: Double
    ) throws -> Double {
        guard screenWidth > 0, screenHeight > 0 else {
            throw Failure(description: "The screen has no size.")
        }
        let scale = Double(board.width) / screenWidth
        let wide = Self.points(screenWidth)
        let tall = Self.points(screenHeight)
        guard scale > 0, scale <= 4, (screenHeight * scale).rounded() == Double(board.height) else {
            throw Failure(
                description:
                    "The board is \(board.width) × \(board.height) pixels, which is not the "
                    + "screen's \(wide) × \(tall) points at a scale up to 4. A board for this "
                    + "screen is \(wide) × \(tall) pixels at 1×, \(Self.pixels(screenWidth, 2)) × "
                    + "\(Self.pixels(screenHeight, 2)) at 2×, or \(Self.pixels(screenWidth, 3)) × "
                    + "\(Self.pixels(screenHeight, 3)) at 3×.")
        }
        return scale
    }

    /// Renders the screen at the board's scale with `screenshot`, compares
    /// it with the board, and writes the diff PNG.
    ///
    /// - Parameters:
    ///   - screenshot: A PNG of the screen at the given scale, or `nil` if
    ///     the app did not answer.
    ///   - diffPath: Where to write the diff, or `nil` for a file in the
    ///     temporary directory named after the board.
    public static func compare(
        boardPath: String,
        screenWidth: Double,
        screenHeight: Double,
        tolerance: Int = ImageDiff.defaultTolerance,
        diffPath: String? = nil,
        screenshot: (_ scale: Double) throws -> [UInt8]
    ) throws -> Outcome {
        guard let boardData = FileManager.default.contents(atPath: boardPath) else {
            throw Failure(description: "Cannot read \(boardPath).")
        }
        let board: Bitmap
        do {
            board = try Bitmap(pngData: [UInt8](boardData))
        } catch {
            throw Failure(description: "\(boardPath) is not a PNG image: \(error).")
        }
        let scale = try scale(for: board, screenWidth: screenWidth, screenHeight: screenHeight)
        let actual = try Bitmap(pngData: screenshot(scale))
        let result: ImageDiff
        do {
            result = try ImageDiff.compare(actual, with: board, tolerance: tolerance)
        } catch {
            throw Failure(description: "\(error)")
        }

        let path = diffPath ?? defaultDiffPath(for: boardPath)
        let png = result.diffPNG()
        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try Data(png).write(to: URL(fileURLWithPath: path))
        } catch {
            throw Failure(
                description: "Cannot write the diff to \(path): \(error.localizedDescription)")
        }

        var summary = String(
            format: "%.2f%% of pixels differ (%d of %d) between the screen and %@ at %@× "
                + "(%d × %d pixels), with a tolerance of %d of 255; the largest difference is %d.",
            result.share * 100, result.differingPixels, result.pixelCount,
            (boardPath as NSString).lastPathComponent, points(scale), result.width,
            result.height, result.tolerance, result.largestDifference)
        if let bounds = result.bounds {
            summary +=
                " The differences lie within [\(points(Double(bounds.x) / scale)), "
                + "\(points(Double(bounds.y) / scale)), \(points(Double(bounds.width) / scale)) × "
                + "\(points(Double(bounds.height) / scale))] points."
        }
        summary += " The diff, with differing pixels in red, is at \(path)."
        return Outcome(
            summary: summary, diffPNG: png, diffPath: path, share: result.share,
            differingPixels: result.differingPixels)
    }

    /// A warning when stretching a board to the screen would distort it, or
    /// `nil`.
    public static func stretchWarning(
        boardWidth: Int, boardHeight: Int, screenWidth: Double, screenHeight: Double
    ) -> String? {
        guard screenWidth > 0, screenHeight > 0, boardWidth > 0, boardHeight > 0 else { return nil }
        let boardRatio = Double(boardWidth) / Double(boardHeight)
        guard abs(boardRatio / (screenWidth / screenHeight) - 1) > 0.01 else { return nil }
        return """
            Warning: the overlay is \(boardWidth) × \(boardHeight) pixels, which is not the shape \
            of the \(points(screenWidth)) × \(points(screenHeight)) point screen; it is stretched \
            to fit. Use --device to simulate the board's device.
            """
    }

    /// `parhelion-compare/<board name>-diff.png` in the temporary directory.
    static func defaultDiffPath(for boardPath: String) -> String {
        let name = ((boardPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-compare")
            .appendingPathComponent("\(name)-diff.png").path
    }

    /// A number of points without a trailing ".0", to two decimals.
    static func points(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private static func pixels(_ points: Double, _ scale: Double) -> String {
        Self.points(points * scale)
    }
}
