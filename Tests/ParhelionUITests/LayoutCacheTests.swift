import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

@MainActor
@Suite("Layout and glyph caches")
struct LayoutCacheTests {
    @Test("The Collection fixture is a lazy column of rows with art and two lines of text")
    func collectionOutline() throws {
        let host = ViewHost(CollectionFixture(), device: .iPhone18ProMax)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        #expect(stack.attributes["lazyCount"] == "5000")
        let row = try #require(stack.children.first)
        #expect(row.outline().contains("RoundedRectangle"))
        #expect(row.outline().contains(#"Text "Song number 0""#))
        #expect(row.outline().contains(#"Text "Artist 0 · Album 0""#))
    }

    @Test("The Now Playing fixture has art, two lines, a scrubber, and three buttons")
    func nowPlayingOutline() throws {
        let host = ViewHost(NowPlayingFixture(), device: .iPhone18ProMax)
        let outline = host.root.outline()
        #expect(outline.contains("RoundedRectangle"))
        #expect(outline.contains(#"Text "Blinding Lights""#))
        #expect(outline.contains("Slider"))
        #expect(outline.contains("accessibilityLabel=Play"))
        #expect(host.root.allNodes.filter { $0.kind == "Button" }.count == 3)
    }

    @Test("Laying out an unchanged tree again finds every size in the cache")
    func sizesAreFound() throws {
        let host = ViewHost(NowPlayingFixture(), device: .iPhone18ProMax)
        let engine = LayoutEngine(device: .iPhone18ProMax)
        let tree = Self.unplaced(host.root)
        _ = engine.layout(tree)
        let misses = engine.sizes.misses
        #expect(misses > 0)
        let first = engine.layout(tree)
        #expect(engine.sizes.misses == misses)
        #expect(engine.sizes.hits > 0)
        #expect(first == engine.layout(tree))
    }

    /// The tree as evaluation makes it, before layout gives it frames.
    private static func unplaced(_ node: ViewNode) -> ViewNode {
        var node = node
        node.frame = nil
        node.modifierFrames = []
        node.children = node.children.map(unplaced)
        return node
    }

    @Test("A node that changed is measured again")
    func changedNodeIsMeasured() throws {
        struct Label: View {
            var title: String
            var body: some View { Text(title).padding(8) }
        }
        let engine = LayoutEngine(device: .iPhone18ProMax)
        let short = ViewHost(Label(title: "Hi"), device: .iPhone18ProMax).root
        let long = ViewHost(Label(title: "A much longer title"), device: .iPhone18ProMax).root
        let a = try #require(engine.layout(short).allNodes.first { $0.kind == "Text" }?.frame)
        let b = try #require(engine.layout(long).allNodes.first { $0.kind == "Text" }?.frame)
        #expect(a.width < b.width)
        #expect(engine.layout(short).allNodes.first { $0.kind == "Text" }?.frame == a)
    }

    @Test("A scrolled list lays out as it does with an empty cache")
    func scrollingMatchesFreshLayout() throws {
        let scrolled = ViewHost(CollectionFixture(count: 500), device: .iPhone18ProMax)
        let list = try #require(scrolled.root.allNodes.first { $0.kind == "ScrollView" })
        for step in 1...30 {
            scrolled.scroll(by: CGSize(width: 0, height: 37.5), at: CGPoint(x: 200, y: 400))
            scrolled.advanceTime(by: 1.0 / 120)
            _ = step
        }
        let offset = try #require(scrolled.scrollOffset(of: list.id))
        let fresh = ViewHost(CollectionFixture(count: 500), device: .iPhone18ProMax)
        try fresh.scroll(list.id, to: offset)
        #expect(scrolled.root == fresh.root)
    }

    @Test("Wrapped lines come from the cache the second time and are the same")
    func linesAreCached() {
        let measurer = FontTextMeasurer()
        let font = Font.body.resolved()
        let text = "A line of text long enough to wrap onto more than one line in a narrow column"
        let first = measurer.lines(of: text, font: font, width: 120)
        let hits = TextLineCache.shared.hits
        let second = measurer.lines(of: text, font: font, width: 120)
        #expect(TextLineCache.shared.hits == hits + 1)
        #expect(first == second)
        #expect(first.count > 1)
        // Another width is another entry.
        #expect(measurer.lines(of: text, font: font, width: 300) != first)
    }

