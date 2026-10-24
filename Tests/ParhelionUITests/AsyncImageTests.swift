import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

/// Writes a PNG image of one color to a new file and returns its URL. Each
/// file has its own name, so no test sees another's image in the library.
private func pngFile(width: Int, height: Int, _ color: RGBA) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("parhelion-async-\(UUID().uuidString).png")
    let canvas = Canvas(width: Double(width), height: Double(height), scale: 1, background: color)
    try Data(canvas.pngData()).write(to: url)
    return url
}

private let missingFile = URL(fileURLWithPath: "/nonexistent/parhelion-missing.png")

@MainActor
@Suite("AsyncImage")
struct AsyncImageTests {
    @Test("Until it loads, an AsyncImage shows a gray placeholder; then the image")
    func loads() async throws {
        let url = try pngFile(width: 40, height: 20, RGBA(red: 0, green: 0, blue: 255))
        let host = ViewHost(AsyncImage(url: url), device: square)
        #expect(host.pendingTaskCount == 1)
        #expect(
            host.root.outline() == """
                Root
                └─ AsyncImage phase=empty url=\(url.absoluteString)
                   └─ Rectangle fill=secondarySystemFill
                """)
        // The placeholder fills the space it is offered.
        #expect(host.root.children[0].frame?.size == CGSize(width: 200, height: 200))
        let gray = host.render(scale: 1).color(at: CGPoint(x: 100, y: 100))
        #expect(gray.red == gray.green && gray.red < 255 && gray.blue > gray.red)

        await host.waitForTasks()
        #expect(host.pendingTaskCount == 0)
        #expect(
            host.root.outline() == """
                Root
                └─ AsyncImage phase=success url=\(url.absoluteString)
                   └─ Image size=40 × 20 url=\(url.absoluteString)
                """)
        #expect(host.root.children[0].frame?.size == CGSize(width: 40, height: 20))
        #expect(
            components(host.render(scale: 2).color(at: CGPoint(x: 100, y: 100)))
                == [0, 0, 255, 255])
    }

    @Test("The placeholder is the dark secondary fill in the dark appearance")
    func darkPlaceholder() {
        let host = ViewHost(AsyncImage(url: missingFile), device: square)
        let light = host.render(scale: 1).color(at: CGPoint(x: 100, y: 100))
        host.colorScheme = .dark
        let dark = host.render(scale: 1).color(at: CGPoint(x: 100, y: 100))
        // 120,120,128 at 16% over white, and at 32% over black.
        #expect(components(light) == [233, 233, 235, 255])
        #expect(components(dark) == [39, 39, 41, 255])
    }

    @Test("A failed load keeps the placeholder and records the failure")
    func failure() async throws {
        let host = ViewHost(AsyncImage(url: missingFile), device: square)
        await host.waitForTasks()
        let node = host.root.children[0]
        #expect(node.attributes["phase"] == "failure")
        #expect(node.children.map(\.kind) == ["Rectangle"])
    }

    @Test("Data that is not a PNG image fails to decode")
    func undecodable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-async-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]).write(to: url)
        var error: (any Error)?
        let host = ViewHost(
            AsyncImage(url: url) { phase in
                if let failure = phase.error {
                    Text("Failed").onAppear { error = failure }
                }
            },
            device: square
        )
        await host.waitForTasks()
        #expect(host.nodes(withText: "Failed").count == 1)
        #expect((error as? URLError)?.code == .cannotDecodeContentData)
    }

    @Test("Content and placeholder closures show the image or the placeholder")
    func contentAndPlaceholder() async throws {
        let url = try pngFile(width: 10, height: 10, .black)
        let host = ViewHost(
            AsyncImage(url: url, scale: 2) { image in
                image.resizable()
            } placeholder: {
                Text("Loading")
            }
            .frame(width: 50, height: 50),
            device: square
        )
        #expect(host.nodes(withText: "Loading").count == 1)
        await host.waitForTasks()
        let node = host.root.children[0]
        #expect(node.attributes["scale"] == "2")
        let image = try #require(node.children.first)
        #expect(image.attributes["size"] == "5 × 5")
        #expect(image.attributes["resizable"] == "true")
        #expect(image.frame?.size == CGSize(width: 50, height: 50))
    }

    @Test("Phase content sees each phase, and a request loads like a URL")
    func phases() async throws {
        let url = try pngFile(width: 8, height: 8, .white)
        let host = ViewHost(
            VStack {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .empty: Text("Empty")
                    case .success(let image): image
                    case .failure: Text("Failed")
                    }
                }
                AsyncImage(request: URLRequest(url: url))
                AsyncImage(url: nil) { phase in
                    Text(phase.image == nil ? "No URL" : "Image")
                }
            },
            device: square
        )
        #expect(host.nodes(withText: "Empty").count == 1)
        await host.waitForTasks()
        let images = host.root.children[0].children
        #expect(images[0].children.first?.kind == "Image")
        #expect(images[1].children.first?.kind == "Image")
        #expect(images[2].attributes["url"] == nil)
        #expect(host.nodes(withText: "No URL").count == 1)
    }

    @Test("A resizable image scales to fit or fill, keeping its ratio")
    func aspectRatios() throws {
        let url = try pngFile(width: 100, height: 50, .black)
        ImageLibrary.shared.store(
            try Bitmap(pngData: [UInt8](Data(contentsOf: url))), for: url.absoluteString)
        let image = Image(loaded: url.absoluteString, size: CGSize(width: 100, height: 50))
        let host = ViewHost(
            VStack(spacing: 0) {
                image.resizable().scaledToFit().frame(width: 200, height: 60)
                image.resizable().scaledToFill().frame(width: 60, height: 60).clipped()
                image.resizable().aspectRatio(1, contentMode: .fit).frame(width: 80, height: 40)
                Color.red.aspectRatio(CGSize(width: 3, height: 1), contentMode: .fit)
                    .frame(width: 30)
            },
            device: square
        )
        let nodes = host.root.children[0].children
        #expect(nodes[0].modifiers.first?.outlineDescription == "aspectRatio(contentMode: fit)")
        #expect(nodes[2].modifiers.first?.outlineDescription == "aspectRatio(1, contentMode: fit)")
        // 200 × 60 fits a 2:1 image at 120 × 60, centered.
        #expect(nodes[0].frame?.size == CGSize(width: 120, height: 60))
        #expect(nodes[0].frame?.minX == 40)
        // 60 × 60 is covered by 120 × 60, which overflows on both sides.
        #expect(nodes[1].frame?.size == CGSize(width: 120, height: 60))
        #expect(nodes[2].frame?.size == CGSize(width: 40, height: 40))
        #expect(nodes[3].frame?.size == CGSize(width: 30, height: 10))
        // The clip keeps the filled image inside its 60-point frame.
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 90))) == [0, 0, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 65, y: 90))) == [255, 255, 255, 255])
    }
}
