#if canImport(Foundation)
import Foundation
#endif

/// A view that displays one or more lines of read-only text.
public struct Text: View, Equatable, Sendable {
    public typealias Body = Never

    let content: String
    /// The font set with ``font(_:)``, which overrides the environment's.
    var font: Font?
    /// The weight set with ``fontWeight(_:)`` or ``bold(_:)``.
    var weight: Font.Weight?

    public init(_ content: some StringProtocol) {
        self.content = String(content)
    }

    public init(verbatim content: String) {
        self.content = content
    }

    public var body: Never {
        fatalError("Text is a primitive view and has no body.")
    }
}

extension Text: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes = ["text": content]
        // Text in the body font, the default, records no font, so outlines
        // show a font only where one was chosen, and a size only where
        // Dynamic Type changed it.
        resolvedFont(in: evaluator.environment).record(in: &attributes)
        return [ViewNode(id: path.appending("Text").id, kind: "Text", attributes: attributes)]
    }
}

/// A view that displays an image: a symbol, an image from an asset
/// catalog, or an image that `AsyncImage` loaded.
public struct Image: View, Equatable, Sendable {
    public typealias Body = Never

    /// The relative size of a symbol image.
    public enum Scale: String, Sendable {
        case small, medium, large
    }

    /// How a resizable image fills a frame of another size.
    public enum ResizingMode: Sendable, Hashable {
        /// Repeats the image at its size.
        case tile
        /// Stretches the image to fill the frame.
        case stretch
    }

    /// Whether an image draws its own colors or only its shape in the
    /// foreground color.
    public enum TemplateRenderingMode: Sendable, Hashable {
        /// Draws every pixel that is not transparent in the foreground
        /// color.
        case template
        /// Draws the image's own colors.
        case original
    }

    enum Source: Equatable, Sendable {
        /// An image set in an asset catalog, in the bundle at a path, or
        /// found by name when the path is `nil`.
        case named(String, bundlePath: String?)
        case systemName(String)
        /// An image that `AsyncImage` loaded, by its URL, with its size in
        /// points.
        case loaded(url: String, size: CGSize)
    }

    let source: Source
    var isResizable = false
    var capInsets = EdgeInsets()
    var resizingMode = ResizingMode.stretch
    var renderingMode: TemplateRenderingMode?

    /// An image from an asset catalog, in a bundle, or found by name.
    ///
    /// Parhelion reads PNG images; a JPEG, PDF, or HEIF file draws as a
    /// missing image. Without a bundle, or with the main one, it looks in
    /// the main bundle and every bundle beside it, because on Linux an
    /// app's catalog is in its target's bundle, such as
    /// `MyApp_MyApp.bundle`, not in the main bundle.
    public init(_ name: String, bundle: Bundle? = nil) {
        let path = bundle.flatMap { $0 == Bundle.main ? nil : $0.bundleURL.path }
        source = .named(name, bundlePath: path)
    }

    public init(systemName: String) {
        source = .systemName(systemName)
    }

    init(loaded url: String, size: CGSize) {
        source = .loaded(url: url, size: size)
    }

    /// The image resizable to fill the frame it is offered. The parts
    /// inside `capInsets`, in points, keep their size at the edges and
    /// corners, and the rest stretches or tiles.
    public func resizable(
        capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch
    ) -> Image {
        var image = self
        image.isResizable = true
        image.capInsets = capInsets
        image.resizingMode = resizingMode
        return image
    }

    /// The image drawn as a template, as itself, or, for `nil`, as its
    /// asset catalog says.
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var image = self
        image.renderingMode = renderingMode
        return image
    }

    public var body: Never {
        fatalError("Image is a primitive view and has no body.")
    }
}

