import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// `AsyncImage`, from https://developer.apple.com/documentation/swiftui/asyncimage
// and its initializers' pages (research for #30, section 4.3).

/// The context of a change to state, mirroring SwiftUI's `Transaction`.
/// Parhelion keeps only its animation.
public struct Transaction: Sendable {
    /// The animation the change makes, or `nil` for none.
    public var animation: Animation?

    public init() {
        animation = nil
    }

    public init(animation: Animation?) {
        self.animation = animation
    }
}

/// Where an `AsyncImage`'s load is, mirroring SwiftUI's `AsyncImagePhase`.
public enum AsyncImagePhase: Sendable {
    /// No image has loaded: the load is under way, or there is no URL.
    case empty
    /// The image loaded.
    case success(Image)
    /// The load failed.
    case failure(any Error)

    /// The loaded image, if there is one.
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }

    /// The error the load failed with, if it failed.
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }

    /// The phase as the tree records it.
    var name: String {
        switch self {
        case .empty: "empty"
        case .success: "success"
        case .failure: "failure"
        }
    }
}

/// A view that loads an image from a URL and shows it, mirroring SwiftUI's
/// `AsyncImage`.
///
/// The load runs as a `task` of the view, so `ViewHost.waitForTasks()`
/// waits for it and `parhelion mcp` counts it in `pendingTasks`. A `file:`
/// URL is read from disk and any other with the view's `URLSession`,
/// `URLSession.shared` unless `asyncImageURLSession(_:)` sets another.
/// Parhelion decodes PNG images; other data fails to load. Assumed: as
/// with iOS 27's cache, an image already loaded from the same URL shows
/// without loading again.
///
/// The node is an `AsyncImage` with the URL, the `phase`, and the `scale`
/// when it is not 1, and the content as its children. Until the image
/// loads, and after a failure, `AsyncImage(url:scale:)` shows a gray
/// rectangle that fills the space it is offered.
public struct AsyncImage<Content: View>: View {
    let request: URLRequest?
    let scale: CGFloat
    let transaction: Transaction
    let content: @MainActor (AsyncImagePhase) -> any View

    @State private var loaded: Loaded?
    @Environment(\.asyncImageURLSession) private var session

    /// The phase a load reached, for the URL and scale it loaded.
    private struct Loaded {
        var key: LoadKey
        var phase: AsyncImagePhase
    }

    private struct LoadKey: Equatable {
        var url: String?
        var scale: CGFloat
    }

    init(
        loading request: URLRequest?, scale: CGFloat, transaction: Transaction,
        makeContent content: @escaping @MainActor (AsyncImagePhase) -> any View
    ) {
        self.request = request
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    public var body: some View {
        let key = LoadKey(url: request?.url?.absoluteString, scale: scale)
        let phase = loaded.flatMap { $0.key == key ? $0.phase : nil } ?? .empty
        AsyncImageNode(url: key.url, scale: scale, phase: phase, content: content(phase))
            .task(id: key) { await load(key) }
    }

    private func load(_ key: LoadKey) async {
        guard let request, let url = request.url else { return }
        let result = await AsyncImageLoader.load(request, url: url, session: session)
        guard !Task.isCancelled else { return }
        let phase: AsyncImagePhase
        switch result {
        case .success(let pixels):
            phase = .success(
                Image(
                    loaded: url.absoluteString,
                    size: CGSize(
                        width: CGFloat(pixels.width) / scale, height: CGFloat(pixels.height) / scale
                    )
                ))
        case .failure(let error):
            phase = .failure(error)
        }
        withAnimation(transaction.animation) { loaded = Loaded(key: key, phase: phase) }
    }
}

extension AsyncImage {
    /// Shows the image at a URL, and a gray placeholder until it loads or
    /// if the load fails. `scale` is the image's pixels per point: 2 for
    /// an image you would name with `@2x`.
    public init(url: URL?, scale: CGFloat = 1) where Content == Image {
        self.init(defaultContentFor: url.map { URLRequest(url: $0) }, scale: scale)
    }

    /// Shows the image at a URL through `content`, and `placeholder` until
    /// it loads or if the load fails.
    public init<I: View, P: View>(
        url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(
            loading: url.map { URLRequest(url: $0) }, scale: scale, transaction: Transaction(),
            makeContent: { phase in
                if let image = phase.image { return content(image) }
                return placeholder()
            })
    }

    /// Shows whatever `content` makes of each phase of loading the image at
    /// a URL, changing phases with the transaction's animation.
    public init(
        url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.init(
            loading: url.map { URLRequest(url: $0) }, scale: scale, transaction: transaction,
            makeContent: { content($0) })
    }

