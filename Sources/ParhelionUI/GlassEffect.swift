import Foundation
import ParhelionRender

/// An identifier for matching views, mirroring SwiftUI's `Namespace`.
///
/// A compile-only stub: every `@Namespace` property gets a new ID when its
/// view is created again. Issues #54 and #78 keep it stable.
@propertyWrapper
public struct Namespace: DynamicProperty {
    public struct ID: Hashable, Sendable {
        let value: UInt64
    }

    nonisolated(unsafe) private static var next: UInt64 = 0

    private let id: ID

    public init() {
        Namespace.next += 1
        id = ID(value: Namespace.next)
    }

    public var wrappedValue: Namespace.ID { id }
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

/// The shape that `glassEffect` uses when none is given.
public struct DefaultGlassEffectShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Capsule().path(in: rect)
    }
}

/// A compile-only stub: a container that shows its content. Issue #54
/// blends the glass of its children.
public struct GlassEffectContainer<Content: View>: View {
    let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View { content }
}

extension View {
    /// A compile-only stub that draws no glass. Issue #54 draws it.
    public func glassEffect(
        _ glass: Glass = .regular,
        in shape: some Shape = DefaultGlassEffectShape()
    ) -> some View {
        self
    }

    /// A compile-only stub. Issue #54 morphs glass between views.
    public func glassEffectID(
        _ id: (some Hashable & Sendable)?, in namespace: Namespace.ID
    ) -> some View {
        self
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
