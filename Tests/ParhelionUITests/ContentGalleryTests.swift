import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

// The README's images of shapes, gradients, the styling modifiers, images,
// AsyncImage, and grids. The images come from an asset catalog this file
// draws and writes to a temporary bundle, as SwiftPM copies an app's
// catalog into its target's bundle on Linux.

/// A slice of a pie, as an app would write a shape of its own.
private struct Wedge: Shape {
    var start: Angle
    var end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center, radius: min(rect.width, rect.height) / 2, startAngle: start,
            endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct ShapesScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Shapes").font(.largeTitle.bold())
            HStack(spacing: 12) {
                Rectangle().fill(.red).frame(width: 50)
                RoundedRectangle(cornerRadius: 12).fill(.orange).frame(width: 50)
                Circle().fill(.green).frame(width: 50)
                Capsule().fill(.blue).frame(width: 80)
                Ellipse().fill(.purple).frame(width: 70)
            }
            .frame(height: 50)
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.indigo, .pink], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .frame(height: 150)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gradient card").font(.title2.bold())
                        Text("An overlay over a shadowed gradient").font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                }
                .shadow(radius: 10, y: 6)
            HStack(spacing: 24) {
                LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(.green).frame(width: 18, height: 18)
                    }
                ZStack {
                    Wedge(start: .degrees(-90), end: .degrees(30)).fill(.blue)
                    Wedge(start: .degrees(30), end: .degrees(150)).fill(.mint)
                    Wedge(start: .degrees(150), end: .degrees(270)).fill(.indigo)
                }
                .frame(width: 72, height: 72)
                Image(systemName: "star.fill")
                    .font(.title)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .red], startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(1.6)
                Text("Mirror").font(.headline).scaleEffect(x: -1)
            }
            Color.teal
                .frame(height: 56)
                .overlay(Color.white.opacity(0.3), in: Capsule())
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { Text("clipShape and overlay(_:in:)").foregroundStyle(.white) }
        }
        .padding(20)
    }
}

private struct ImagesScreen: View {
    let bundle: Bundle
    let photo: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Images").font(.largeTitle.bold())
            Image("Landscape", bundle: bundle)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            HStack(spacing: 16) {
                Image("Landscape", bundle: bundle).resizable().scaledToFit().frame(width: 110)
                Image("StarTemplate", bundle: bundle).foregroundStyle(.orange)
                Image("Bubble", bundle: bundle)
                    .resizable(
                        capInsets: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
                    )
                    .frame(width: 140, height: 52)
                    .overlay {
                        Text("Cap insets").font(.subheadline)
                            .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 0.2))
                    }
            }
            Text("AsyncImage").font(.headline)
            HStack(spacing: 16) {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                AsyncImage(url: URL(fileURLWithPath: "/nonexistent/parhelion-gallery.png"))
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Image("Missing", bundle: bundle)
            }
        }
        .padding(20)
    }
}

private struct GridsScreen: View {
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Grids").font(.largeTitle.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colors[index])
                        .frame(height: 64)
                        .overlay { Text("\(index + 1)").font(.headline).foregroundStyle(.white) }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Plan").font(.headline)
                    Text("Storage").font(.headline)
                    Text("Price").font(.headline).gridColumnAlignment(.trailing)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Basic")
                    Text("50 GB")
                    Text("$0.99")
                }
                GridRow {
                    Text("Plus")
                    Text("200 GB")
                    Text("$2.99")
                }
                GridRow {
                    Text("Family, shared")
                        .gridCellColumns(2)
                    Text("$9.99")
                }
            }
            LazyHGrid(rows: [GridItem(.fixed(36)), GridItem(.fixed(36))], spacing: 8) {
                ForEach(["Swift", "Linux", "Agents", "Grids", "Shapes", "Images"], id: \.self) {
                    Text($0)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(height: 80)
        }
        .padding(20)
    }
}

/// The README's content screens.
@MainActor
enum ContentGallery {
    enum Screen: String, CaseIterable {
        case shapes = "content-shapes"
        case images = "content-images"
        case grids = "content-grids"
        case imagesDark = "content-images-dark"
    }

