#if canImport(Foundation)
import Foundation
#endif

// MARK: - Scroll edge effect

/// How a scroll view blends its content into the bars it scrolls under,
/// mirroring SwiftUI's `ScrollEdgeEffectStyle`.
///
/// A soft effect blurs the content under the bar and fades the blur out
/// toward the content. A hard effect covers it with a nearly opaque
/// boundary and a dividing line. Parhelion draws the effect at the top of a
/// scroll view under a navigation bar, and at the bottom under a tab bar,
/// only while content lies under the bar.
public struct ScrollEdgeEffectStyle: Equatable, Sendable {
    enum Kind: String, Sendable {
        case automatic, soft, hard
    }

    let kind: Kind

    /// The style the system chooses. Assumed: it is the soft style on
    /// iPhone, as the iOS 27 UI Kit draws it under a navigation bar.
    public static var automatic: ScrollEdgeEffectStyle { .init(kind: .automatic) }
    /// A subtle, blurred boundary.
    public static var soft: ScrollEdgeEffectStyle { .init(kind: .soft) }
    /// A nearly opaque boundary with a dividing line.
    public static var hard: ScrollEdgeEffectStyle { .init(kind: .hard) }
}

/// The scroll edge effect settings that scroll views read from the
/// environment, for each edge a scroll view scrolls toward.
struct ScrollEdgeEffectSettings: Equatable {
    var styles: [Edge: ScrollEdgeEffectStyle] = [:]
    var hidden: [Edge: Bool] = [:]

    /// What a scroll view records for an edge: `hidden`, or the name of a
    /// style other than `automatic`; `nil` for the default.
    func recorded(_ edge: Edge) -> String? {
        if hidden[edge] == true { return "hidden" }
        guard let style = styles[edge], style != .automatic else { return nil }
        return style.kind.rawValue
    }
}

struct ScrollEdgeEffectKey: EnvironmentKey {
    static var defaultValue: ScrollEdgeEffectSettings { ScrollEdgeEffectSettings() }
}

extension Edge.Set {
    var edges: [Edge] { Edge.allCases.filter { contains(Edge.Set($0)) } }
}

extension View {
    /// Sets the style of the scroll edge effect of the scroll views in this
    /// view, on the given edges. A `nil` style restores the automatic one.
    public func scrollEdgeEffectStyle(
        _ style: ScrollEdgeEffectStyle?, for edges: Edge.Set
    ) -> some View {
        EnvironmentWriter(content: self) { values in
            var settings = values[ScrollEdgeEffectKey.self]
            for edge in edges.edges { settings.styles[edge] = style }
            values[ScrollEdgeEffectKey.self] = settings
        }
    }

    /// Hides, or shows again, the scroll edge effect of the scroll views in
    /// this view, on the given edges.
    public func scrollEdgeEffectHidden(
        _ hidden: Bool = true, for edges: Edge.Set = .all
    ) -> some View {
        EnvironmentWriter(content: self) { values in
            var settings = values[ScrollEdgeEffectKey.self]
            for edge in edges.edges { settings.hidden[edge] = hidden }
            values[ScrollEdgeEffectKey.self] = settings
        }
    }
}

// MARK: - Content margins

/// Which part of a scroll view a content margin applies to, mirroring
/// SwiftUI's `ContentMarginPlacement`.
public struct ContentMarginPlacement: Equatable, Sendable {
    enum Kind: Sendable {
        case automatic, scrollContent, scrollIndicators
    }

    let kind: Kind

    /// The margins apply to the scroll content, and to its indicators.
    public static var automatic: ContentMarginPlacement { .init(kind: .automatic) }
    /// The margins apply to the scroll content only.
    public static var scrollContent: ContentMarginPlacement { .init(kind: .scrollContent) }
    /// The margins apply to the scroll indicators only. Parhelion draws no
    /// indicators, so these have no effect.
    public static var scrollIndicators: ContentMarginPlacement { .init(kind: .scrollIndicators) }
}

/// The margins around the content of the scroll views below a view, for
/// each edge that a modifier set.
struct ContentMargins: Equatable {
    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?

    /// The margins of an inner modifier replace the outer ones on the edges
    /// it sets, as in SwiftUI.
    func overridden(by inner: ContentMargins) -> ContentMargins {
        ContentMargins(
            top: inner.top ?? top, leading: inner.leading ?? leading,
            bottom: inner.bottom ?? bottom, trailing: inner.trailing ?? trailing)
    }

    var insets: EdgeInsets {
        EdgeInsets(
            top: top ?? 0, leading: leading ?? 0, bottom: bottom ?? 0, trailing: trailing ?? 0)
    }

    var isEmpty: Bool { top == nil && leading == nil && bottom == nil && trailing == nil }

    /// The margins as a scroll view records them: top, leading, bottom, and
    /// trailing, like `padding` in an outline.
    var recorded: String? {
        guard !isEmpty else { return nil }
        let insets = insets
        return [insets.top, insets.leading, insets.bottom, insets.trailing]
            .map(formatPoints).joined(separator: ", ")
    }

