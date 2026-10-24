import Foundation
import ParhelionPreview
import ParhelionRender
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 300),
    safeAreaInsets: EdgeInsets()
)

/// Text that shows the color scheme it reads from the environment.
private struct SchemeLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(colorScheme == .dark ? "dark" : "light")
    }
}

/// A screen with a button that turns its preference for dark on and off.
private struct PrefersDarkWhenAsked: View {
    @State private var prefersDark = false

    var body: some View {
        VStack {
            SchemeLabel()
            Button("Toggle") { prefersDark.toggle() }
                .preferredColorScheme(prefersDark ? .dark : nil)
        }
    }
}

private func components(_ color: (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
    [color.0, color.1, color.2, color.3]
}

@MainActor
@Suite("Dark mode")
struct DarkModeTests {
    @Test("The device's color scheme reaches the environment, and the root records dark")
    func deviceScheme() {
        let host = ViewHost(SchemeLabel(), device: square)
        #expect(host.root.outline() == "Root\n└─ Text \"light\"")
        host.colorScheme = .dark
        #expect(host.root.outline() == "Root colorScheme=dark\n└─ Text \"dark\"")
        let started = ViewHost(SchemeLabel(), device: square, colorScheme: .dark)
        #expect(started.root.outline() == host.root.outline())
    }

    @Test("A preferred color scheme applies to the whole window, even views before it")
    func preferredScheme() {
        let host = ViewHost(
            VStack {
                SchemeLabel()
                SchemeLabel().preferredColorScheme(.dark)
            }, device: square)
        #expect(
            host.root.outline() == """
                Root colorScheme=dark
                └─ VStack
                   ├─ Text "dark"
                   └─ Text "dark"
                """)
    }

    @Test("An outer preference wins over an inner one, and the first of two siblings wins")
    func preferenceOrder() {
        let siblings = ViewHost(
            VStack {
                SchemeLabel().preferredColorScheme(.light)
                SchemeLabel().preferredColorScheme(.dark)
            }, device: square, colorScheme: .dark)
        #expect(siblings.root.attributes["colorScheme"] == nil)
        #expect(siblings.root.allNodes.compactMap(\.text) == ["light", "light"])

        let nested = ViewHost(
            VStack {
                SchemeLabel().preferredColorScheme(.light)
            }
            .preferredColorScheme(.dark), device: square)
        #expect(nested.root.attributes["colorScheme"] == "dark")
        #expect(nested.root.allNodes.compactMap(\.text) == ["dark"])
    }

    @Test("A nil preference leaves the device's scheme, and removing a preference returns to it")
    func removingPreference() throws {
        let host = ViewHost(PrefersDarkWhenAsked(), device: square)
        #expect(host.root.allNodes.compactMap(\.text) == ["light", "Toggle"])
        try host.tapButton(labeled: "Toggle")
        #expect(host.root.attributes["colorScheme"] == "dark")
        #expect(host.root.allNodes.compactMap(\.text) == ["dark", "Toggle"])
        try host.tapButton(labeled: "Toggle")
        #expect(host.root.attributes["colorScheme"] == nil)
        #expect(host.root.allNodes.compactMap(\.text) == ["light", "Toggle"])
    }

    @Test("A sheet's preference applies to the sheet, not to the window beneath it")
    func sheetPreference() {
        let host = ViewHost(
            SchemeLabel()
                .sheet(isPresented: .constant(true)) {
                    SchemeLabel().preferredColorScheme(.dark)
                }, device: square)
        #expect(
            host.root.outline() == """
                Root
                ├─ Text "light"
                └─ Sheet colorScheme=dark
                   └─ Text "dark"
                """)
    }

    @Test("A sheet without a preference takes the window's")
    func sheetInheritsWindow() {
        let host = ViewHost(
            SchemeLabel()
                .sheet(isPresented: .constant(true)) { SchemeLabel() }
                .preferredColorScheme(.dark), device: square)
        #expect(
            host.root.outline() == """
                Root colorScheme=dark
                ├─ Text "dark"
                └─ Sheet
                   └─ Text "dark"
                """)
    }

    @Test("environment(\\.colorScheme, _:) changes its content and records the scheme there")
    func environmentScheme() {
        let host = ViewHost(
            VStack {
                SchemeLabel()
                VStack { SchemeLabel() }.environment(\.colorScheme, .dark)
                SchemeLabel().environment(\.colorScheme, .light)
            }, device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "light"
                   ├─ VStack colorScheme=dark
                   │  └─ Text "dark"
                   └─ Text "light"
                """)
    }

    @Test("Named colors take the dark swatches of the iOS 27 UI Kit")
    func namedColors() {
        func rgba(_ name: String) -> [UInt8] {
            let color = ColorPalette.color(named: name, in: .dark)
            return [color.red, color.green, color.blue, color.alpha]
        }
        #expect(rgba("blue") == [0, 145, 255, 255])
        #expect(rgba("tint") == [0, 145, 255, 255])
        #expect(rgba("red") == [255, 66, 69, 255])
        #expect(rgba("green") == [48, 209, 88, 255])
        #expect(rgba("indigo") == [109, 124, 255, 255])
        #expect(rgba("gray") == [142, 142, 147, 255])
        #expect(rgba("primary") == [255, 255, 255, 255])
        #expect(rgba("secondary") == [235, 235, 245, 153])
        #expect(rgba("black") == [0, 0, 0, 255])
        #expect(rgba("white") == [255, 255, 255, 255])
        #expect(rgba("blue@0.5") == [0, 145, 255, 128])
        // Light keeps the light swatches.
        #expect(ColorPalette.color(named: "blue") == RGBA(red: 0, green: 136, blue: 255))
        #expect(ColorPalette.color(named: "primary", in: .light) == .black)
    }

    @Test("The dark appearance draws a black screen with white text and system bars")
    func darkFrame() {
        let host = ViewHost(Text("Hello"), device: .iPhone16, colorScheme: .dark)
        let frame = host.render(scale: 1, chrome: .systemBars)
        #expect(components(frame.color(at: CGPoint(x: 20, y: 300))) == [0, 0, 0, 255])
        let screen = Device.iPhone16.screenSize
        // The home indicator is white.
        #expect(
            components(frame.color(at: CGPoint(x: screen.width / 2, y: screen.height - 10.5)))
                == [255, 255, 255, 255])
        // The text's brightest pixel is white.
        let text = host.root.allNodes.first { $0.kind == "Text" }!.frame!
        var brightest: UInt8 = 0
        for x in stride(from: text.minX, to: text.maxX, by: 1) {
            brightest = max(brightest, frame.color(at: CGPoint(x: x, y: text.midY)).red)
        }
        #expect(brightest > 240)
    }

    @Test("Content drawn in its own color scheme uses that scheme's colors")
    func environmentSchemeDraws() {
        let host = ViewHost(
            HStack(spacing: 0) {
                // The color that `.primary` names, as a view.
                Color(name: "primary")
                Color(name: "primary").environment(\.colorScheme, .dark)
            }, device: square)
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 75, y: 150))) == [0, 0, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 225, y: 150))) == [255, 255, 255, 255])
    }

    @Test("A grouped list is black with 28-gray cells, and lighter in a sheet")
    func groupedList() {
        func list() -> some View {
            List {
                Text("Row")
            }
        }
        let host = ViewHost(list(), device: .iPhone16, colorScheme: .dark)
        let row = host.root.allNodes.first { $0.listRowFrame != nil }!.listRowFrame!
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 5, y: row.midY))) == [0, 0, 0, 255])
        #expect(
            components(frame.color(at: CGPoint(x: row.maxX - 5, y: row.midY)))
                == [28, 28, 30, 255])

        let sheet = ViewHost(
            Color.clear.sheet(isPresented: .constant(true)) { list() }, device: .iPhone16,
            colorScheme: .dark)
        sheet.advanceTime(by: 2)
        let cell = sheet.root.allNodes.first { $0.listRowFrame != nil }!.listRowFrame!
        let sheetFrame = sheet.render(scale: 1)
        #expect(
            components(sheetFrame.color(at: CGPoint(x: cell.maxX - 5, y: cell.midY)))
                == [44, 44, 46, 255])
        #expect(
            components(sheetFrame.color(at: CGPoint(x: 5, y: cell.midY))) == [28, 28, 30, 255])
    }

    @Test("Dark glass over black is 26 gray, as the kit's dark materials make it")
    func darkGlass() {
        for material in [ColorPalette.darkSmallGlass, ColorPalette.darkLargeGlass] {
            var canvas = Canvas(width: 200, height: 200, scale: 1, background: .black)
            canvas.drawGlass(
                CGRect(x: 50, y: 50, width: 100, height: 100), cornerRadius: 20,
                material: material)
            let middle = canvas.pixel(x: 100, y: 100)
            #expect([middle.red, middle.green, middle.blue] == [26, 26, 26])
        }
    }

    @Test("setAppearance commands set the device and refuse unknown names")
    func command() {
        let host = ViewHost(SchemeLabel(), device: square)
        let reply = host.execute(
            .setAppearance(colorScheme: "dark", dynamicTypeSize: "accessibility2"))
        #expect(reply.ok)
        #expect(reply.message == "The device is set to dark at Dynamic Type size accessibility2.")
        #expect(host.colorScheme == .dark)
        #expect(host.dynamicTypeSize == .accessibility2)
        #expect(
            host.root.outline()
                == "Root colorScheme=dark dynamicTypeSize=accessibility2\n└─ Text \"dark\" fontSize=33"
        )
        let unknown = host.execute(.setAppearance(colorScheme: "sepia", dynamicTypeSize: nil))
        #expect(!unknown.ok)
        #expect(unknown.message == "Unknown color scheme \"sepia\". Use light or dark.")
        let size = host.execute(.setAppearance(colorScheme: nil, dynamicTypeSize: "huge"))
        #expect(!size.ok)
        #expect(size.message.hasPrefix("Unknown Dynamic Type size \"huge\". Use one of: xSmall,"))
        #expect(host.colorScheme == .dark)
    }

    @Test("Apps take appearance commands")
    func capability() {
        #expect(PreviewCapability.all.contains(PreviewCapability.appearance))
    }
}
