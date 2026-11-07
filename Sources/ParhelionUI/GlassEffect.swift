import Foundation
import ParhelionRender

/// An identifier for matching views, mirroring SwiftUI's `Namespace`.
///
/// Each `@Namespace` property keeps its ID for as long as its view stays at
/// the same position in the tree, as `@State` keeps its value, so views
/// that share a namespace match across updates. `glassEffectID(_:in:)`
/// uses it; `matchedGeometryEffect` and the zoom transition (#78) can too.
@propertyWrapper
public struct Namespace: DynamicProperty {
    public struct ID: Hashable, Sendable {
        let value: UInt64
    }

    nonisolated(unsafe) private static var next: UInt64 = 0

    private let initialID: ID
    let location: StateLocation<ID>

    public init() {
        Namespace.next += 1
        initialID = ID(value: Namespace.next)
        location = StateLocation(StateBox(initialID))
    }

    public var wrappedValue: Namespace.ID { location.box.value }
}

extension Namespace: StateInstallable {
    func install(in host: ViewHost, key: String) {
        location.box = host.stateBox(forKey: key, initialValue: initialID)
    }
}

/// How Liquid Glass looks, mirroring SwiftUI's `Glass`.
public struct Glass: Equatable, Sendable {
    var kind = "regular"
    var tintColor: Color?
    var isInteractive = false

    public static var regular: Glass { Glass() }
    public static var clear: Glass { Glass(kind: "clear") }
    public static var identity: Glass { Glass(kind: "identity") }

    public func tint(_ color: Color?) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }

    public func interactive(_ isEnabled: Bool = true) -> Glass {
        var copy = self
        copy.isInteractive = isEnabled
        return copy
    }
}

/// The shape that `glassEffect` uses when none is given: a capsule.
public struct DefaultGlassEffectShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Capsule().path(in: rect)
    }
}

/// A container for views that have `glassEffect`, mirroring SwiftUI's
/// `GlassEffectContainer`.
///
/// Glass shapes inside it that come closer than `spacing` draw as one
/// piece of glass, joined by a neck that thins as they move apart. A shape
/// with a `glassEffectID` that appears or disappears while an animation
/// runs grows out of, or shrinks into, the nearest glass that shares its
/// namespace. The content is laid out as in a `ZStack`.
public struct GlassEffectContainer<Content: View>: View {
    public typealias Body = Never

    let spacing: CGFloat?
    let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("GlassEffectContainer is a primitive view and has no body.")
    }
}

extension GlassEffectContainer: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        NodeExtensions.registerOnce(kind: "GlassEffectContainer") {
            GlassEffects.containerBehavior
        }
        let ownPath = path.appending("GlassEffectContainer")
        var attributes: [String: String] = [:]
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        return [
            ViewNode(
                id: ownPath.id, kind: "GlassEffectContainer", attributes: attributes,
                children: evaluator.evaluate(content, at: ownPath))
        ]
    }
}

extension View {
    /// Draws Liquid Glass in a shape behind the view.
    ///
    /// Alone, the glass is drawn behind this view. Inside a
    /// ``GlassEffectContainer``, the container draws it, so that nearby
    /// shapes merge.
    public func glassEffect(
        _ glass: Glass = .regular,
        in shape: some Shape = DefaultGlassEffectShape(),
        isEnabled: Bool = true
    ) -> some View {
        let geometry: ShapeGeometry =
            shape is DefaultGlassEffectShape ? .capsule(continuous: true) : ShapeGeometry(of: shape)
        return customModifier(
            GlassEffects.modifierName,
            GlassEffects.parameters(glass: isEnabled ? glass : .identity, shape: geometry),
            behavior: GlassEffects.modifierBehavior)
    }

    /// Names this view's glass, so that it morphs into and out of the glass
    /// of other views in the namespace when it appears or disappears in an
    /// animation, inside a ``GlassEffectContainer``.
    public func glassEffectID(
        _ id: (some Hashable & Sendable)?, in namespace: Namespace.ID
    ) -> some View {
        var parameters = ["namespace": "\(namespace.value)"]
        if let id { parameters["id"] = "\(id)" }
        return customModifier(
            GlassEffects.idModifierName, parameters, behavior: GlassEffects.idBehavior)
    }
}

// SwiftUI's static shape members, which `glassEffect(_:in:)` is usually
// called with: `in: .capsule`, `in: .rect(cornerRadius: 20)`.
extension Shape where Self == Capsule {
    public static var capsule: Capsule { Capsule() }
}

extension Shape where Self == Circle {
    public static var circle: Circle { Circle() }
}

extension Shape where Self == Ellipse {
    public static var ellipse: Ellipse { Ellipse() }
}

extension Shape where Self == Rectangle {
    public static var rect: Rectangle { Rectangle() }
}

extension Shape where Self == RoundedRectangle {
    public static func rect(
        cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous
    ) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
}