    init(
        top: CGFloat? = nil, leading: CGFloat? = nil, bottom: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    init(_ edges: Edge.Set, _ length: CGFloat) {
        self.init(
            top: edges.contains(.top) ? length : nil,
            leading: edges.contains(.leading) ? length : nil,
            bottom: edges.contains(.bottom) ? length : nil,
            trailing: edges.contains(.trailing) ? length : nil)
    }

    /// Parses what ``recorded`` wrote.
    init?(recorded: String?) {
        guard let recorded else { return nil }
        let values = recorded.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard values.count == 4 else { return nil }
        self.init(
            top: CGFloat(values[0]), leading: CGFloat(values[1]), bottom: CGFloat(values[2]),
            trailing: CGFloat(values[3]))
    }
}

struct ContentMarginsKey: EnvironmentKey {
    static var defaultValue: ContentMargins { ContentMargins() }
}

extension View {
    /// Adds margins around the content of the scroll views in this view, on
    /// the given edges. A `nil` length uses the platform default. The
    /// margins scroll with the content, inside the safe area.
    public func contentMargins(
        _ edges: Edge.Set = .all, _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        contentMargins(ContentMargins(edges, length ?? LayoutDefaults.padding), for: placement)
    }

    /// Adds margins around the content of the scroll views in this view.
    public func contentMargins(
        _ edges: Edge.Set = .all, _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        contentMargins(
            ContentMargins(
                top: edges.contains(.top) ? insets.top : nil,
                leading: edges.contains(.leading) ? insets.leading : nil,
                bottom: edges.contains(.bottom) ? insets.bottom : nil,
                trailing: edges.contains(.trailing) ? insets.trailing : nil),
            for: placement)
    }

    private func contentMargins(
        _ margins: ContentMargins, for placement: ContentMarginPlacement
    )
        -> some View
    {
        EnvironmentWriter(content: self) { values in
            // Margins for the indicators do not change the content.
            guard placement.kind != .scrollIndicators else { return }
            values[ContentMarginsKey.self] = values[ContentMarginsKey.self].overridden(by: margins)
        }
    }
}

extension EnvironmentValues {
    /// The attributes that a scroll view records from the environment.
    var scrollAttributes: [String: String] {
        var attributes: [String: String] = [:]
        let settings = self[ScrollEdgeEffectKey.self]
        if let top = settings.recorded(.top) { attributes["scrollEdgeEffectTop"] = top }
        if let bottom = settings.recorded(.bottom) { attributes["scrollEdgeEffectBottom"] = bottom }
        if let margins = self[ContentMarginsKey.self].recorded {
            attributes["contentMargins"] = margins
        }
        if let behavior = self[ScrollTargetBehaviorKey.self] {
            attributes["scrollTargetBehavior"] = behavior
        }
        return attributes
    }
}

// MARK: - Safe area padding and ignoring the safe area

/// A set of safe-area regions, mirroring SwiftUI's `SafeAreaRegions`.
public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The area the device's edges, bars, and home indicator cover.
    public static let container = SafeAreaRegions(rawValue: 1 << 0)
    /// The area the keyboard covers. Parhelion has no keyboard, so this has
    /// no effect.
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)
    /// Every region.
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

/// A view that adds to the safe area of the view it modifies.
struct SafeAreaPaddingModifier<Content: View>: View {
    typealias Body = Never

    let content: Content
    let margins: ContentMargins

    var body: Never {
        fatalError("SafeAreaPaddingModifier is a primitive view and has no body.")
    }
}

extension SafeAreaPaddingModifier: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path).map { node in
            var node = node
            if node.isScrollContainer {
                // A scroll view insets its content by the padding, so that
                // the content still scrolls under the bars.
                let merged = ContentMargins(recorded: node.attributes["contentMargins"]) ?? .init()
                let own = margins.insets
                let total = ContentMargins(
                    top: (merged.top ?? 0) + own.top, leading: (merged.leading ?? 0) + own.leading,
                    bottom: (merged.bottom ?? 0) + own.bottom,
                    trailing: (merged.trailing ?? 0) + own.trailing)
                node.attributes["contentMargins"] = total.recorded
            } else {
                node.modifiers.append(.padding(margins.insets))
            }
            return node
        }
    }
}

/// A view that lets the view it modifies reach the edges of the screen.
struct IgnoresSafeAreaModifier<Content: View>: View {
    typealias Body = Never

    let content: Content
    let edges: Edge.Set

    var body: Never {
        fatalError("IgnoresSafeAreaModifier is a primitive view and has no body.")
    }
}

extension IgnoresSafeAreaModifier: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard !edges.isEmpty else { return nodes }
        return nodes.map { node in
            var node = node
            let names = edges.edges.map { "\($0)" }
            node.attributes["ignoresSafeArea"] =
                edges == .all ? "all" : names.joined(separator: ",")
            return node
        }
    }
}

extension View {
    /// Adds to the safe area of this view by padding its edges. A `nil`
    /// length uses the platform default. A scroll view insets its content
    /// by the padding, so the content still scrolls under the bars.
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        SafeAreaPaddingModifier(
            content: self, margins: ContentMargins(edges, length ?? LayoutDefaults.padding))
    }

    /// Adds to the safe area of this view by padding each edge by a
    /// different length.
    public func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        SafeAreaPaddingModifier(
            content: self,
            margins: ContentMargins(
                top: insets.top, leading: insets.leading, bottom: insets.bottom,
                trailing: insets.trailing))
    }

    /// Lets this view extend into the safe area on the given edges, where
    /// it touches them. Without `.container`, it stays inside.
    public func ignoresSafeArea(
        _ regions: SafeAreaRegions = .all, edges: Edge.Set = .all
    ) -> some View {
        IgnoresSafeAreaModifier(
            content: self, edges: regions.contains(.container) ? edges : [])
    }
}