    @Test("A font parses a glyph's outline once and returns it again")
    func outlinesAreCached() {
        let font = TrueTypeFont.interRegular
        let glyph = font.glyph(for: "g")
        let first = font.outline(ofGlyph: glyph)
        let second = font.outline(ofGlyph: glyph)
        #expect(!first.isEmpty)
        func drawn(_ path: Path) -> [UInt8] {
            var canvas = Canvas(width: 40, height: 40, scale: 1, background: .white)
            canvas.fill(
                path.applying(scaleX: 0.02, scaleY: -0.02, translateX: 5, translateY: 30),
                color: .black)
            return canvas.pixels
        }
        #expect(drawn(first) == drawn(second))
        #expect(drawn(first).contains { $0 < 255 })
    }

    @Test("Letter spacing follows Inter's dynamic metrics and is part of every width")
    func trackingSpacing() {
        let font = TrueTypeFont.interRegular
        // None to speak of at 12 points, tighter at body size, and a
        // constant fraction of an em for large text.
        #expect(abs(font.tracking(size: 12)) < 0.01)
        #expect(font.tracking(size: 17) < -0.1)
        #expect(font.tracking(size: 17) > -0.4)
        let large = font.tracking(size: 40) / 40
        let larger = font.tracking(size: 80) / 80
        #expect(abs(large - -0.0223) < 0.001)
        #expect(abs(larger - -0.0223) < 0.0001)

        let units = "Hello".unicodeScalars.reduce(0) {
            $0 + font.advance(ofGlyph: font.glyph(for: $1))
        }
        let plain = Double(units) * 17 / Double(font.unitsPerEm)
        #expect(
            abs(font.width(of: "Hello", size: 17) - (plain + 5 * font.tracking(size: 17))) < 1e-9)
        #expect(font.width(of: "Hello", size: 17) < plain)
    }

    @Test("Text is drawn where layout measured it, tracking included")
    func drawingAgreesWithMeasuring() {
        let font = TrueTypeFont.interRegular
        var canvas = Canvas(width: 200, height: 40, scale: 1, background: .white)
        canvas.drawText(
            "Hello world", font: font, size: 17, origin: CGPoint(x: 4, y: 28), color: .black)
        let width = font.width(of: "Hello world", size: 17)
        // Ink ends no further right than the measured width, and not far
        // inside it.
        var rightmost = 0
        for y in 0..<40 {
            for x in 0..<200 where canvas.pixel(x: x, y: y).red < 128 {
                rightmost = max(rightmost, x)
            }
        }
        #expect(Double(rightmost) <= 4 + width + 1)
        #expect(Double(rightmost) >= 4 + width - 4)
    }

    @Test("Text moved by whole pixels draws the same pixels, and a clip crops it")
    func glyphCoverageIsShiftedAndCropped() {
        let font = TrueTypeFont.interMedium
        func line(at x: Double, clip: CGRect? = nil) -> Canvas {
            var canvas = Canvas(width: 160, height: 40, scale: 2, background: .white)
            canvas.clipRect = clip
            canvas.drawText(
                "Glyphs", font: font, size: 15, origin: CGPoint(x: x, y: 24), color: .black)
            return canvas
        }
        // A point is two pixels, so half a point is one.
        let a = line(at: 10)
        let b = line(at: 10.5)
        for y in 0..<80 {
            for x in 0..<150 { #expect(a.pixel(x: x, y: y) == b.pixel(x: x + 1, y: y)) }
        }
        let clip = CGRect(x: 14, y: 0, width: 20, height: 40)
        let cropped = line(at: 10, clip: clip)
        var inked = false
        for y in 0..<80 {
            for x in 0..<160 {
                let inside = x >= 28 && x < 68
                let expected = inside ? a.pixel(x: x, y: y) : RGBA(red: 255, green: 255, blue: 255)
                #expect(cropped.pixel(x: x, y: y) == expected)
                if inside, expected.red < 255 { inked = true }
            }
        }
        #expect(inked)
    }
}