    /// Shows the image a request loads, and a gray placeholder until it
    /// loads or if the load fails.
    public init(request: URLRequest, scale: CGFloat = 1) where Content == Image {
        self.init(defaultContentFor: request, scale: scale)
    }

    /// Shows the image a request loads through `content`, and
    /// `placeholder` until it loads or if the load fails.
    public init<I: View, P: View>(
        request: URLRequest?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _AsyncImageConditionalContent<I, P> {
        self.init(
            loading: request, scale: scale, transaction: Transaction(),
            makeContent: { phase in
                if let image = phase.image { return content(image) }
                return placeholder()
            })
    }

    /// Shows whatever `content` makes of each phase of loading the image a
    /// request loads, changing phases with the transaction's animation.
    public init(
        request: URLRequest?, scale: CGFloat = 1, transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.init(
            loading: request, scale: scale, transaction: transaction, makeContent: { content($0) })
    }

    /// Shows the loaded image, or the gray placeholder.
    private init(defaultContentFor request: URLRequest?, scale: CGFloat) where Content == Image {
        self.init(
            loading: request, scale: scale, transaction: Transaction(),
            makeContent: { phase in
                if let image = phase.image { return image }
                return Rectangle().fill(AsyncImagePlaceholderStyle())
            })
    }
}

/// The content type of `AsyncImage`'s request initializer with content and
/// a placeholder, mirroring SwiftUI's. Parhelion never makes one.
public struct _AsyncImageConditionalContent<TrueContent: View, FalseContent: View>: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("_AsyncImageConditionalContent is a primitive view and has no body.")
    }
}

/// The node of an `AsyncImage`, with its content as children.
struct AsyncImageNode: View {
    typealias Body = Never

    let url: String?
    let scale: CGFloat
    let phase: AsyncImagePhase
    let content: any View

    var body: Never {
        fatalError("AsyncImageNode is a primitive view and has no body.")
    }
}

extension AsyncImageNode: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        // `AsyncImage` is not primitive, so the path already ends with its
        // name.
        var attributes = ["phase": phase.name]
        if let url { attributes["url"] = url }
        if scale != 1 { attributes["scale"] = formatPoints(scale) }
        return [
            ViewNode(
                id: path.id, kind: "AsyncImage", attributes: attributes,
                children: evaluator.evaluate(content, at: path))
        ]
    }
}

/// The fill of `AsyncImage`'s default placeholder.
///
/// Assumed: iOS's `secondarySystemFill`, because Apple's documentation
/// shows "a grey box" in both appearances and the system fills are the
/// kit's translucent grays: 120,120,128 at 16% in light, swatch
/// `Fills/Light/2 Secondary`, and at 32% in dark, `Fills/Dark/2 Secondary`
/// (research for #30, section 4.3).
struct AsyncImagePlaceholderStyle: ShapeStyle {
    var styleName: String { "secondarySystemFill" }
}

/// Loads `AsyncImage`'s images off the main actor.
enum AsyncImageLoader {
    /// The size in pixels of the image at a URL, after keeping its pixels
    /// in the image library by the URL, or why it could not load.
    static func load(
        _ request: URLRequest, url: URL, session: URLSession
    ) async -> Result<(width: Int, height: Int), any Error> {
        let key = url.absoluteString
        if let levels = ImageLibrary.shared.loaded(key) {
            return .success((levels[0].width, levels[0].height))
        }
        do {
            let data: Data
            if url.isFileURL {
                data = try await Task.detached { try Data(contentsOf: url) }.value
            } else {
                let (body, response) = try await session.data(for: request)
                if let response = response as? HTTPURLResponse,
                    !(200..<300).contains(response.statusCode)
                {
                    throw URLError(.badServerResponse)
                }
                data = body
            }
            let bitmap = try await Task.detached { () throws -> Bitmap in
                do {
                    return try Bitmap(pngData: [UInt8](data))
                } catch {
                    throw URLError(.cannotDecodeContentData)
                }
            }.value
            ImageLibrary.shared.store(bitmap, for: key)
            return .success((bitmap.width, bitmap.height))
        } catch {
            return .failure(error)
        }
    }
}

struct AsyncImageURLSessionKey: EnvironmentKey {
    static var defaultValue: URLSession { .shared }
}

extension EnvironmentValues {
    /// The session `AsyncImage` loads with.
    var asyncImageURLSession: URLSession {
        get { self[AsyncImageURLSessionKey.self] }
        set { self[AsyncImageURLSessionKey.self] = newValue }
    }
}

extension View {
    /// Sets the URL session that the `AsyncImage` views inside load with.
    public func asyncImageURLSession(_ urlSession: URLSession) -> some View {
        environment(\.asyncImageURLSession, urlSession)
    }
}