extension Image: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String]
        switch source {
        case .named(let name, let bundlePath):
            attributes = assetAttributes(name, bundlePath: bundlePath, in: evaluator.environment)
        case .systemName(let name):
            attributes = symbolAttributes(name, in: evaluator.environment)
        case .loaded(let url, let size):
            attributes = ["url": url, "size": formatSize(size)]
            if renderingMode == .template { attributes["renderingMode"] = "template" }
        }
        if isResizable {
            attributes["resizable"] = "true"
            if capInsets != EdgeInsets() {
                attributes["capInsets"] = [
                    capInsets.top, capInsets.leading, capInsets.bottom, capInsets.trailing,
                ].map(formatPoints).joined(separator: ", ")
            }
            if resizingMode == .tile { attributes["resizingMode"] = "tile" }
        }
        return [ViewNode(id: path.appending("Image").id, kind: "Image", attributes: attributes)]
    }
}

/// A control that performs an action when tapped.
public struct Button<Label: View>: View {
    public typealias Body = Never

    let label: Label
    let role: ButtonRole?
    let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.init(role: nil, action: action, label: label)
    }

    /// Creates a button with a role, which can change how it looks and where
    /// it goes in an alert.
    public init(
        role: ButtonRole?,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    public var body: Never {
        fatalError("Button is a primitive view and has no body.")
    }
}

extension Button where Label == Text {
    public init(_ title: some StringProtocol, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }

    /// Creates a button with a text label and a role.
    public init(
        _ title: some StringProtocol,
        role: ButtonRole?,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(role: role, action: action) { Text(title) }
    }
}

extension Button: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Button")
        let environment = evaluator.environment
        var attributes = role.map { ["role": $0.name] } ?? [:]
        if environment.isEnabled {
            evaluator.registerAction(action, for: ownPath.id)
        } else {
            attributes["disabled"] = "true"
        }
        let children: [ViewNode]
        switch environment.buttonStyle {
        case .custom(let style):
            attributes["buttonStyle"] = baseTypeName(of: type(of: style))
            children = evaluator.withEnvironment({ $0.buttonStyle = .builtIn(.automatic) }) {
                evaluator.evaluate(customBody(style), at: ownPath)
            }
        case .builtIn(let style):
            if style != .automatic { attributes["buttonStyle"] = style.rawValue }
            if style.drawsShape, environment.controlSize != .regular {
                attributes["controlSize"] = environment.controlSize.rawValue
            }
            children = evaluator.withEnvironment({ labelEnvironment(&$0, style: style) }) {
                evaluator.evaluate(label, at: ownPath)
            }
        }
        return [
            ViewNode(id: ownPath.id, kind: "Button", attributes: attributes, children: children)
        ]
    }

    /// Changes the environment of the label for the button's style: glass
    /// buttons, toolbar items, and alert buttons have medium labels, and a
    /// small bordered button has smaller text. Fonts set inside the label
    /// still win.
    private func labelEnvironment(_ environment: inout EnvironmentValues, style: BuiltInButtonStyle)
    {
        // Assumed: in the iOS 27 UI Kit, labels on glass and in alerts are
        // medium, and other button labels are regular.
        if style.isGlass || environment.buttonContext != .standard {
            environment.fontWeight = environment.fontWeight ?? .medium
        }
        if style.drawsShape, environment.buttonContext == .standard {
            let metrics = LayoutDefaults.controlMetrics(
                environment.controlSize, glass: style.isGlass)
            if metrics.fontSize != LayoutDefaults.bodyFontSize, environment.font == nil {
                environment.font = .subheadline
            }
        }
    }

    private func customBody<S: ButtonStyle>(_ style: S) -> any View {
        style.makeBody(
            configuration: ButtonStyleConfiguration(
                role: role, label: ButtonStyleConfiguration.Label(content: label),
                isPressed: false))
    }
}

/// A flexible space that expands along the major axis of its stack.
public struct Spacer: View, Sendable {
    public typealias Body = Never

    let minLength: CGFloat?

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer is a primitive view and has no body.")
    }
}

extension Spacer: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if let minLength { attributes["minLength"] = formatPoints(minLength) }
        return [ViewNode(id: path.appending("Spacer").id, kind: "Spacer", attributes: attributes)]
    }
}
