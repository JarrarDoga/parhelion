import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 300),
    safeAreaInsets: EdgeInsets()
)

@MainActor
@Suite("Fonts")
struct FontTests {
    @Test("Text styles resolve to the iOS sizes, line heights, and weights")
    func textStyles() {
        let expected: [(Font, CGFloat, CGFloat, Font.Weight)] = [
            (.largeTitle, 34, 41, .regular), (.title, 28, 34, .regular),
            (.title2, 22, 28, .regular), (.title3, 20, 25, .regular),
            (.headline, 17, 22, .semibold), (.body, 17, 22, .regular),
            (.callout, 16, 21, .regular), (.subheadline, 15, 20, .regular),
            (.footnote, 13, 18, .regular), (.caption, 12, 16, .regular),
            (.caption2, 11, 13, .regular),
        ]
        for (font, size, lineHeight, weight) in expected {
            let resolved = font.resolved()
            #expect(resolved.size == size)
            #expect(resolved.lineHeight == lineHeight)
            #expect(resolved.weight == weight)
        }
    }

    @Test("The system font at a size has a line height of about 1.2 times the size")
    func systemFont() {
        let footer = Font.system(size: 13).resolved()
        #expect(footer.size == 13 && footer.lineHeight == 16 && footer.weight == .regular)
        let large = Font.system(size: 30, weight: .heavy).resolved()
        #expect(large.lineHeight == 36 && large.weight == .heavy)
        #expect(Font.system(.headline, weight: .bold).resolved().weight == .bold)
    }

    @Test("Weights map to the nearest bundled Inter weight")
    func typefaces() {
        // Each Inter weight has its own advance widths.
        func typeface(_ weight: Font.Weight) -> Double {
            Font.body.weight(weight).resolved().typeface.width(of: "Tasks", size: 17)
        }
        #expect(typeface(.ultraLight) == typeface(.regular))
        #expect(typeface(.medium) != typeface(.regular))
        #expect(typeface(.semibold) != typeface(.medium))
        #expect(typeface(.heavy) == typeface(.bold))
        #expect(typeface(.black) == typeface(.bold))
    }

    @Test("A font attribute names the style and any weight that differs from it")
    func attributeRoundTrip() {
        let fonts: [Font] = [
            .largeTitle.bold(), .headline, .body.weight(.medium), .system(size: 13),
            .system(size: 20.5, weight: .semibold), .caption2,
        ]
        let attributes = fonts.map { $0.resolved().attribute }
        #expect(
            attributes == [
                "largeTitle.bold", "headline", "body.medium", "system(13)",
                "system(20.5).semibold", "caption2",
            ])
        for (font, attribute) in zip(fonts, attributes) {
            #expect(ResolvedFont(attribute: attribute) == font.resolved())
        }
        #expect(ResolvedFont(attribute: nil) == .body)
        #expect(ResolvedFont(attribute: "nonsense") == .body)
    }

    @Test("font(_:) sets the font of the text in its content")
    func fontModifier() {
        let host = ViewHost(
            VStack {
                Text("Title")
                HStack { Text("Detail") }
            }
            .font(.headline),
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Title" font=headline
                   └─ HStack
                      └─ Text "Detail" font=headline
                """
        )
    }

    @Test("Text in the body font records no font")
    func bodyRecordsNothing() {
        let host = ViewHost(
            VStack {
                Text("Plain")
                Text("Body").font(.body)
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Plain"
                   └─ Text "Body"
                """
        )
    }

    @Test("An inner font(_:) overrides an outer one, and Text.font overrides both")
    func innerFontWins() {
        let host = ViewHost(
            VStack {
                Text("Outer")
                Text("Inner").font(.caption)
                VStack { Text("Nested") }.font(.title)
            }
            .font(.footnote),
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Outer" font=footnote
                   ├─ Text "Inner" font=caption
                   └─ VStack
                      └─ Text "Nested" font=title
                """
        )
    }

    @Test("fontWeight(_:) and bold() change the weight of the content's fonts")
    func weightModifiers() {
        let host = ViewHost(
            VStack {
                Text("Weighted").fontWeight(.medium)
                Text("Bold").bold()
                Text("Not bold").bold(false)
                HStack {
                    Text("Group")
                    Text("Headline").font(.headline)
                }
                .fontWeight(.semibold)
                Text("Title").font(.title3).bold()
                VStack { Text("Inherited") }.bold()
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Weighted" font=body.medium
                   ├─ Text "Bold" font=body.bold
                   ├─ Text "Not bold"
                   ├─ HStack
                   │  ├─ Text "Group" font=body.semibold
                   │  └─ Text "Headline" font=headline
                   ├─ Text "Title" font=title3.bold
                   └─ VStack
                      └─ Text "Inherited" font=body.bold
                """
        )
    }

    @Test("A Text's own weight overrides the environment's")
    func textWeightWins() {
        let host = ViewHost(VStack { Text("Light").fontWeight(.light) }.bold(), device: square)
        let text = host.root.allNodes.first { $0.kind == "Text" }
        #expect(text?.attributes["font"] == "body.light")
    }

    @Test("Views read the font from the environment")
    func environmentFont() {
        struct Reader: View {
            @Environment(\.font) private var font

            var body: some View {
                Text(font == .largeTitle ? "large" : "other")
            }
        }
        let host = ViewHost(Reader().font(.largeTitle), device: square)
        #expect(host.root.label == "large")
        #expect(ViewHost(Reader(), device: square).root.label == "other")
    }

    @Test("Layout measures text in its font")
    func layoutUsesFont() throws {
        let host = ViewHost(
            VStack(spacing: 0) {
                Text("Tasks")
                Text("Tasks").font(.largeTitle).bold()
                Text("Tasks").font(.system(size: 13))
            },
            device: square
        )
        let texts = host.root.allNodes.filter { $0.kind == "Text" }.compactMap(\.frame)
        #expect(texts.map(\.height) == [22, 41, 16])
        // Twice the size and bold: more than twice as wide.
        #expect(texts[1].width > texts[0].width * 2)
        #expect(texts[2].width < texts[0].width)
    }

    @Test("The renderer draws text in its font's weight")
    func renderingUsesWeight() {
        func inkCount(_ text: Text) -> Int {
            let frame = ViewHost(text, device: square).render(scale: 2)
            var count = 0
            for y in stride(from: 0, to: frame.pixelHeight, by: 1) {
                for x in stride(from: 0, to: frame.pixelWidth, by: 1) {
                    let pixel = frame.color(at: CGPoint(x: Double(x) / 2, y: Double(y) / 2))
                    if pixel.red < 128 { count += 1 }
                }
            }
            return count
        }
        let regular = inkCount(Text("Tasks"))
        let bold = inkCount(Text("Tasks").bold())
        let large = inkCount(Text("Tasks").font(.largeTitle))
        #expect(bold > regular)
        #expect(large > regular * 3)
    }
}
