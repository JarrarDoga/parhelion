import ParhelionRender

/// A comparison of two images of the same size, such as a screenshot of the
/// preview and a design board.
///
/// A pixel differs when any of its red, green, blue, or alpha values is more
/// than `tolerance` away from the other image's, on the 0 to 255 scale of a
/// byte. A tolerance of 0 counts every change; the default absorbs the
/// rounding of anti-aliased edges.
public struct ImageDiff: Sendable {
    /// Why two images could not be compared.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case sizeMismatch(actual: ImageSize, expected: ImageSize)

        public var description: String {
            switch self {
            case .sizeMismatch(let actual, let expected):
                "The images differ in size: \(actual) against \(expected)."
            }
        }
    }

    /// A size in pixels.
    public struct ImageSize: Equatable, Sendable, CustomStringConvertible {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var description: String { "\(width) × \(height) pixels" }
    }

    /// A rectangle in pixels.
    public struct Region: Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }

    /// The tolerance `compare` uses when none is given.
    public static let defaultTolerance = 8

    public let width: Int
    public let height: Int
    public let tolerance: Int
    /// How many pixels differ.
    public let differingPixels: Int
    /// The smallest rectangle that holds every differing pixel, or `nil`
    /// when the images match.
    public let bounds: Region?
    /// The largest difference in any value of any pixel, from 0 to 255.
    public let largestDifference: Int
    /// The first image, faded, with the differing pixels in solid red, as a
    /// bitmap the size of the images.
    public let diff: Bitmap

    public var pixelCount: Int { width * height }

    /// The share of pixels that differ, from 0 to 1. It is 0 for images of
    /// no pixels.
    public var share: Double {
        pixelCount == 0 ? 0 : Double(differingPixels) / Double(pixelCount)
    }

    /// The color of a differing pixel in ``diff``.
    public static let highlight = RGBA(red: 255, green: 0, blue: 64)

    /// Compares `actual` with `expected`.
    ///
    /// - Parameter tolerance: The largest difference in a value, from 0 to
    ///   255, that still counts as the same.
    public static func compare(
        _ actual: Bitmap, with expected: Bitmap, tolerance: Int = defaultTolerance
    ) throws(Failure) -> ImageDiff {
        guard actual.width == expected.width, actual.height == expected.height else {
            throw .sizeMismatch(
                actual: ImageSize(width: actual.width, height: actual.height),
                expected: ImageSize(width: expected.width, height: expected.height))
        }
        let tolerance = min(max(tolerance, 0), 255)
        let width = actual.width
        let height = actual.height
        var diff = [UInt8](repeating: 0, count: actual.pixels.count)
        var count = 0
        var largest = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        let highlight = Self.highlight
        actual.pixels.withUnsafeBufferPointer { a in
            expected.pixels.withUnsafeBufferPointer { e in
                for y in 0..<height {
                    for x in 0..<width {
                        let index = (y * width + x) * 4
                        var difference = 0
                        for channel in 0..<4 {
                            difference = max(
                                difference, abs(Int(a[index + channel]) - Int(e[index + channel])))
                        }
                        largest = max(largest, difference)
                        if difference > tolerance {
                            count += 1
                            minX = min(minX, x)
                            maxX = max(maxX, x)
                            minY = min(minY, y)
                            maxY = max(maxY, y)
                            diff[index] = highlight.red
                            diff[index + 1] = highlight.green
                            diff[index + 2] = highlight.blue
                            diff[index + 3] = 255
                        } else {
                            // The same pixel, a third as strong over white, so
                            // the screen stays readable under the highlights.
                            for channel in 0..<3 {
                                diff[index + channel] = UInt8(
                                    (Int(a[index + channel]) + 2 * 255) / 3)
                            }
                            diff[index + 3] = 255
                        }
                    }
                }
            }
        }
        return ImageDiff(
            width: width, height: height, tolerance: tolerance, differingPixels: count,
            bounds: count == 0
                ? nil : Region(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
            largestDifference: largest,
            diff: Bitmap(width: width, height: height, pixels: diff))
    }

    /// Compares two PNG images.
    public static func compare(
        pngData actual: [UInt8], with expected: [UInt8], tolerance: Int = defaultTolerance
    ) throws -> ImageDiff {
        try compare(Bitmap(pngData: actual), with: Bitmap(pngData: expected), tolerance: tolerance)
    }

    /// The highlighted comparison as a PNG image.
    public func diffPNG() -> [UInt8] { diff.pngData() }
}
