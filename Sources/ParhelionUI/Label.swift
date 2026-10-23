#if canImport(Foundation)
import Foundation
#endif

/// A title with an icon beside it, mirroring SwiftUI's `Label`.
///
/// A label is a `Label` node whose children are its icon and its title,
/// laid out side by side, or only one of them under the ``IconOnlyLabelStyle``
/// and ``TitleOnlyLabelStyle`` styles. Its `labelStyle` attribute records a
/// style other than the default. In a toolbar, the default style shows only
/// the icon, as on iOS.
public struct Label<Title: View, Icon: View>: View {
    public typealias Body = Never

    let title: Title
    let icon: Icon

    /// Creates a label with a custom title and icon.
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public var body: Never {
        fatalError("Label is a primitive view and has no body.")
    }
}

extension Label where Title == Text, Icon == Image {
    /// Creates a label with a symbol as its icon.
    public init(_ title: some StringProtocol, systemImage name: String) {
        self.init(title: { Text(title) }, icon: { Image(systemName: name) })
    }

    /// Creates a label with an image from the app's assets as its icon,
    /// which Parhelion does not draw.
    public init(_ title: some StringProtocol, image name: String) {
        self.init(title: { Text(title) }, icon: { Image(name) })
    }
}

extension Label: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Label")
        var attributes: [String: String] = [:]
        let children: [ViewNode]
        switch evaluator.environment.labelStyle {
        case .custom(let style):
            attributes["labelStyle"] = baseTypeName(of: type(of: style))
            children = evaluator.evaluate(customBody(style), at: ownPath)
        case .builtIn(let style):
            if style != .automatic { attributes["labelStyle"] = style.rawValue }
            // Assumed: the default style shows only the icon in a toolbar,
            // and the title and the icon elsewhere.
            let resolved =
                style == .automatic
                ? (evaluator.environment.buttonContext == .toolbar ? .iconOnly : .titleAndIcon)
                : style
            var nodes: [ViewNode] = []
            if resolved != .titleOnly {
                nodes += evaluator.evaluate(icon, at: ownPath.appending("icon"))
            }
            if resolved != .iconOnly {
                nodes += evaluator.evaluate(title, at: ownPath.appending("title"))
            }
            children = nodes
        }
        return [ViewNode(id: ownPath.id, kind: "Label", attributes: attributes, children: children)]
    }

    private func customBody<S: LabelStyle>(_ style: S) -> any View {
        style.makeBody(
            configuration: LabelStyleConfiguration(
                title: LabelStyleConfiguration.Title(content: title),
                icon: LabelStyleConfiguration.Icon(content: icon)))
    }
}

// MARK: - Styles

/// A style that builds a label's appearance from its title and icon,
/// mirroring SwiftUI's `LabelStyle`.
@MainActor
@preconcurrency
public protocol LabelStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    typealias Configuration = LabelStyleConfiguration
}

/// The title and icon of a label that a ``LabelStyle`` arranges, mirroring
/// SwiftUI's `LabelStyleConfiguration`.
public struct LabelStyleConfiguration {
    /// The label's title, as a view.
    public struct Title: View {
        public typealias Body = Never

        let content: any View

        public var body: Never {
            fatalError("Title is a primitive view and has no body.")
        }
    }

    /// The label's icon, as a view.
    public struct Icon: View {
        public typealias Body = Never

        let content: any View

        public var body: Never {
            fatalError("Icon is a primitive view and has no body.")
        }
    }

    /// The label's title.
    public var title: Title
    /// The label's icon.
    public var icon: Icon
}

extension LabelStyleConfiguration.Title: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path.appending("title"))
    }
}

extension LabelStyleConfiguration.Icon: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path.appending("icon"))
    }
}

/// The label styles Parhelion lays out itself, by the names nodes record.
enum BuiltInLabelStyle: String, Sendable {
    case automatic, titleAndIcon, titleOnly, iconOnly
}

/// A label style that Parhelion lays out itself.
protocol BuiltInLabelStyleProtocol: LabelStyle {
    var builtIn: BuiltInLabelStyle { get }
}

/// The default label style: the title and the icon, or only the icon in a
/// toolbar. Mirrors SwiftUI's `DefaultLabelStyle`.
public struct DefaultLabelStyle: BuiltInLabelStyleProtocol {
    var builtIn: BuiltInLabelStyle { .automatic }
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

/// A style that shows the icon beside the title, mirroring SwiftUI's
/// `TitleAndIconLabelStyle`.
public struct TitleAndIconLabelStyle: BuiltInLabelStyleProtocol {
    var builtIn: BuiltInLabelStyle { .titleAndIcon }
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

/// A style that shows only the title, mirroring SwiftUI's
/// `TitleOnlyLabelStyle`.
public struct TitleOnlyLabelStyle: BuiltInLabelStyleProtocol {
    var builtIn: BuiltInLabelStyle { .titleOnly }
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

/// A style that shows only the icon, mirroring SwiftUI's
/// `IconOnlyLabelStyle`.
public struct IconOnlyLabelStyle: BuiltInLabelStyleProtocol {
    var builtIn: BuiltInLabelStyle { .iconOnly }
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    public static var automatic: DefaultLabelStyle { DefaultLabelStyle() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
    public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() }
}

/// The label style in the environment: a built-in style, or a custom
/// ``LabelStyle`` whose body is evaluated.
enum ResolvedLabelStyle {
    case builtIn(BuiltInLabelStyle)
    case custom(any LabelStyle)
}

struct LabelStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedLabelStyle { .builtIn(.automatic) }
}

extension EnvironmentValues {
    var labelStyle: ResolvedLabelStyle {
        get { self[LabelStyleKey.self] }
        set { self[LabelStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style of labels in this view and its content.
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        let resolved: ResolvedLabelStyle =
            (style as? any BuiltInLabelStyleProtocol).map { .builtIn($0.builtIn) }
            ?? .custom(style)
        return EnvironmentWriter(content: self) { $0.labelStyle = resolved }
    }
}
