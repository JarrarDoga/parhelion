import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

/// The host's current frame drawn from scratch, without its cache.
@MainActor
private func uncachedFrame(_ host: ViewHost, scale: Double) -> Canvas {
    TreeRenderer(
        device: host.device, pressedNodeID: host.pressedNodeID,
        focusedNodeID: host.focusedNodeID, caretOffset: host.caretOffset
    )
    .render(host.presentedRoot, scale: scale)
}

/// Whether two frames have the same size and the same bytes.
private func identical(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    return a.withUnsafeBytes { a in
        b.withUnsafeBytes { b in memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 }
    }
}

/// Draws a frame through the host's cache and checks it against the same
/// frame drawn from scratch.
@MainActor
private func expectCachedFrameMatches(
    _ host: ViewHost, scale: Double = 2, sourceLocation: SourceLocation = #_sourceLocation
) {
    let cached = host.render(scale: scale).pixels
    #expect(
        identical(cached, uncachedFrame(host, scale: scale).pixels),
        "frame at \(host.time) s", sourceLocation: sourceLocation)
}

/// Steps the host's clock until nothing moves, drawing every frame through
/// the cache, as the preview does, and checking every `stride`th frame and
/// the last against a frame drawn from scratch. Frames are drawn at 1×
/// and 60 Hz, which keeps the test quick in debug builds; the cache works
/// the same at every scale and rate.
@MainActor
private func expectAnimationMatches(
    _ host: ViewHost, stride: Int = 6, scale: Double = 1,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var frames = 0
    while host.isAnimating, frames < 200 {
        host.advanceTime(by: 1.0 / 60)
        frames += 1
        if frames % stride == 0 || !host.isAnimating {
            expectCachedFrameMatches(host, scale: scale, sourceLocation: sourceLocation)
        } else {
            _ = host.render(scale: scale)
        }
    }
    #expect(frames > stride, sourceLocation: sourceLocation)
}

/// A field in a sheet whose text also shows on the screen beneath it.
private struct Echo: View {
    @State private var text = ""
    @State private var isEditing = true

    var body: some View {
        NavigationStack {
            Text("Typed: \(text)")
                .navigationTitle("Echo")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { isEditing = true }
                    }
                }
        }
        .sheet(isPresented: $isEditing) {
            TextField("Text", text: $text)
                .presentationDetents([.medium])
        }
    }
}

/// A long list under a large title with a glass toolbar button.
private struct LongList: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(1..<41) { row in
                    Text("Row \(row)")
                }
            }
            .navigationTitle("Rows")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {}
                }
            }
        }
    }
}

/// The pixels of a canvas inside and outside a box, as words.
private func split(_ canvas: Canvas, by box: PixelBox) -> (inside: [UInt32], outside: [UInt32]) {
    var inside: [UInt32] = []
    var outside: [UInt32] = []
    canvas.pixels.withUnsafeBytes { raw in
        let words = raw.bindMemory(to: UInt32.self)
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let isInside = x >= box.minX && x < box.maxX && y >= box.minY && y < box.maxY
                if isInside {
                    inside.append(words[y * canvas.width + x])
                } else {
                    outside.append(words[y * canvas.width + x])
                }
            }
        }
    }
    return (inside, outside)
}