    /// A temporary bundle with the gallery's asset catalog: a landscape at
    /// 2×, with a dark version, a star drawn as a template, and a speech
    /// bubble with rounded corners for cap insets.
    static let bundle: Bundle = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "parhelion-content-gallery-\(ProcessInfo.processInfo.processIdentifier)")
        let catalog = root.appendingPathComponent("Gallery.bundle/Assets.xcassets")
        func write(_ path: String, _ data: Data) {
            let url = catalog.appendingPathComponent(path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        func json(_ path: String, _ text: String) { write(path, Data(text.utf8)) }
        json("Contents.json", #"{"info": {"author": "xcode", "version": 1}}"#)
        write("Landscape.imageset/landscape@2x.png", Data(landscape(dark: false).pngData()))
        write("Landscape.imageset/landscape-dark@2x.png", Data(landscape(dark: true).pngData()))
        json(
            "Landscape.imageset/Contents.json",
            """
            {"images": [
              {"filename": "landscape@2x.png", "idiom": "universal", "scale": "2x"},
              {"filename": "landscape-dark@2x.png", "idiom": "universal", "scale": "2x",
               "appearances": [{"appearance": "luminosity", "value": "dark"}]}
            ]}
            """)
        write("StarTemplate.imageset/star@2x.png", Data(star().pngData()))
        json(
            "StarTemplate.imageset/Contents.json",
            #"{"images": [{"filename": "star@2x.png", "idiom": "universal", "scale": "2x"}]}"#)
        write("Bubble.imageset/bubble@2x.png", Data(bubble().pngData()))
        json(
            "Bubble.imageset/Contents.json",
            #"{"images": [{"filename": "bubble@2x.png", "idiom": "universal", "scale": "2x"}]}"#)
        return Bundle(path: root.appendingPathComponent("Gallery.bundle").path) ?? .main
    }()

    /// A photo for `AsyncImage` to load: the landscape, as a file.
    static let photo: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "parhelion-content-gallery-\(ProcessInfo.processInfo.processIdentifier).png")
        try? Data(landscape(dark: false).pngData()).write(to: url)
        return url
    }()

    /// A 160 × 100 point landscape at 2×: sky, sun, and two hills.
    private static func landscape(dark: Bool) -> Canvas {
        var canvas = Canvas(width: 160, height: 100, scale: 2)
        let sky =
            dark
            ? [RGBA(red: 10, green: 20, blue: 60), RGBA(red: 60, green: 40, blue: 110)]
            : [RGBA(red: 90, green: 170, blue: 255), RGBA(red: 255, green: 200, blue: 150)]
        canvas.fill(
            CGRect(x: 0, y: 0, width: 160, height: 100),
            gradient: Canvas.LinearGradient(
                colors: sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 100)))
        canvas.fill(
            Path(ellipseIn: CGRect(x: 104, y: 18, width: 26, height: 26)),
            color: dark
                ? RGBA(red: 240, green: 240, blue: 220) : RGBA(red: 255, green: 230, blue: 90))
        var back = Path()
        back.move(to: CGPoint(x: 0, y: 72))
        back.addQuadCurve(to: CGPoint(x: 100, y: 64), control: CGPoint(x: 50, y: 40))
        back.addQuadCurve(to: CGPoint(x: 160, y: 70), control: CGPoint(x: 130, y: 52))
        back.addLine(to: CGPoint(x: 160, y: 100))
        back.addLine(to: CGPoint(x: 0, y: 100))
        back.closeSubpath()
        canvas.fill(
            back,
            color: dark ? RGBA(red: 30, green: 60, blue: 50) : RGBA(red: 70, green: 150, blue: 90))
        var front = Path()
        front.move(to: CGPoint(x: 0, y: 90))
        front.addQuadCurve(to: CGPoint(x: 160, y: 84), control: CGPoint(x: 90, y: 62))
        front.addLine(to: CGPoint(x: 160, y: 100))
        front.addLine(to: CGPoint(x: 0, y: 100))
        front.closeSubpath()
        canvas.fill(
            front,
            color: dark ? RGBA(red: 20, green: 40, blue: 35) : RGBA(red: 40, green: 110, blue: 60))
        return canvas
    }

    /// A 28-point five-pointed star, black on transparent, at 2×.
    private static func star() -> Canvas {
        var canvas = Canvas(width: 28, height: 28, scale: 2, background: .clear)
        var path = Path()
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index % 2 == 0 ? 13.0 : 5.5
            let point = CGPoint(x: 14 + radius * cos(angle), y: 14.5 + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        canvas.fill(path, color: .black)
        return canvas
    }

    /// A 40-point speech bubble with 14-point corners, at 2×.
    private static func bubble() -> Canvas {
        var canvas = Canvas(width: 40, height: 40, scale: 2, background: .clear)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 14, style: .continuous,
            color: RGBA(red: 52, green: 199, blue: 89))
        canvas.fill(
            CGRect(x: 3, y: 3, width: 34, height: 34), cornerRadius: 11, style: .continuous,
            color: RGBA(red: 230, green: 250, blue: 235))
        return canvas
    }

    static func host(showing screen: Screen) async -> ViewHost {
        let host: ViewHost
        switch screen {
        case .shapes:
            host = ViewHost(ScrollView { ShapesScreen() })
        case .images, .imagesDark:
            host = ViewHost(ScrollView { ImagesScreen(bundle: bundle, photo: photo) })
            if screen == .imagesDark { host.colorScheme = .dark }
        case .grids:
            host = ViewHost(ScrollView { GridsScreen() })
        }
        await host.waitForTasks()
        return host
    }

    /// A screen as the README shows it: at 2× with the status bar and the
    /// home indicator, as `--png` draws.
    static func readmeImage(_ screen: Screen) async -> Data {
        await host(showing: screen).render(scale: 2, chrome: .systemBars).pngData()
    }

    static func readmeImageURL(_ screen: Screen, in directory: URL? = nil) -> URL {
        (directory ?? TasksScreens.repository.appendingPathComponent("docs/images"))
            .appendingPathComponent("\(screen.rawValue).png")
    }
}

