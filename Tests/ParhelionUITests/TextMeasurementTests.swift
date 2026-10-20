import Foundation
import Testing

@testable import ParhelionUI

@Suite("Text measurement")
struct TextMeasurementTests {
    let measurer = FontTextMeasurer(metrics: .interRegular)

    @Test("The bundled font loads with plausible metrics")
    func fontLoads() {
        let metrics = FontMetrics.interRegular
        #expect(metrics.unitsPerEm > 0)
        #expect(metrics.ascender > 0)
        #expect(metrics.descender < 0)
        #expect(metrics.advance(of: "M") > metrics.advance(of: "i"))
    }

    @Test("Width grows with the text and the font size")
    func widthScales() {
        let narrow = measurer.size(of: "iiii", fontSize: 17, width: nil)
        let wide = measurer.size(of: "MMMM", fontSize: 17, width: nil)
        #expect(narrow.width < wide.width)

        let large = measurer.size(of: "MMMM", fontSize: 34, width: nil)
        #expect(abs(large.width - wide.width * 2) < 0.001)
    }

    @Test("Text without a width proposal stays on one line")
    func singleLine() {
        let size = measurer.size(of: "The quick brown fox", fontSize: 17, width: nil)
        #expect(size.height == FontMetrics.interRegular.lineHeight(size: 17))
    }

    @Test("Text wraps at spaces to fit the proposed width")
    func wrapsAtSpaces() {
        let oneLine = measurer.size(of: "The quick brown fox", fontSize: 17, width: nil)
        let wrapped = measurer.size(
            of: "The quick brown fox", fontSize: 17, width: oneLine.width / 2)
        let lineHeight = FontMetrics.interRegular.lineHeight(size: 17)
        #expect(wrapped.width <= oneLine.width / 2)
        #expect(wrapped.height >= lineHeight * 2)
    }

    @Test("A word wider than the line breaks between characters")
    func breaksLongWords() {
        let word = measurer.size(of: "Supercalifragilistic", fontSize: 17, width: nil)
        let broken = measurer.size(of: "Supercalifragilistic", fontSize: 17, width: word.width / 3)
        #expect(broken.width <= word.width / 3)
        #expect(broken.height >= FontMetrics.interRegular.lineHeight(size: 17) * 3)
    }

    @Test("Newlines start new lines")
    func newlines() {
        let size = measurer.size(of: "One\nTwo\nThree", fontSize: 17, width: nil)
        #expect(size.height == FontMetrics.interRegular.lineHeight(size: 17) * 3)
    }

    @Test("Empty text has no size")
    func emptyText() {
        #expect(measurer.size(of: "", fontSize: 17, width: 100) == .zero)
    }
}
