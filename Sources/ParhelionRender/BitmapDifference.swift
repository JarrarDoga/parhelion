/// How two images differ, pixel by pixel.
///
/// A pixel differs when any of its red, green, blue, or alpha bytes differs
/// from the reference's by more than a tolerance. The check is integer
/// arithmetic, so it gives the same answer on every platform. Perceptual
/// metrics would need color conversion through the math library, which is
/// the part of a render that can differ between machines.
public struct BitmapDifference: Sendable, Equatable {
    /// A rectangle of pixels.
    public struct Bounds: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }

    /// Whether both images have the same width and height.
    public var sizesMatch: Bool
    /// The pixels compared: those of the larger of the two images in each
    /// direction, so a pixel that exists in only one image counts as differing.
    public var totalPixels: Int
    /// The number of pixels that differ by more than the tolerance.
    public var differingPixels: Int
    /// The largest difference in any channel of any pixel, 0 to 255. Pixels
    /// that exist in only one image count as 255.
    public var maxChannelDifference: Int
    /// The smallest rectangle that holds every differing pixel, or `nil`
    /// when none differ.
    public var bounds: Bounds?

    /// The share of compared pixels that differ, 0 to 1.
    public var fraction: Double {
        totalPixels == 0 ? 0 : Double(differingPixels) / Double(totalPixels)
    }

    /// A one-line description for a failure message.
    public var summary: String {
        var text = ""
        if !sizesMatch { text += "The sizes differ. " }
        text += "\(differingPixels) of \(totalPixels) pixels differ"
        text +=
            " (\((fraction * 100000).rounded() / 1000)%), by up to \(maxChannelDifference) in a channel"
        if let bounds {
            text +=
                ", inside x \(bounds.x)..<\(bounds.x + bounds.width)"
                + " and y \(bounds.y)..<\(bounds.y + bounds.height)"
        }
        return text + "."
    }
}

extension Bitmap {
    /// Compares this image with a reference.
    ///
    /// - Parameter channelTolerance: How far a channel may differ, 0 to 255,
    ///   before its pixel counts as differing.
    public func difference(
        from reference: Bitmap, channelTolerance: Int = 0
    )
        -> BitmapDifference
    {
        let width = max(self.width, reference.width)
        let height = max(self.height, reference.height)
        let sizesMatch = self.width == reference.width && self.height == reference.height
        var differing = 0
        var largest = 0
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let delta = Self.delta(self, reference, x: x, y: y)
                largest = max(largest, delta)
                guard delta > channelTolerance else { continue }
                differing += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return BitmapDifference(
            sizesMatch: sizesMatch,
            totalPixels: width * height,
            differingPixels: differing,
            maxChannelDifference: largest,
            bounds: differing == 0
                ? nil
                : .init(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// An image that shows where this one differs from a reference: the
    /// differing pixels in red, over this image faded to light gray. It is
    /// as large as the larger of the two images in each direction.
    public func differenceImage(from reference: Bitmap, channelTolerance: Int = 0) -> Bitmap {
        let width = max(self.width, reference.width)
        let height = max(self.height, reference.height)
        var output = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if Self.delta(self, reference, x: x, y: y) > channelTolerance {
                    output[offset] = 255
                    output[offset + 1] = 0
                    output[offset + 2] = 0
                } else {
                    // Mix the pixel with white, three parts white to one part pixel.
                    let source = self.pixel(x: x, y: y)
                    output[offset] = UInt8((Int(source.red) + 3 * 255) / 4)
                    output[offset + 1] = UInt8((Int(source.green) + 3 * 255) / 4)
                    output[offset + 2] = UInt8((Int(source.blue) + 3 * 255) / 4)
                }
            }
        }
        return Bitmap(width: width, height: height, pixels: output)
    }

    /// The largest channel difference at a position, or 255 when only one
    /// image has a pixel there.
    private static func delta(_ a: Bitmap, _ b: Bitmap, x: Int, y: Int) -> Int {
        guard x < a.width, y < a.height, x < b.width, y < b.height else { return 255 }
        let first = (y * a.width + x) * 4
        let second = (y * b.width + x) * 4
        var largest = 0
        for channel in 0..<4 {
            let difference = abs(Int(a.pixels[first + channel]) - Int(b.pixels[second + channel]))
            largest = max(largest, difference)
        }
        return largest
    }
}