@MainActor
@Suite("Content gallery")
struct ContentGalleryTests {
    @Test("The gallery's screens resolve their content")
    func screens() async {
        let images = await ContentGallery.host(showing: .images)
        let kinds = Set(images.root.allNodes.map(\.kind))
        #expect(kinds.isSuperset(of: ["Image", "AsyncImage", "Overlay", "Rectangle"]))
        let phases = images.root.allNodes.filter { $0.kind == "AsyncImage" }
            .map { $0.attributes["phase"] }
        #expect(phases == ["success", "failure"])
        let landscape = images.root.allNodes.first { $0.attributes["name"] == "Landscape" }
        #expect(landscape?.attributes["size"] == "160 × 100")
        let dark = await ContentGallery.host(showing: .imagesDark)
        #expect(
            dark.root.allNodes.first { $0.attributes["name"] == "Landscape" }?
                .attributes["appearance"] == "dark")
        let grids = await ContentGallery.host(showing: .grids)
        #expect(grids.root.allNodes.filter { $0.kind == "GridRow" }.count == 4)
    }

    /// Rendering is deterministic, so the README's images must match a fresh
    /// render. After an intended rendering change, regenerate them with
    /// `PARHELION_README_IMAGES=docs/images swift test --filter writeContentReadmeImages`.
    @Test(
        "The README's content images match a fresh render",
        arguments: ContentGallery.Screen.allCases)
    func readmeImages(_ screen: ContentGallery.Screen) async throws {
        let committed = try Data(contentsOf: ContentGallery.readmeImageURL(screen))
        #expect(await ContentGallery.readmeImage(screen) == committed)
    }

    @Test(
        "Write the README's content images",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] != nil)
    )
    func writeContentReadmeImages() async throws {
        let path = ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] ?? ""
        let directory = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for screen in ContentGallery.Screen.allCases {
            try await ContentGallery.readmeImage(screen).write(
                to: ContentGallery.readmeImageURL(screen, in: directory))
        }
    }
}
