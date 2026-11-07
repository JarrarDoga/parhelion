import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

@MainActor
private func color(_ host: ViewHost, _ x: Double, _ y: Double) -> (red: Int, green: Int, blue: Int)
{
    let pixel = host.render(scale: 1).color(at: CGPoint(x: x, y: y))
    return (Int(pixel.red), Int(pixel.green), Int(pixel.blue))
}

private func isWhite(_ pixel: (red: Int, green: Int, blue: Int)) -> Bool {
    pixel.red > 250 && pixel.green > 250 && pixel.blue > 250
}

/// Opaque red against the white background: a high red and a low green.
private func isRed(_ pixel: (red: Int, green: Int, blue: Int)) -> Bool {
    pixel.red > 240 && pixel.green < 90
}

@MainActor
@Suite("rotationEffect, blur, and mask")
struct TransformEffectTests {
    // MARK: Outlines

    @Test("rotationEffect, blur, and mask appear in the outline, in their place in the chain")
    func outline() {
        let host = ViewHost(
            Color.red.frame(width: 20, height: 20)
                .rotationEffect(.degrees(-7))
                .blur(radius: 4)
                .blur(radius: 2.5, opaque: true)
                .rotationEffect(.radians(.pi / 2), anchor: .topLeading),
            device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ Color frame(width: 20, height: 20) rotationEffect(-7°) blur(radius: 4) blur(radius: 2.5, opaque) rotationEffect(90°, anchor: topLeading) color=red
                """)
    }

    @Test("A mask's views are an Overlay child, laid out in the view's bounds")
    func maskOutline() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask(alignment: .leading) { Color.black.frame(width: 50) },
            device: square)
        #expect(
            host.root.outline(includeIDs: true) == """
                Root
                └─ Color frame(width: 100, height: 100) overlay(alignment: leading) mask color=red  #Color
                   └─ Overlay  #Color/mask
                      └─ Color frame(width: 50) color=black  #Color/mask/Color
                """)
        let node = host.root.children[0]
        #expect(node.frame == CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(node.children[0].children[0].frame == CGRect(x: 50, y: 50, width: 50, height: 100))
    }

    @Test("None of them changes the layout around the view")
    func layoutIsUnchanged() {
        let plain = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 20)
                Color.blue.frame(width: 40, height: 20)
            }, device: square)
        let changed = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 20)
                    .rotationEffect(.degrees(30)).blur(radius: 6)
                    .mask { Color.black }
                Color.blue.frame(width: 40, height: 20)
            }, device: square)
        #expect(plain.root.children.map(\.frame) == changed.root.children.map(\.frame))
    }

    // MARK: rotationEffect

    @Test("A quarter turn clockwise stands a bar upright around its center")
    func quarterTurn() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 20).rotationEffect(.degrees(90)), device: square)
        #expect(isRed(color(host, 100, 60)))
        #expect(isRed(color(host, 100, 140)))
        #expect(isWhite(color(host, 60, 100)))
        #expect(isWhite(color(host, 140, 100)))
    }

    @Test("The anchor is the point it turns around, in the view's bounds")
    func anchor() {
        // The bar spans x 50...150 and y 90...110. Turned a quarter around its
        // top-leading corner, it hangs down from (50, 90).
        let host = ViewHost(
            Color.red.frame(width: 100, height: 20)
                .rotationEffect(.degrees(90), anchor: .topLeading),
            device: square)
        #expect(isRed(color(host, 40, 150)))
        #expect(isWhite(color(host, 100, 100)))
        #expect(isWhite(color(host, 60, 150)))
    }

    @Test("A turn of a few degrees tilts the edges, with anti-aliasing")
    func tilt() {
        // Turned -7° (counterclockwise), the bar's right end rises.
        let host = ViewHost(
            Color.red.frame(width: 120, height: 20).rotationEffect(.degrees(-7)), device: square)
        let rise = 60 * tan(7.0 * .pi / 180)
        #expect(isRed(color(host, 140, 100 - rise)))
        #expect(isWhite(color(host, 140, 100 + rise + 8)))
        #expect(isRed(color(host, 60, 100 + rise)))
        #expect(isWhite(color(host, 60, 100 - rise - 8)))
        // Along the top edge, some pixels are part covered.
        let edge = color(host, 100, 100 - 10 / cos(7.0 * .pi / 180) + 3.5)
        #expect(!isWhite(edge))
    }

    @Test("It rotates the view's backgrounds, overlays, and children with it")
    func content() {
        let host = ViewHost(
            Text("Hello there").padding(.horizontal, 40).padding(.vertical, 10).background(
                Color.red
            ).foregroundStyle(.white)
                .rotationEffect(.degrees(90)),
            device: square)
        let node = host.root.children[0]
        let frame = node.modifierFrames.last ?? .zero
        // The padded box is wider than tall; turned, it is taller than wide.
        #expect(frame.width > frame.height)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        #expect(isRed(color(host, center.x, center.y - frame.width / 2 + 2)))
        #expect(isWhite(color(host, center.x + frame.width / 2 - 2, center.y)))
    }

    @Test("A turn of zero or a full turn draws as without it")
    func noTurn() {
        let plain = ViewHost(Color.red.frame(width: 60, height: 30), device: square)
        let full = ViewHost(
            Color.red.frame(width: 60, height: 30).rotationEffect(.degrees(360)), device: square)
        #expect(plain.render(scale: 2).canvas.pixels == full.render(scale: 2).canvas.pixels)
    }

    // MARK: blur

    @Test("A blur spreads a view past its edges and softens them")
    func blur() {
        let host = ViewHost(Color.red.frame(width: 60, height: 60).blur(radius: 8), device: square)
        // The middle is untouched, and the edge is halfway.
        #expect(isRed(color(host, 100, 100)))
        let edge = color(host, 70, 100)
        #expect(edge.red > 240 && edge.green > 100 && edge.green < 200)
        // Outside the edge is part red; far away is white.
        let outside = color(host, 62, 100)
        #expect(outside.green < 250 && outside.green > edge.green)
        #expect(isWhite(color(host, 30, 100)))
        // Inside the edge, the red is lighter than in the middle.
        #expect(color(host, 75, 100).green > 20)
    }

    @Test("A blur of zero draws the view as it is")
    func blurZero() {
        let plain = ViewHost(Color.red.frame(width: 60, height: 60), device: square)
        let blurred = ViewHost(
            Color.red.frame(width: 60, height: 60).blur(radius: 0), device: square)
        #expect(plain.render(scale: 1).canvas.pixels == blurred.render(scale: 1).canvas.pixels)
    }

    @Test("An opaque blur stays inside the view's bounds and does not fade at its edge")
    func opaqueBlur() {
        let host = ViewHost(
            Color.red.frame(width: 60, height: 60).blur(radius: 8, opaque: true), device: square)
        #expect(isRed(color(host, 71, 100)))
        #expect(isRed(color(host, 100, 71)))
        #expect(isWhite(color(host, 60, 100)))
    }

    @Test("It blurs the colors of a view with several, in place")
    func blurMixesColors() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 80)
                Color.blue.frame(width: 40, height: 80)
            }.blur(radius: 6),
            device: square)
        // At the seam, red and blue mix.
        let seam = color(host, 100, 100)
        #expect(seam.red > 90 && seam.blue > 90)
        #expect(color(host, 70, 100).red > color(host, 130, 100).red)
    }

    // MARK: mask

    @Test("A gradient mask fades a view from opaque to transparent")
    func gradientMask() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask {
                    LinearGradient(
                        colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                },
            device: square)
        let top = color(host, 100, 51)
        let middle = color(host, 100, 100)
        let bottom = color(host, 100, 149)
        #expect(isRed(top))
        #expect(middle.red > 240 && middle.green > 100 && middle.green < 160)
        #expect(bottom.green > 240)
        #expect(isWhite(color(host, 100, 40)))
    }

    @Test("A mask shows the view only where it is opaque, placed by its alignment")
    func shapeMask() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask(alignment: .leading) { Color.black.frame(width: 50) },
            device: square)
        #expect(isRed(color(host, 70, 100)))
        #expect(isWhite(color(host, 130, 100)))
        let centered = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask { Circle().frame(width: 60, height: 60) },
            device: square)
        #expect(isRed(color(centered, 100, 100)))
        #expect(isWhite(color(centered, 58, 58)))
    }

    @Test("A mask uses its views' alpha, not their color")
    func maskAlpha() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask { Color.white.opacity(0.5) },
            device: square)
        let pixel = color(host, 100, 100)
        #expect(pixel.red > 240 && pixel.green > 100 && pixel.green < 160)
    }

    @Test("A mask applies to what is inside it only, and a background outside it is whole")
    func maskOrder() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .mask(alignment: .leading) { Color.black.frame(width: 50) }
                .background(Color.blue),
            device: square)
        #expect(isRed(color(host, 70, 100)))
        let masked = color(host, 130, 100)
        #expect(masked.blue > 200 && masked.red < 60)
    }

    @Test("Masks, a rotation, and a blur combine in the order they are written")
    func combined() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 20)
                .mask(alignment: .leading) { Color.black.frame(width: 50) }
                .rotationEffect(.degrees(90)),
            device: square)
        // The left half stands up, in the top half of the turn.
        #expect(isRed(color(host, 100, 70)))
        #expect(isWhite(color(host, 100, 130)))
    }

    // MARK: The art wall

    /// Writes the art wall to a directory, when `PARHELION_TRANSFORM_PNG_DIR`
    /// names one. `docs/images/art-wall.png` came from it.
    @Test("Rustle's art wall: five tiles across, turned -7°, faded by 84 % with a gradient mask")
    func artWall() throws {
        let host = ViewHost(ArtWall(), device: .iPhone18ProMax)
        let frame = host.render(scale: 2, chrome: .systemBars)
        // The wall is opaque at the top of its mask and gone at the bottom.
        let top = frame.color(at: CGPoint(x: 220, y: 175))
        let bottom = frame.color(at: CGPoint(x: 220, y: 480))
        #expect(top.red != 255 || top.green != 255 || top.blue != 255)
        #expect(bottom.red > 250 && bottom.green > 250 && bottom.blue > 250)
        // The turn lifts the wall's right side: its top edge is above where the
        // left side's is, so the same row of pixels is wall on the right only.
        let left = frame.color(at: CGPoint(x: 30, y: 145))
        let right = frame.color(at: CGPoint(x: 400, y: 145))
        #expect(left.red > 250 && left.green > 250 && left.blue > 250)
        #expect(right.red < 200 || right.green < 200)
        if let directory = ProcessInfo.processInfo.environment["PARHELION_TRANSFORM_PNG_DIR"] {
            try host.render(scale: 1, chrome: .systemBars).pngData()
                .write(to: URL(fileURLWithPath: directory + "/art-wall.png"))
            let blurred = ViewHost(BlurredBackdrop(), device: .iPhone18ProMax)
            try blurred.render(scale: 1, chrome: .systemBars).pngData()
                .write(to: URL(fileURLWithPath: directory + "/blurred-art.png"))
        }
    }
}

/// Rustle's art wall, built from the sizes in the issue: five tiles across,
/// four rows, turned -7° and faded by 84 % toward the bottom.
private struct ArtWall: View {
    private let tiles: [[Color]] = [
        [.red, .orange, .yellow, .green, .mint],
        [.teal, .cyan, .blue, .indigo, .purple],
        [.pink, .red, .orange, .yellow, .green],
        [.mint, .teal, .cyan, .blue, .indigo],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                ForEach(0..<tiles.count, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { column in
                            tiles[row][column]
                                .overlay {
                                    LinearGradient(
                                        colors: [.white.opacity(0.35), .black.opacity(0.25)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, -30)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .clear, location: 0.84),
                    ], startPoint: .top, endPoint: .bottom)
            }
            .rotationEffect(.degrees(-7))
            .frame(height: 380)
            Spacer()
        }
        .padding(.top, 90)
    }
}

/// A still blur of artwork behind a screen, as Now Playing has.
private struct BlurredBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .pink, .orange], startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay { Circle().fill(.white).frame(width: 160, height: 160).offset(y: -120) }
            .blur(radius: 30, opaque: true)
            Text("Now Playing").font(.title).bold().foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
