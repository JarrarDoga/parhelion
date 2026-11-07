import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// The extension seam: how a new view kind or layout modifier plugs into
// layout, rendering, and hit testing from its own file. See
// docs/adr/0011-extension-seam.md.
//
// A primitive view registers its kind's behavior the first time it makes its
// nodes, with ``NodeExtensions/registerOnce(kind:_:)``. The engine, the
// renderer, and the host look the kind up before they run their built-in
// `switch`, so a kind that is registered needs no `case` anywhere else.

/// What a view kind does that the layout engine, the renderer, and hit
/// testing do not already know. Every part is optional: a kind that sets
/// nothing is laid out as a container that centers its children, and draws
/// nothing of its own.
struct NodeBehavior: Sendable {
    /// The size the node chooses for a proposal, without its layout
    /// modifiers. Called with the engine, so it can size and place children.
    var size: (@Sendable (LayoutEngine, ViewNode, ProposedSize, LayoutAxis?) -> CGSize)?
    /// Places the node's children in the rectangle the node was placed in.
    var place: (@Sendable (LayoutEngine, ViewNode, CGRect) -> [ViewNode])?
    /// Draws the node, before its children. Setting `foreground` or
    /// `container` on the drawing changes what the children inherit.
    var draw: (@Sendable (TreeRenderer, ViewNode, inout NodeDrawing, inout Canvas) -> Void)?
    /// Whether a point is on the node, in place of the node's frame.
    var hitTest: (@Sendable (ViewNode, CGPoint) -> Bool)?
    /// Whether the node is a presentation, like a sheet: a child of the
    /// root that is placed over the screen and receives input exclusively.
    var isPresentation = false
    /// Places a presentation. The nodes below it are what it can attach to.
    var placePresentation: (@Sendable (LayoutEngine, ViewNode, [ViewNode]) -> ViewNode)?

    init(
        size: (@Sendable (LayoutEngine, ViewNode, ProposedSize, LayoutAxis?) -> CGSize)? = nil,
        place: (@Sendable (LayoutEngine, ViewNode, CGRect) -> [ViewNode])? = nil,
        draw: (@Sendable (TreeRenderer, ViewNode, inout NodeDrawing, inout Canvas) -> Void)? = nil,
        hitTest: (@Sendable (ViewNode, CGPoint) -> Bool)? = nil,
        isPresentation: Bool = false,
        placePresentation: (@Sendable (LayoutEngine, ViewNode, [ViewNode]) -> ViewNode)? = nil
    ) {
        self.size = size
        self.place = place
        self.draw = draw
        self.hitTest = hitTest
        self.isPresentation = isPresentation
        self.placePresentation = placePresentation
    }
}

/// What a node draws with, and what its children inherit.
struct NodeDrawing {
    /// The node's frame.
    var frame: CGRect
    /// The foreground style, from the node or an ancestor. Children inherit
    /// the value left here.
    var foreground: String?
    /// The tint color's style name, or `nil` for the default tint.
    var tint: String?
    /// The opacity that multiplies every color the node draws.
    var opacity: Double
    var scheme: ColorScheme
    var palette: ColorPalette.Appearance
    /// What the node is in. Children inherit the value left here.
    var container: TreeRenderer.Container

    /// The color for a style name, with the node's opacity.
    func color(_ style: String) -> RGBA {
        var color = ColorPalette.color(named: style == "tint" ? tint ?? style : style, in: scheme)
        color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
        return color
    }
}

/// What a layout modifier does that the engine and the renderer do not
/// already know. The modifier is a ``LayoutModifier/custom(_:)`` value that
/// names it, so it keeps its place in the modifier chain and appears in the
/// tree as data.
struct ModifierBehavior: Sendable {
    /// The size of a node with this modifier, from the proposal and a
    /// function that gives the size of what the modifier wraps. Without it,
    /// the modifier does not change the size.
    var size:
        (
            @Sendable (
                _ parameters: [String: String], _ proposal: ProposedSize,
                _ inner: (ProposedSize) -> CGSize
            ) ->
                CGSize
        )?
    /// The rectangle for what the modifier wraps, from the rectangle the
    /// modifier is placed in and the same function. Without it, the
    /// rectangle is unchanged.
    var place:
        (
            @Sendable (
                _ parameters: [String: String], _ rect: CGRect, _ inner: (ProposedSize) -> CGSize
            ) ->
                CGRect
        )?
    /// How the modifier appears in an outline. Without it, the name and the
    /// sorted parameters.
    var outline: (@Sendable (_ parameters: [String: String]) -> String)?
    /// Draws behind everything inside the modifier, in its bounds.
    var drawBehind:
        (
            @Sendable (
                TreeRenderer, _ parameters: [String: String], _ drawing: NodeDrawing, inout Canvas
            ) -> Void
        )?
    /// Draws in front of everything inside the modifier, in its bounds.
    var drawInFront:
        (
            @Sendable (
                TreeRenderer, _ parameters: [String: String], _ drawing: NodeDrawing, inout Canvas
            ) -> Void
        )?
    /// Draws everything inside the modifier, through a function that draws
    /// it, as a clip or a shadow does. The function draws onto the canvas it
    /// is given, so the effect can draw it on a layer of its own.
    var drawEffect:
        (
            @Sendable (
                TreeRenderer, _ parameters: [String: String], _ drawing: NodeDrawing,
                _ drawInside: (inout Canvas) -> Void, inout Canvas
            ) -> Void
        )?

