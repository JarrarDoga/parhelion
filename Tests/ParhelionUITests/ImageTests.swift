import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

/// A PNG image of one color.
private func solidPNG(width: Int, height: Int, _ color: RGBA) -> [UInt8] {
    Canvas(width: Double(width), height: Double(height), scale: 1, background: color).pngData()
}

/// A PNG image of a white square with a black border `border` pixels wide.
private func framedPNG(side: Int, border: Int) -> [UInt8] {
    var canvas = Canvas(width: Double(side), height: Double(side), scale: 1, background: .black)
    canvas.fill(
        CGRect(
            x: border, y: border, width: side - 2 * border, height: side - 2 * border),
        color: .white)
    return canvas.pngData()
}

/// A bundle folder with an asset catalog, as SwiftPM copies an app
/// target's catalog into its resource bundle on Linux.
private let fixtureBundle: Bundle = {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "parhelion-image-tests-\(ProcessInfo.processInfo.processIdentifier)")
    let bundle = root.appendingPathComponent("Fixture.bundle")
    let catalog = bundle.appendingPathComponent("Assets.xcassets")
    func write(_ path: String, _ contents: String) {
        let url = catalog.appendingPathComponent(path)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
    }
    func write(_ path: String, _ bytes: [UInt8]) {
        let url = catalog.appendingPathComponent(path)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(bytes).write(to: url)
    }
    write("Contents.json", #"{"info": {"author": "xcode", "version": 1}}"#)
    // A different color at each scale, so a test can tell which was drawn.
    write("Dot.imageset/dot.png", solidPNG(width: 10, height: 8, RGBA(red: 255, green: 0, blue: 0)))
    write(
        "Dot.imageset/dot@2x.png",
        solidPNG(width: 20, height: 16, RGBA(red: 0, green: 0, blue: 255)))
    write(
        "Dot.imageset/dot@3x.png",
        solidPNG(width: 30, height: 24, RGBA(red: 0, green: 255, blue: 0)))
    write(
        "Dot.imageset/Contents.json",
        """
        {"images": [
          {"filename": "dot.png", "idiom": "universal", "scale": "1x"},
          {"filename": "dot@2x.png", "idiom": "universal", "scale": "2x"},
          {"filename": "dot@3x.png", "idiom": "universal", "scale": "3x"},
          {"filename": "dot-ipad.png", "idiom": "ipad", "scale": "2x"}
        ], "info": {"author": "xcode", "version": 1}}
        """)
    write(
        "Mode.imageset/light.png",
        solidPNG(width: 10, height: 10, RGBA(red: 255, green: 255, blue: 0)))
    write(
        "Mode.imageset/dark.png",
        solidPNG(width: 10, height: 10, RGBA(red: 40, green: 40, blue: 40)))
    write(
        "Mode.imageset/Contents.json",
        """
        {"images": [
          {"filename": "light.png", "idiom": "universal", "scale": "2x"},
          {"filename": "dark.png", "idiom": "universal", "scale": "2x",
           "appearances": [{"appearance": "luminosity", "value": "dark"}]}
        ]}
        """)
    write("StarTemplate.imageset/star.png", solidPNG(width: 10, height: 10, .white))
    write(
        "StarTemplate.imageset/Contents.json",
        #"{"images": [{"filename": "star.png", "idiom": "universal", "scale": "1x"}]}"#)
    write("Photo.imageset/photo.png", solidPNG(width: 10, height: 10, .white))
    write(
        "Photo.imageset/Contents.json",
        """
        {"images": [{"filename": "photo.png", "idiom": "universal", "scale": "1x"}],
         "properties": {"template-rendering-intent": "original"}}
        """)
    write("Icons/Contents.json", #"{"properties": {"provides-namespace": true}}"#)
    write("Icons/Gear.imageset/gear.png", solidPNG(width: 12, height: 12, .black))
    write(
        "Icons/Gear.imageset/Contents.json",
        """
        {"images": [{"filename": "gear.png", "idiom": "universal", "scale": "1x"}],
         "properties": {"template-rendering-intent": "template"}}
        """)
    write("Folder/Plain.imageset/plain.png", solidPNG(width: 6, height: 6, .black))
    write(
        "Folder/Plain.imageset/Contents.json",
        #"{"images": [{"filename": "plain.png", "idiom": "universal", "scale": "1x"}]}"#)
    write("Legacy.imageset/legacy.jpg", [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])
    write(
        "Legacy.imageset/Contents.json",
        #"{"images": [{"filename": "legacy.jpg", "idiom": "universal", "scale": "1x"}]}"#)
    write("Frame.imageset/frame.png", framedPNG(side: 30, border: 10))
    write(
        "Frame.imageset/Contents.json",
        #"{"images": [{"filename": "frame.png", "idiom": "universal", "scale": "1x"}]}"#)
    return Bundle(path: bundle.path)!
}()

@MainActor
@Suite("Images")
struct ImageTests {
    @Test("An asset image records its name, bundle, and size in points")
    func assetNodes() {
        let host = ViewHost(
            VStack {
                Image("Dot", bundle: fixtureBundle)
                Image("Icons/Gear", bundle: fixtureBundle)
                Image("Plain", bundle: fixtureBundle)
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Image bundle=Fixture name=Dot size=10 × 8
                   ├─ Image bundle=Fixture name=Icons/Gear renderingMode=template size=12 × 12
                   └─ Image bundle=Fixture name=Plain size=6 × 6
                """)
        #expect(host.root.children[0].children[0].frame?.size == CGSize(width: 10, height: 8))
    }

    @Test("The renderer draws the file for its scale: the smallest at least as large")
    func scales() {
        let host = ViewHost(Image("Dot", bundle: fixtureBundle), device: square)
        let center = CGPoint(x: 100, y: 100)
        #expect(components(host.render(scale: 1).color(at: center)) == [255, 0, 0, 255])
        #expect(components(host.render(scale: 2).color(at: center)) == [0, 0, 255, 255])
        #expect(components(host.render(scale: 3).color(at: center)) == [0, 255, 0, 255])
        #expect(components(host.render(scale: 4).color(at: center)) == [0, 255, 0, 255])
    }

    @Test("In the dark appearance, an image set's dark file draws")
    func darkAppearance() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Image("Mode", bundle: fixtureBundle)
                Image("Mode", bundle: fixtureBundle).environment(\.colorScheme, .dark)
            },
            device: square
        )
        let images = host.root.children[0].children
        #expect(images[0].attributes["appearance"] == nil)
        #expect(images[1].attributes["appearance"] == "dark")
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 97, y: 100))) == [255, 255, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 103, y: 100))) == [40, 40, 40, 255])
    }

    @Test("A template image draws its shape in the foreground color")
    func templates() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Image("StarTemplate", bundle: fixtureBundle)
                Image("StarTemplate", bundle: fixtureBundle).renderingMode(.original)
                Image("Photo", bundle: fixtureBundle).renderingMode(.template)
                Image("Photo", bundle: fixtureBundle)
            }
            .foregroundStyle(.red),
            device: square
        )
        let images = host.root.children[0].children
        #expect(
            images.map { $0.attributes["renderingMode"] } == [
                "template", "original", "template", nil,
            ])
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 85, y: 100))) == [255, 56, 60, 255])
        #expect(components(frame.color(at: CGPoint(x: 95, y: 100))) == [255, 255, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 105, y: 100))) == [255, 56, 60, 255])
    }

    @Test("A missing or unreadable image records missingImage and draws a ring")
    func missingImages() {
        let host = ViewHost(
            VStack {
                Image("Nope", bundle: fixtureBundle)
                Image("Legacy", bundle: fixtureBundle)
            },
            device: square
        )
        let images = host.root.children[0].children
        #expect(images.allSatisfy { $0.attributes["missingImage"] == "true" })
        #expect(images[1].attributes["size"] == nil)
        let side = LayoutDefaults.symbolSide(for: .medium)
        #expect(images[0].frame?.size == CGSize(width: side, height: side))
        // The ring's center is empty.
        let frame = host.render(scale: 2)
        let center = CGPoint(x: images[0].frame!.midX, y: images[0].frame!.midY)
        #expect(components(frame.color(at: center)) == [255, 255, 255, 255])
    }

    @Test("A resizable image fills its frame, and its cap insets keep their size")
    func resizable() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Image("Dot", bundle: fixtureBundle).resizable().frame(width: 100, height: 40)
                Image("Frame", bundle: fixtureBundle)
                    .resizable(
                        capInsets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                    )
                    .frame(width: 100, height: 60)
                Image("Frame", bundle: fixtureBundle)
                    .resizable(
                        capInsets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                        resizingMode: .tile
                    )
                    .frame(width: 100, height: 60)
            },
            device: square
        )
        let images = host.root.children[0].children
        #expect(images[0].frame == CGRect(x: 50, y: 20, width: 100, height: 40))
        #expect(images[0].attributes["resizable"] == "true")
        #expect(images[1].attributes["capInsets"] == "10, 10, 10, 10")
        #expect(images[2].attributes["resizingMode"] == "tile")
        let frame = host.render(scale: 1)
        // The border stays 10 points wide; the white middle stretches.
        #expect(components(frame.color(at: CGPoint(x: 55, y: 90))) == [0, 0, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 65, y: 90))) == [255, 255, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 135, y: 90))) == [255, 255, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 145, y: 90))) == [0, 0, 0, 255])
        // The tiled image, from y 120, has the same border and middle.
        #expect(components(frame.color(at: CGPoint(x: 100, y: 125))) == [0, 0, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 100, y: 150))) == [255, 255, 255, 255])
    }

    @Test("A resizable symbol fills its frame")
    func resizableSymbol() {
        let host = ViewHost(
            Image(systemName: "star.fill").resizable().frame(width: 80, height: 80),
            device: square
        )
        #expect(host.root.children[0].attributes["resizable"] == "true")
        #expect(host.root.children[0].frame?.size == CGSize(width: 80, height: 80))
    }

    @Test("A symbol takes a gradient foreground style")
    func gradientSymbol() {
        let host = ViewHost(
            Image(systemName: "circle.fill").resizable()
                .foregroundStyle(
                    LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 100, height: 100),
            device: square
        )
        let frame = host.render(scale: 1)
        let top = frame.color(at: CGPoint(x: 100, y: 62))
        let bottom = frame.color(at: CGPoint(x: 100, y: 138))
        #expect(top.red > top.blue && bottom.blue > bottom.red)
    }
}
