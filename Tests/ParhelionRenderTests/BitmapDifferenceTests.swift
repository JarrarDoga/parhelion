import Testing

@testable import ParhelionRender

private func bitmap(_ width: Int, _ height: Int, _ color: RGBA) -> Bitmap {
    Bitmap(
        width: width, height: height,
        pixels: (0..<(width * height)).flatMap { _ in
            [color.red, color.green, color.blue, color.alpha]
        })
}

private func setting(_ bitmap: Bitmap, x: Int, y: Int, to color: RGBA) -> Bitmap {
    var pixels = bitmap.pixels
    let index = (y * bitmap.width + x) * 4
    pixels[index] = color.red
    pixels[index + 1] = color.green
    pixels[index + 2] = color.blue
    pixels[index + 3] = color.alpha
    return Bitmap(width: bitmap.width, height: bitmap.height, pixels: pixels)
}

@Suite("Bitmap difference")
struct BitmapDifferenceTests {
    @Test("Equal images do not differ")
    func equal() {
        let image = bitmap(4, 3, .white)
        let difference = image.difference(from: image)
        #expect(difference.differingPixels == 0)
        #expect(difference.fraction == 0)
        #expect(difference.bounds == nil)
        #expect(difference.maxChannelDifference == 0)
        #expect(difference.sizesMatch)
    }

    @Test("It counts differing pixels, their largest difference, and their bounds")
    func counts() {
        let reference = bitmap(5, 4, .white)
        var image = setting(reference, x: 1, y: 1, to: RGBA(red: 250, green: 255, blue: 255))
        image = setting(image, x: 3, y: 2, to: RGBA(red: 255, green: 255, blue: 155))
        let difference = image.difference(from: reference)
        #expect(difference.totalPixels == 20)
        #expect(difference.differingPixels == 2)
        #expect(difference.fraction == 0.1)
        #expect(difference.maxChannelDifference == 100)
        #expect(difference.bounds == .init(x: 1, y: 1, width: 3, height: 2))
    }

    @Test("A channel tolerance skips small differences but still reports the largest")
    func channelTolerance() {
        let reference = bitmap(2, 2, .white)
        let image = setting(reference, x: 0, y: 0, to: RGBA(red: 252, green: 255, blue: 255))
        #expect(image.difference(from: reference, channelTolerance: 2).differingPixels == 1)
        let tolerated = image.difference(from: reference, channelTolerance: 3)
        #expect(tolerated.differingPixels == 0)
        #expect(tolerated.maxChannelDifference == 3)
    }

    @Test("Alpha counts as a channel")
    func alpha() {
        let reference = bitmap(1, 1, RGBA(red: 10, green: 10, blue: 10, alpha: 255))
        let image = bitmap(1, 1, RGBA(red: 10, green: 10, blue: 10, alpha: 0))
        #expect(image.difference(from: reference).differingPixels == 1)
    }

    @Test("Images of different sizes differ where only one has a pixel")
    func sizes() {
        let difference = bitmap(2, 2, .white).difference(from: bitmap(3, 2, .white))
        #expect(!difference.sizesMatch)
        #expect(difference.totalPixels == 6)
        #expect(difference.differingPixels == 2)
        #expect(difference.bounds == .init(x: 2, y: 0, width: 1, height: 2))
    }

    @Test("The difference image marks differing pixels red over a faded copy")
    func differenceImage() throws {
        let reference = bitmap(3, 1, .black)
        let image = setting(reference, x: 1, y: 0, to: RGBA(red: 0, green: 0, blue: 40))
        let diff = image.differenceImage(from: reference)
        #expect(diff.pixel(x: 1, y: 0) == RGBA(red: 255, green: 0, blue: 0))
        #expect(diff.pixel(x: 0, y: 0) == RGBA(red: 191, green: 191, blue: 191))
        let decoded = try Bitmap(pngData: diff.pngData())
        #expect(decoded == diff)
    }
}
