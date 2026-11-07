import Foundation
import ParhelionRender

// rotationEffect, blur, and mask. Each is a layout modifier that does not
// change layout, so it applies at its place in the modifier chain, like
// `scaleEffect`. Rendering+Transform.swift draws them, through the hook in
// Rendering+Effects.swift.

extension View {
    /// Rotates how this view draws, clockwise for a positive angle, around
    /// an anchor in its bounds, without changing its layout. Assumed: taps
    /// reach the view's unrotated frame, as for `scaleEffect`.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        customModifier(
            TransformEffects.rotation,
            [
                "degrees": formatUnit(CGFloat(angle.degrees)),
                "anchorX": formatUnit(anchor.x), "anchorY": formatUnit(anchor.y),
            ],
            behavior: TransformEffects.rotationBehavior)
    }

    /// Blurs how this view draws, with a Gaussian of standard deviation
    /// `radius` points, without changing its layout.
    ///
    /// Assumed: `radius` is the standard deviation, as in SwiftUI, which
    /// does not document it. By default the blur spreads past the view's
    /// edges and fades into transparency. With `opaque`, the view is
    /// blurred within its bounds and the edge pixels extend outward, so the
    /// blur has no soft edge.
    public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        customModifier(
            TransformEffects.blur,
            ["radius": formatPoints(radius)].merging(opaque ? ["opaque": "true"] : [:]) { $1 },
            behavior: TransformEffects.blurBehavior)
    }

    /// Hides this view where a mask is transparent, and shows it where the
    /// mask is opaque, using the alpha of the mask view, which is laid out
    /// in this view's bounds as an `overlay(alignment:content:)` is.
    ///
    /// The mask's views become an `Overlay` child of each node this view
    /// resolves to, with the `mask` modifier after the overlay's. A mask
    /// outside the view's bounds hides nothing more; a view beyond the mask
    /// is hidden.
    public func mask<Mask: View>(
        alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        MaskView(content: self, mask: mask(), alignment: alignment)
    }
}

/// The names and behaviors of the three modifiers.
enum TransformEffects {
    static let rotation = "rotationEffect"
    static let blur = "blur"
    static let mask = "mask"

    /// A modifier's parameter as a number.
    static func number(
        _ parameters: [String: String], _ key: String, default value: Double = 0
    )
        -> Double
    {
        parameters[key].flatMap { Double($0) } ?? value
    }

    /// Draws everything inside through its function, when something other
    /// than the renderer's own hook asks. The renderer handles these three
    /// itself, because they draw on layers placed by the node's frames.
    private static let passThrough:
        @Sendable (
            TreeRenderer, [String: String], NodeDrawing, (inout Canvas) -> Void, inout Canvas
        ) -> Void = { _, _, _, inside, canvas in inside(&canvas) }

    static var rotationBehavior: ModifierBehavior {
        ModifierBehavior(
            outline: { parameters in
                var parts = [formatUnit(CGFloat(number(parameters, "degrees"))) + "°"]
                let anchor = UnitPoint(
                    x: CGFloat(number(parameters, "anchorX", default: 0.5)),
                    y: CGFloat(number(parameters, "anchorY", default: 0.5)))
                if anchor != .center { parts.append("anchor: \(anchor.name)") }
                return "rotationEffect(" + parts.joined(separator: ", ") + ")"
            },
            drawEffect: passThrough)
    }

    static var blurBehavior: ModifierBehavior {
        ModifierBehavior(
            outline: { parameters in
                "blur(radius: \(parameters["radius"] ?? "0")"
                    + (parameters["opaque"] == "true" ? ", opaque" : "") + ")"
            },
            drawEffect: passThrough)
    }

    static var maskBehavior: ModifierBehavior {
        ModifierBehavior(outline: { _ in "mask" }, drawEffect: passThrough)
    }
}

/// A view with a mask, produced by ``View/mask(alignment:_:)``.
struct MaskView<Content: View, Mask: View>: View {
    typealias Body = Never

    let content: Content
    let mask: Mask
    let alignment: Alignment

    var body: Never {
        fatalError("MaskView is a primitive view and has no body.")
    }
}

extension MaskView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        NodeExtensions.registerOnce(modifier: TransformEffects.mask) {
            TransformEffects.maskBehavior
        }
        return evaluator.evaluate(content, at: path).map { node in
            var node = node
            // The mask belongs to the node it covers, so its identity
            // follows the node's, as an overlay's does.
            let count = node.children.count { $0.kind == "Overlay" }
            let maskPath = ViewPath().appending(node.id.rawValue)
                .appending(count == 0 ? "mask" : "mask\(count + 1)")
            node.children.append(
                ViewNode(
                    id: maskPath.id, kind: "Overlay",
                    children: evaluator.evaluate(mask, at: maskPath)))
            node.modifiers.append(.overlay(alignment: alignment))
            node.modifiers.append(.custom(CustomModifier(name: TransformEffects.mask)))
            return node
        }
    }
}
