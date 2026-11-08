#if canImport(Foundation)
import Foundation
#endif

// `Link` and the `openURL` action. Linux opens nothing: the system action
// records the URL on the host, where a test or an agent reads it. See
// ``ViewHost/openedURLs``.

/// A control that opens a URL, mirroring SwiftUI's `Link`.
///
/// A link is a `Button` node whose `link` attribute is the URL, so it looks
/// and lays out like a button: its label is in the tint color, and button
/// styles apply to it. Tapping it calls the ``EnvironmentValues/openURL``
/// action with the URL.
public struct Link<Label: View>: View {
    public typealias Body = Never

    let destination: URL
    let label: Label

    /// Creates a link to `destination` with a custom label.
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: Never {
        fatalError("Link is a primitive view and has no body.")
    }
}

extension Link where Label == Text {
    /// Creates a link to `destination` whose label is a title.
    public init(_ title: some StringProtocol, destination: URL) {
        self.init(destination: destination) { Text(title) }
    }
}

extension Link: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let openURL = evaluator.environment.openURL
        let destination = destination
        let button = Button(action: { openURL(destination) }) { label }
        return evaluator.evaluate(button, at: path.appending("Link")).map { node in
            var node = node
            node.attributes["link"] = destination.absoluteString
            return node
        }
    }
}

// MARK: - Opening URLs

/// An action that opens a URL, mirroring SwiftUI's `OpenURLAction`.
///
/// Read it from the environment with `@Environment(\.openURL)`, and call it
/// with a URL. The system action records the URL on the ``ViewHost``: see
/// ``ViewHost/openedURLs``. Replace it with
/// `.environment(\.openURL, OpenURLAction { url in ... })`; a handler that
/// returns ``Result/systemAction`` passes the URL on to the system action.
public struct OpenURLAction {
    /// What a handler did with a URL, mirroring SwiftUI's
    /// `OpenURLAction.Result`.
    public struct Result: Sendable {
        let url: URL?
        let opensURL: Bool
        let isHandled: Bool

        /// The handler opened the URL.
        public static let handled = Result(url: nil, opensURL: false, isHandled: true)
        /// The handler ignored the URL.
        public static let discarded = Result(url: nil, opensURL: false, isHandled: false)
        /// The system opens the URL.
        public static let systemAction = Result(url: nil, opensURL: true, isHandled: true)

        /// The system opens another URL in place of the one given.
        public static func systemAction(_ url: URL) -> Result {
            Result(url: url, opensURL: true, isHandled: true)
        }
    }

    let handler: (@MainActor (URL) -> Result)?
    /// The system action: on the host, records the URL.
    var system: (@MainActor (URL) -> Void)?

    /// Creates an action that hands each URL to `handler`.
    public init(handler: @escaping @MainActor (URL) -> Result) {
        self.handler = handler
        self.system = nil
    }

    init(system: (@MainActor (URL) -> Void)?) {
        self.handler = nil
        self.system = system
    }

    /// Opens `url`.
    @MainActor
    public func callAsFunction(_ url: URL) {
        _ = open(url)
    }

    /// Opens `url`, then calls `completion` with whether it was opened.
    @MainActor
    public func callAsFunction(_ url: URL, completion: @escaping (_ accepted: Bool) -> Void) {
        completion(open(url))
    }

    @MainActor
    private func open(_ url: URL) -> Bool {
        let result = handler?(url) ?? .systemAction
        guard result.opensURL else { return result.isHandled }
        system?(result.url ?? url)
        return system != nil
    }
}

struct OpenURLKey: EnvironmentKey {
    static var defaultValue: OpenURLAction { OpenURLAction(system: nil) }
}

extension EnvironmentValues {
    /// The action that opens a URL. A ``Link`` calls it when tapped.
    ///
    /// Setting a new action keeps the system action of the one it replaces,
    /// so that a handler can return ``OpenURLAction/Result/systemAction``.
    public var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set {
            var action = newValue
            if action.system == nil { action.system = self[OpenURLKey.self].system }
            self[OpenURLKey.self] = action
        }
    }
}

/// The URLs that the system `openURL` action was given.
struct OpenedURLLog {
    /// How many URLs the log keeps; older ones are dropped.
    static let capacity = 50
    /// The name of the root node's attribute that holds the newest URL.
    static let attribute = "openedURL"

    var urls: [URL] = []

    mutating func record(_ url: URL) {
        urls.append(url)
        if urls.count > Self.capacity { urls.removeFirst(urls.count - Self.capacity) }
    }
}

extension ViewHost {
    /// The URLs that links and the `openURL` action opened, oldest first, up
    /// to the last 50. Linux opens nothing, so this is where a test or an
    /// agent checks a link. The root node's `openedURL` attribute is the
    /// newest, and `PARHELION_DEBUG=1` logs each one.
    public var openedURLs: [URL] { openedURLLog.urls }

    /// Records a URL that the system action opened, and marks the tree for
    /// an update that shows it.
    func recordOpenedURL(_ url: URL) {
        openedURLLog.record(url)
        if ProcessInfo.processInfo.environment["PARHELION_DEBUG"] != nil {
            FileHandle.standardError.write(
                Data("parhelion app: open URL \(url.absoluteString)\n".utf8))
        }
        setNeedsUpdate()
    }

    /// The system `openURL` action of this host.
    var systemOpenURLAction: OpenURLAction {
        OpenURLAction(system: { [weak self] url in self?.recordOpenedURL(url) })
    }
}
