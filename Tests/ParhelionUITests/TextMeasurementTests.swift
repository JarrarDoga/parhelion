import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

@Suite("Text measurement")
struct TextMeasurementTests {
    let measurer = FontTextMeasurer()
    let body = ResolvedFont.body

    @Test("Width grows with the text and the font size")
    func widthScales() {
        let narrow = measurer.size(of: "iiii", font: body, width: nil)
        let wide = measurer.size(of: "MMMM", font: body, width: nil)
        #expect(narrow.width < wide.width)

        let large = measurer.size(of: "MMMM", font: Font.system(size: 34).resolved(), width: nil)
        #expect(abs(large.width - wide.width * 2) < 0.001)
    }

    @Test("Text is measured with the Inter weight nearest to its font's weight")
    func weights() {
        func width(_ weight: Font.Weight) -> CGFloat {
            measurer.size(of: "Tasks", font: Font.body.weight(weight).resolved(), width: nil).width
        }
        let regular = TrueTypeFont.interRegular.width(of: "Tasks", size: 17)
        let bold = TrueTypeFont.interBold.width(of: "Tasks", size: 17)
        #expect(abs(width(.regular) - CGFloat(regular)) < 0.001)
        #expect(abs(width(.bold) - CGFloat(bold)) < 0.001)
        // Inter's weights are wider the heavier they are.
        #expect(width(.regular) < width(.medium))
        #expect(width(.medium) < width(.semibold))
        #expect(width(.semibold) < width(.bold))
        // Weights between the bundled ones use the nearest.
        #expect(width(.light) == width(.regular))
        #expect(width(.black) == width(.bold))
    }

    @Test("Each line is the font's line height tall")
    func lineHeights() {
        #expect(measurer.size(of: "Tasks", font: body, width: nil).height == 22)
        #expect(
            measurer.size(of: "Tasks", font: Font.largeTitle.resolved(), width: nil).height == 41)
        #expect(measurer.size(of: "Tasks", font: Font.caption2.resolved(), width: nil).height == 13)
        #expect(
            measurer.size(of: "A\nB", font: Font.system(size: 13).resolved(), width: nil).height
                == 32)
    }

    @Test("Text without a width proposal stays on one line")
    func singleLine() {
        let size = measurer.size(of: "The quick brown fox", font: body, width: nil)
        #expect(size.height == 22)
    }

    @Test("Text wraps at spaces to fit the proposed width")
    func wrapsAtSpaces() {
        let oneLine = measurer.size(of: "The quick brown fox", font: body, width: nil)
        let wrapped = measurer.size(of: "The quick brown fox", font: body, width: oneLine.width / 2)
        #expect(wrapped.width <= oneLine.width / 2)
        #expect(wrapped.height >= 22 * 2)
    }

    @Test("Bolder text wraps sooner")
    func boldWraps() {
        let text = "Open a task to mark it done or delete it."
        let regular = measurer.size(of: text, font: body, width: nil)
        let bold = Font.body.bold().resolved()
        #expect(measurer.size(of: text, font: body, width: regular.width).height == 22)
        #expect(measurer.size(of: text, font: bold, width: regular.width).height == 44)
    }

    @Test("A word wider than the line breaks between characters")
    func breaksLongWords() {
        let word = measurer.size(of: "Supercalifragilistic", font: body, width: nil)
        let broken = measurer.size(of: "Supercalifragilistic", font: body, width: word.width / 3)
        #expect(broken.width <= word.width / 3)
        #expect(broken.height >= 22 * 3)
    }

    @Test("Newlines start new lines")
    func newlines() {
        let size = measurer.size(of: "One\nTwo\nThree", font: body, width: nil)
        #expect(size.height == 66)
    }

    @Test("Empty text has no size")
    func emptyText() {
        #expect(measurer.size(of: "", font: body, width: 100) == .zero)
    }
}
