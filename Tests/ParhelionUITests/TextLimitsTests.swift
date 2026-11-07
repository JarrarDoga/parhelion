import Foundation
import Testing

@testable import ParhelionUI

private let phone = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 400),
    safeAreaInsets: EdgeInsets()
)

private let title = "Never Gonna Give You Up (Extended Remix 2026)"

@MainActor
private func lines(_ host: ViewHost, kind: String = "Text") throws -> [String] {
    let node = try #require(host.root.allNodes.first { $0.kind == kind })
    let frame = try #require(node.frame)
    return FontTextMeasurer().textLines(for: node, width: frame.width).map(\.text)
}

@MainActor
@Suite("Line limits and truncation")
struct TextLimitsTests {
    @Test("lineLimit and truncationMode appear in the outline, and flow to the text inside")
    func outline() {
        let host = ViewHost(
            VStack(alignment: .leading) {
                Text("Plain")
                Text("One").lineLimit(1)
                Text("Reserved").lineLimit(3, reservesSpace: true)
                Text("Range").lineLimit(2...5)
                Text("Open").lineLimit(2...)
                Text("Head").lineLimit(1).truncationMode(.head)
                // The writer nearest the text wins, as in SwiftUI.
                Text("Nearest").lineLimit(1).lineLimit(nil)
                VStack {
                    Text("Inner")
                }
                .lineLimit(2)
                .truncationMode(.middle)
            },
            device: phone)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack alignment=leading
                   ├─ Text "Plain"
                   ├─ Text "One" lineLimit=1
                   ├─ Text "Reserved" lineLimit=3 reservesSpace=true
                   ├─ Text "Range" lineLimit=5
                   ├─ Text "Open"
                   ├─ Text "Head" lineLimit=1 truncationMode=head
                   ├─ Text "Nearest" lineLimit=1
                   └─ VStack
                      └─ Text "Inner" lineLimit=2 truncationMode=middle
                """)
    }

    @Test("Without a limit, long text wraps onto as many lines as it needs")
    func unlimited() throws {
        let host = ViewHost(Text(title).frame(width: 100), device: phone)
        let text = try #require(host.root.allNodes.first { $0.kind == "Text" })
        #expect(try #require(text.frame).height > 22 * 2)
    }

    @Test("A one-line limit cuts the title off with an ellipsis at the tail")
    func tail() throws {
        let host = ViewHost(Text(title).lineLimit(1).frame(width: 100), device: phone)
        let text = try #require(host.root.allNodes.first { $0.kind == "Text" })
        #expect(try #require(text.frame).height == 22)
        let shown = try lines(host)
        #expect(shown.count == 1)
        let line = try #require(shown.first)
        #expect(line.hasSuffix("…") && title.hasPrefix(String(line.dropLast())))
        #expect(try #require(text.frame).width <= 100)
    }

    @Test("Head truncation keeps the end of the title")
    func head() throws {
        let host = ViewHost(
            Text(title).lineLimit(1).truncationMode(.head).frame(width: 100), device: phone)
        let line = try #require(try lines(host).first)
        #expect(line.hasPrefix("…") && title.hasSuffix(String(line.dropFirst())))
    }

    @Test("Middle truncation keeps the start and the end of the title")
    func middle() throws {
        let host = ViewHost(
            Text(title).lineLimit(1).truncationMode(.middle).frame(width: 100), device: phone)
        let line = try #require(try lines(host).first)
        let parts = line.components(separatedBy: "…")
        #expect(parts.count == 2)
        #expect(title.hasPrefix(parts[0]) && title.hasSuffix(parts[1]))
        #expect(parts[0].count > 0 && parts[1].count > 0)
    }

    @Test("A limit of two lines wraps, then truncates the last line")
    func twoLines() throws {
        let host = ViewHost(Text(title).lineLimit(2).frame(width: 100), device: phone)
        let text = try #require(host.root.allNodes.first { $0.kind == "Text" })
        #expect(try #require(text.frame).height == 44)
        let shown = try lines(host)
        #expect(shown.count == 2)
        #expect(shown[0].hasSuffix("…") == false)
        #expect(shown[1].hasSuffix("…"))
    }

    @Test("Head and middle truncation with two lines put the ellipsis where they say")
    func twoLinesOtherModes() throws {
        let head = ViewHost(
            Text(title).lineLimit(2).truncationMode(.head).frame(width: 100), device: phone)
        let headLines = try lines(head)
        #expect(headLines.count == 2 && headLines[0].hasPrefix("…"))
        #expect(headLines[1].hasSuffix("2026)"))

        let middle = ViewHost(
            Text(title).lineLimit(3).truncationMode(.middle).frame(width: 100), device: phone)
        let middleLines = try lines(middle)
        #expect(middleLines.count == 3)
        #expect(middleLines[0].hasPrefix("Never"))
        #expect(middleLines[1].contains("…"))
        #expect(middleLines[2].hasSuffix("2026)"))
    }

    @Test("Text that fits is not truncated")
    func fits() throws {
        let host = ViewHost(Text("Short").lineLimit(1), device: phone)
        #expect(try lines(host) == ["Short"])
    }

    @Test("Reserving space makes short text as tall as its limit")
    func reservesSpace() throws {
        func height(_ view: some View) throws -> CGFloat {
            let host = ViewHost(view, device: phone)
            let text = try #require(host.root.allNodes.first { $0.kind == "Text" })
            return try #require(text.frame).height
        }
        #expect(try height(Text("Short").lineLimit(3)) == 22)
        #expect(try height(Text("Short").lineLimit(3, reservesSpace: true)) == 66)
        #expect(try height(Text("Short").lineLimit(2...5)) == 22)
    }

    @Test("In a row, a long title gives way to the text beside it")
    func row() throws {
        let host = ViewHost(
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text("3:21")
            }
            .padding(.horizontal, 10),
            device: phone)
        let texts = host.root.allNodes.filter { $0.kind == "Text" }
        let first = try #require(texts[0].frame)
        let duration = try #require(texts[1].frame)
        #expect(first.height == 22)
        #expect(first.maxX <= duration.minX)
        #expect(duration.maxX <= 190.5)
        #expect(try #require(try lines(host).first).hasSuffix("…"))
    }

    @Test("Truncated text draws, and draws less than the full title")
    func draws() {
        let full = ViewHost(Text(title).frame(width: 300, alignment: .leading), device: phone)
        let cut = ViewHost(
            Text(title).lineLimit(1).frame(width: 100, alignment: .leading), device: phone)
        func inkRight(_ host: ViewHost) -> Int {
            let frame = host.render(scale: 1)
            let text = host.root.allNodes.first { $0.kind == "Text" }?.frame ?? .zero
            let top = Int(text.minY)
            var right = 0
            for x in 0..<frame.pixelWidth {
                for y in top..<(top + 22) {
                    let pixel = frame.color(at: CGPoint(x: x, y: y))
                    if pixel.red < 200 { right = max(right, x) }
                }
            }
            return right - Int(text.minX)
        }
        #expect(inkRight(cut) > 50 && inkRight(cut) <= 101)
        #expect(inkRight(full) > inkRight(cut))
    }
}

@MainActor
private struct CookieForm: View {
    @State var text = ""
    var limit: ClosedRange<Int> = 1...4

    var body: some View {
        VStack {
            TextField("Type it instead", text: $text, axis: .vertical)
                .lineLimit(limit)
            Text("After")
        }
        .padding(10)
    }
}

@MainActor
private func click(_ host: ViewHost, _ point: CGPoint) {
    host.pointerDown(at: point)
    host.pointerUp(at: point)
}

@MainActor
private func field(_ host: ViewHost) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.kind == "TextField" })
}

@MainActor
@Suite("Vertical text fields")
struct VerticalTextFieldTests {
    @Test("A vertical field records its axis and limits in the outline")
    func outline() {
        let host = ViewHost(
            VStack {
                TextField("One", text: .constant(""))
                TextField("Many", text: .constant(""), axis: .vertical).lineLimit(2...6)
                TextField("Three", text: .constant("x"), axis: .vertical).lineLimit(3)
                TextField("Side", text: .constant(""), axis: .horizontal)
            },
            device: phone)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ TextField placeholder=One value=
                   ├─ TextField axis=vertical lineLimit=6 lineLimitMinimum=2 placeholder=Many value=
                   ├─ TextField axis=vertical lineLimit=3 placeholder=Three value=x
                   └─ TextField placeholder=Side value=
                """)
    }

    @Test("A vertical field starts one line tall and grows to four lines as text is typed")
    func grows() throws {
        let host = ViewHost(CookieForm(), device: phone)
        let id = try field(host).id
        #expect(try #require(field(host).frame).height == 22)
        let after = try #require(host.nodes(withText: "After").first)
        let firstY = try #require(after.frame).minY

        try host.focus(id)
        var heights: [CGFloat] = []
        for _ in 0..<12 {
            host.typeText("lorem ipsum ")
            heights.append(try #require(field(host).frame).height)
        }
        // Each line is 22 points; the field grows by lines and stops at 4.
        #expect(heights.first == 22)
        #expect(heights.contains(44) && heights.contains(66) && heights.contains(88))
        #expect(heights.max() == 88 && heights.last == 88)
        #expect(heights == heights.sorted())
        // The stack is centered, so the text below moves down by half the growth.
        let afterNode = try #require(host.nodes(withText: "After").first)
        #expect(try #require(afterNode.frame).minY == firstY + 33)
    }

    @Test("Return starts a new line, and Up and Down move the caret between lines")
    func newlines() throws {
        let host = ViewHost(CookieForm(), device: phone)
        let id = try field(host).id
        try host.focus(id)
        host.typeText("one")
        host.press(.return)
        host.typeText("two")
        host.press(.return)
        host.typeText("three")
        #expect(try field(host).attributes["value"] == "one\ntwo\nthree")
        #expect(try #require(field(host).frame).height == 66)
        #expect(host.focusedNodeID == id)

        host.press(.up)
        #expect(host.caretOffset == 7)
        host.press(.home)
        #expect(host.caretOffset == 4)
        host.press(.up)
        host.press(.end)
        #expect(host.caretOffset == 3)
        host.press(.down)
        #expect((4...7).contains(host.caretOffset))
        host.press(.down)
        #expect((8...13).contains(host.caretOffset))
        // Down on the last line goes to the end of the text.
        host.press(.down)
        #expect(host.caretOffset == 13)
        host.press(.up)
        host.press(.up)
        host.press(.up)
        #expect(host.caretOffset == 0)
    }

    @Test("Clicking a line puts the caret on that line")
    func clicking() throws {
        let host = ViewHost(CookieForm(), device: phone)
        try host.focus(try field(host).id)
        host.typeText("one")
        host.press(.return)
        host.typeText("two")
        host.press(.return)
        host.typeText("three")
        let frame = try #require(field(host).frame)
        click(host, CGPoint(x: frame.minX + 1, y: frame.minY + 33))
        #expect(host.caretOffset == 4)
        click(host, CGPoint(x: frame.minX + 150, y: frame.minY + 55))
        #expect(host.caretOffset == 13)
        click(host, CGPoint(x: frame.minX + 150, y: frame.minY + 5))
        #expect(host.caretOffset == 3)
    }

    @Test("Long text wraps at the field's width")
    func wraps() throws {
        let host = ViewHost(CookieForm(), device: phone)
        try host.focus(try field(host).id)
        host.typeText("the quick brown fox jumps over the lazy dog")
        let frame = try #require(field(host).frame)
        #expect(frame.height > 22 && frame.width == 180)
        #expect(host.caretOffset == 43)
    }

    @Test("Past the limit the field stops growing and shows the caret's line")
    func scrolls() throws {
        let host = ViewHost(CookieForm(limit: 1...2), device: phone)
        try host.focus(try field(host).id)
        for word in ["alpha", "beta", "gamma", "delta"] {
            host.typeText(word)
            host.press(.return)
        }
        #expect(try #require(field(host).frame).height == 44)
        let image = host.render(scale: 1)
        let frame = try #require(field(host).frame)
        // The last two lines show: the fourth word and the empty line with
        // the caret, so the first word's line is blank.
        var ink = 0
        for x in Int(frame.minX)..<Int(frame.maxX) {
            for y in Int(frame.minY)..<Int(frame.minY + 22)
            where image.color(at: CGPoint(x: x, y: y)).red < 200 {
                ink += 1
            }
        }
        #expect(ink > 0)
    }

    @Test("The minimum of a range and reserved space set the starting height")
    func minimum() throws {
        let host = ViewHost(
            VStack {
                TextField("A", text: .constant(""), axis: .vertical).lineLimit(3...6)
                TextField("B", text: .constant(""), axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                TextField("C", text: .constant(""), axis: .vertical).lineLimit(2)
            },
            device: phone)
        let heights = host.root.allNodes.filter { $0.kind == "TextField" }.compactMap {
            $0.frame?.height
        }
        #expect(heights == [66, 44, 22])
    }

    @Test("A one-line field ignores the limit and never grows")
    func horizontal() throws {
        let host = ViewHost(
            TextField("Name", text: .constant("a very long name that would wrap"))
                .lineLimit(4),
            device: phone)
        #expect(try #require(field(host).frame).height == 22)
    }

    @Test("Return still ends editing in a one-line field")
    func returnEnds() throws {
        let host = ViewHost(TextField("Name", text: .constant("")), device: phone)
        try host.focus(try field(host).id)
        host.press(.return)
        #expect(host.focusedNodeID == nil)
    }
}