@MainActor
@Suite("Render cache")
struct RenderCacheTests {
    @Test(
        "The glass region holds every pixel that glass reads or changes", arguments: [1.0, 2.0])
    func glassRegion(scale: Double) {
        // Stripes in both directions, so no backdrop is flat.
        var background = Canvas(width: 300, height: 500, scale: scale)
        for index in 0..<50 {
            let level = UInt8(index * 5)
            background.fill(
                CGRect(x: 0, y: Double(index) * 10, width: 300, height: 4),
                color: RGBA(red: level, green: 140, blue: 255 - level))
            background.fill(
                CGRect(x: Double(index) * 6, y: 0, width: 2, height: 500),
                color: RGBA(red: 30, green: level, blue: 90, alpha: 160))
        }
        // The shadow reaches farther than the blur in every material, so one
        // without a shadow checks the blur's reach on its own.
        var unshadowed = ColorPalette.largeGlass
        unshadowed.shadow = .init(color: .clear, offset: 0, blur: 0)
        let blue = RGBA(red: 0, green: 136, blue: 255)
        let surfaces: [(CGRect, CGFloat, Path.CornerStyle, GlassMaterial, RGBA?)] = [
            (
                CGRect(x: 120.3, y: 210.7, width: 54, height: 44), 22, .circular,
                ColorPalette.smallGlass, nil
            ),
            (
                CGRect(x: 80, y: 190, width: 140, height: 120), 34, .continuous,
                ColorPalette.largeGlass, nil
            ),
            (CGRect(x: 80, y: 190.4, width: 140, height: 120), 34, .continuous, unshadowed, nil),
            (
                CGRect(x: 70.5, y: 170.25, width: 160, height: 150), 38, .continuous,
                ColorPalette.partialSheetGlass, nil
            ),
            (
                CGRect(x: 125, y: 230, width: 60, height: 44), 22, .circular,
                ColorPalette.prominentGlass, blue
            ),
        ]
        for (rect, radius, style, material, tint) in surfaces {
            for clip in [nil, CGRect(x: 100, y: 200, width: 100, height: 70)] {
                var canvas = background
                canvas.clipRect = clip
                let region = canvas.glassRegion(rect, material: material, tint: tint)
                #expect(region.minY > 0 && region.maxY < canvas.height)
                var drawn = canvas
                drawn.drawGlass(
                    rect, cornerRadius: radius, style: style, material: material, tint: tint)
                let before = split(canvas, by: region)
                let after = split(drawn, by: region)
                #expect(before.inside != after.inside)
                #expect(before.outside == after.outside)

                // Every pixel outside the region painted over, at whole
                // pixels, does not change the glass inside it.
                var altered = canvas
                altered.clipRect = nil
                let magenta = RGBA(red: 255, green: 0, blue: 255)
                let size = (
                    width: Double(canvas.width) / scale, height: Double(canvas.height) / scale
                )
                let edges = (
                    minX: Double(region.minX) / scale, minY: Double(region.minY) / scale,
                    maxX: Double(region.maxX) / scale, maxY: Double(region.maxY) / scale
                )
                altered.fill(
                    CGRect(x: 0, y: 0, width: size.width, height: edges.minY), color: magenta)
                altered.fill(
                    CGRect(
                        x: 0, y: edges.maxY, width: size.width, height: size.height - edges.maxY),
                    color: magenta)
                altered.fill(
                    CGRect(x: 0, y: edges.minY, width: edges.minX, height: edges.maxY - edges.minY),
                    color: magenta)
                altered.fill(
                    CGRect(
                        x: edges.maxX, y: edges.minY, width: size.width - edges.maxX,
                        height: edges.maxY - edges.minY),
                    color: magenta)
                #expect(split(altered, by: region).inside == before.inside)
                altered.clipRect = clip
                altered.drawGlass(
                    rect, cornerRadius: radius, style: style, material: material, tint: tint)
                #expect(split(altered, by: region).inside == after.inside)
            }
        }
    }

    @Test("Frames of an alert fading in and out match frames drawn from scratch")
    func alertFade() throws {
        let host = try TasksScreens.host(showing: .detail)
        expectCachedFrameMatches(host)
        try host.tapButton(labeled: "Delete")
        expectCachedFrameMatches(host)
        host.advanceTime(by: 1.0 / 120)
        expectCachedFrameMatches(host)
        // The screen beneath and the alert at full opacity are kept.
        #expect(host.renderCache.backdrop != nil)
        #expect(host.renderCache.layer != nil)
        expectAnimationMatches(host)
        // The settled alert is the layer the fade kept, until it changes.
        #expect(host.renderCache.layer != nil)
        let cancel = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Cancel" }?.frame)
        host.pointerDown(at: CGPoint(x: cancel.midX, y: cancel.midY))
        expectCachedFrameMatches(host)
        #expect(host.renderCache.backdrop != nil)
        #expect(host.renderCache.layer == nil)

        host.pointerUp(at: CGPoint(x: cancel.midX, y: cancel.midY))
        expectCachedFrameMatches(host)
        expectAnimationMatches(host)
        // Nothing is presented, so the canvases are gone.
        #expect(host.renderCache.backdrop == nil)
        #expect(host.renderCache.layer == nil)
    }