    init(
        size: (@Sendable ([String: String], ProposedSize, (ProposedSize) -> CGSize) -> CGSize)? =
            nil,
        place: (@Sendable ([String: String], CGRect, (ProposedSize) -> CGSize) -> CGRect)? = nil,
        outline: (@Sendable ([String: String]) -> String)? = nil,
        drawBehind: (
            @Sendable (TreeRenderer, [String: String], NodeDrawing, inout Canvas) -> Void
        )? = nil,
        drawInFront: (
            @Sendable (TreeRenderer, [String: String], NodeDrawing, inout Canvas) -> Void
        )? = nil,
        drawEffect: (
            @Sendable (
                TreeRenderer, [String: String], NodeDrawing, (inout Canvas) -> Void, inout Canvas
            ) -> Void
        )? = nil
    ) {
        self.size = size
        self.place = place
        self.outline = outline
        self.drawBehind = drawBehind
        self.drawInFront = drawInFront
        self.drawEffect = drawEffect
    }
}

/// A layout modifier that a file of its own defines. It is kept in the
/// node's modifier chain like the built-in ones, so its order matters.
public struct CustomModifier: Hashable, Sendable, Codable {
    /// The name its ``ModifierBehavior`` is registered under.
    public var name: String
    /// Its settings, as text, so that the tree stays plain data.
    public var parameters: [String: String]

    public init(name: String, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }

    var behavior: ModifierBehavior? { NodeExtensions.modifier(named: name) }

    var outlineDescription: String {
        if let outline = behavior?.outline { return outline(parameters) }
        guard !parameters.isEmpty else { return name }
        return name + "("
            + parameters.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            .joined(separator: ", ") + ")"
    }
}

/// The registry of view kinds and layout modifiers that plug in from their
/// own files.
final class NodeExtensions: @unchecked Sendable {
    static let shared = NodeExtensions()

    private let lock = NSLock()
    private var kinds: [String: NodeBehavior] = [:]
    private var modifiers: [String: ModifierBehavior] = [:]
    /// Whether any kind is registered, so that the common case reads no
    /// dictionary.
    private var hasKinds = false

    /// The behavior registered for a kind, or `nil`.
    static func behavior(for kind: String) -> NodeBehavior? {
        shared.lock.withLock { shared.hasKinds ? shared.kinds[kind] : nil }
    }

    /// The behavior registered for a modifier, or `nil`.
    static func modifier(named name: String) -> ModifierBehavior? {
        shared.lock.withLock { shared.modifiers[name] }
    }

    /// Registers a kind, replacing an earlier registration.
    static func register(kind: String, _ behavior: NodeBehavior) {
        shared.lock.withLock {
            shared.kinds[kind] = behavior
            shared.hasKinds = true
        }
    }

    /// Registers a kind unless it is registered already. A view calls this
    /// each time it makes its nodes, so the behavior is built once.
    static func registerOnce(kind: String, _ make: () -> NodeBehavior) {
        let isNew = shared.lock.withLock { shared.kinds[kind] == nil }
        if isNew { register(kind: kind, make()) }
    }

    /// Registers a modifier, replacing an earlier registration.
    static func register(modifier name: String, _ behavior: ModifierBehavior) {
        shared.lock.withLock { shared.modifiers[name] = behavior }
    }

    /// Registers a modifier unless it is registered already. A modifier's
    /// `View` extension calls this each time it is used.
    static func registerOnce(modifier name: String, _ make: () -> ModifierBehavior) {
        let isNew = shared.lock.withLock { shared.modifiers[name] == nil }
        if isNew { register(modifier: name, make()) }
    }

    /// Whether a kind is a presentation that a file of its own registered.
    static func isPresentation(_ kind: String) -> Bool {
        behavior(for: kind)?.isPresentation == true
    }
}

// MARK: - Input

/// What a node does with input beyond a tap. A view registers them with the
/// evaluator, like a button's action, and hit testing finds the frontmost
/// node under a point that has the handler it needs.
struct NodeInputHandlers {
    /// Runs when a press on the node is held for `duration` seconds, from
    /// ``ViewHost/longPress(at:duration:)``.
    var longPress: (@MainActor (_ point: CGPoint, _ duration: TimeInterval) -> Void)?
    /// Runs when a drag that starts on the node ends, from
    /// ``ViewHost/drag(from:to:duration:)``.
    var drag: (@MainActor (_ start: CGPoint, _ end: CGPoint, _ duration: TimeInterval) -> Void)?
    /// Runs when a pull past the top of the scroll view is released far
    /// enough, from ``View/refreshable(action:)``.
    var refresh: (@Sendable () async -> Void)?
}

extension View {
    /// Adds a layout modifier that a file of its own defines, by the name
    /// its behavior is registered under.
    func customModifier(
        _ name: String, _ parameters: [String: String] = [:],
        behavior: @autoclosure () -> ModifierBehavior
    ) -> some View {
        NodeExtensions.registerOnce(modifier: name, behavior)
        return layoutModifier(.custom(CustomModifier(name: name, parameters: parameters)))
    }
}