    @Test("Frames of a sheet sliding up and down match frames drawn from scratch")
    func sheetSlide() throws {
        let host = try TasksScreens.host(showing: .list)
        expectCachedFrameMatches(host)
        try host.tapButton(labeled: "Add")
        expectCachedFrameMatches(host)
        expectAnimationMatches(host)
        #expect(host.renderCache.backdrop != nil)

        // Dragging the sheet down redraws it over the same backdrop.
        host.pointerDown(at: CGPoint(x: 200, y: 400))
        host.pointerMoved(to: CGPoint(x: 200, y: 440))
        expectCachedFrameMatches(host)
        host.pointerMoved(to: CGPoint(x: 200, y: 470))
        expectCachedFrameMatches(host)
        host.pointerUp(at: CGPoint(x: 200, y: 470))
        expectAnimationMatches(host)

        try host.tapButton(labeled: "Cancel")
        expectAnimationMatches(host)
        #expect(host.renderCache.backdrop == nil)
    }

    @Test("A change beneath a sheet draws the screen beneath again")
    func changeBeneathSheet() throws {
        let host = ViewHost(Echo())
        host.advanceTime(by: 2)
        expectCachedFrameMatches(host)
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        try host.focus(field.id)
        expectCachedFrameMatches(host)
        host.typeText("Hi")
        expectCachedFrameMatches(host)
        #expect(host.root.allNodes.contains { $0.text == "Typed: Hi" })
        host.typeText("!")
        expectCachedFrameMatches(host)
        // Another scale draws the backdrop again too.
        expectCachedFrameMatches(host, scale: 3)
        expectCachedFrameMatches(host, scale: 2)
    }

    @Test("Glass over a still bar is reused while a list scrolls beneath it")
    func glassOverScrolling() throws {
        let host = ViewHost(LongList())
        expectCachedFrameMatches(host)
        host.pointerDown(at: CGPoint(x: 200, y: 700))
        for step in 1...6 {
            host.advanceTime(by: 1.0 / 120)
            host.pointerMoved(to: CGPoint(x: 200, y: 700 - 25 * Double(step)))
        }
        host.pointerUp(at: CGPoint(x: 200, y: 550))
        expectAnimationMatches(host, stride: 7)
        // The toolbar button's glass was kept and reused in nearly every
        // frame.
        #expect(host.renderCache.glassCount == 1)
        #expect(host.renderCache.glassReuses > 20)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(try #require(host.scrollOffset(of: list.id)).y > 100)
    }

    @Test("Pressing a button in an alert reuses the alert's glass")
    func pressInAlert() throws {
        let host = try TasksScreens.host(showing: .alert)
        expectCachedFrameMatches(host)
        expectCachedFrameMatches(host)
        let cancel = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Cancel" }?.frame)
        host.pointerDown(at: CGPoint(x: cancel.midX, y: cancel.midY))
        #expect(host.pressedNodeID != nil)
        expectCachedFrameMatches(host)
        host.pointerMoved(to: CGPoint(x: cancel.midX, y: cancel.midY - 100))
        expectCachedFrameMatches(host)
        // The back button beneath is in the kept backdrop; the alert's glass
        // is the one surface drawn in every frame.
        #expect(host.renderCache.glassCount == 1)
        #expect(host.renderCache.glassReuses == 2)
    }

    @Test("A fading alert blends over the screen as one group")
    func groupOpacity() throws {
        let host = try TasksScreens.host(showing: .detail)
        let beneath = host.render(scale: 2).canvas
        try host.tapButton(labeled: "Delete")
        host.advanceTime(by: 0.05)
        let alert = try #require(host.presentedRoot.children.last)
        #expect(alert.kind == "Alert")
        let opacity = alert.opacity
        #expect(opacity > 0.05 && opacity < 0.95)
        let fading = host.render(scale: 2).canvas
        host.advanceTime(by: 2)
        let settled = host.render(scale: 2).canvas
        // Every pixel, including the blurred ones inside the glass, is the
        // screen beneath moved toward the settled alert by the opacity.
        let blended = Canvas(blending: settled, over: beneath, opacity: opacity)
        #expect(identical(fading.pixels, blended.pixels))
    }
}
