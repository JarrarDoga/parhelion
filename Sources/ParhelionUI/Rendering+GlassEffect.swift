import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// `glassEffect`, `GlassEffectContainer`, and `glassEffectID` (GlassEffect.swift).
//
// Both plug in through the extension seam (NodeBehavior.swift), so no shared
// file knows about them. A `glassEffect` modifier draws its glass behind its
// view. Inside a `GlassEffectContainer`, layout marks the modifier as
// grouped, and the container draws the glass of every grouped shape in its
// subtree before its children: shapes closer than the container's spacing
// draw as one piece, and a shape that is appearing or disappearing grows out
// of, or shrinks into, the nearest settled glass that shares its namespace.
//
// A shape on its own, which is nearly every glass surface, goes through
// `Canvas.drawGlass` and the render cache like the bars and buttons do. Only
// merged shapes and shapes that are not rounded rectangles take the general
// path.

enum GlassEffects {
    static let modifierName = "glassEffect"
    static let idModifierName = "glassEffectID"

    /// The parameters of a `glassEffect` modifier in the tree.
    static func parameters(glass: Glass, shape: ShapeGeometry) -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var parameters = [
            "glass": glass.kind,
            "shape": (try? encoder.encode(shape)).map { String(decoding: $0, as: UTF8.self) } ?? "",
        ]
        if let tint = glass.tintColor { parameters["tint"] = tint.styleName }
        if glass.isInteractive { parameters["interactive"] = "true" }
        return parameters
    }

    static let modifierBehavior = ModifierBehavior(
        outline: { parameters in
            guard let glass = GlassParameters(parameters) else { return modifierName }
            var description = glass.kind
            if let tint = glass.tint { description += ".tint(\(tint))" }
            if glass.isInteractive { description += ".interactive()" }
            return "\(modifierName)(\(description), in: \(glass.geometry.outlineDescription))"
        },
        drawBehind: { renderer, parameters, drawing, canvas in
            // Inside a container, the container draws the glass.
            guard let glass = GlassParameters(parameters), !glass.isGrouped else { return }
            let shape = GlassShape(frame: drawing.frame, parameters: glass, opacity: 1)
            renderer.drawGlassShapes([shape], spacing: 0, drawing: drawing, into: &canvas)
        })

    /// `glassEffectID` draws nothing: the container reads it.
    static let idBehavior = ModifierBehavior(
        outline: { parameters in
            "\(idModifierName)(\(parameters["id"] ?? "nil"))"
        })

    /// A container is laid out as a `ZStack`, and marks the glass of its
    /// subtree as grouped, so that the container draws it.
    static let containerBehavior = NodeBehavior(
        size: { engine, node, proposal, _ in
            engine.sizeThatFits(LayoutEngine.stack("ZStack", node), proposal, parentAxis: nil)
        },
        place: { engine, node, rect in
            let proposal = ProposedSize(rect.size)
            return node.children.map { child in
                let size = engine.sizeThatFits(child, proposal, parentAxis: nil)
                return grouped(
                    engine.place(child, in: engine.align(size, in: rect, .center), parentAxis: nil))
            }
        },
        draw: { renderer, node, drawing, canvas in
            let spacing = node.attributes["spacing"].flatMap(Double.init).map { CGFloat($0) } ?? 0
            var shapes: [GlassShape] = []
            collect(node.children, opacity: 1, into: &shapes)
            renderer.drawGlassShapes(shapes, spacing: spacing, drawing: drawing, into: &canvas)
        })

    /// The node with the `glassEffect` modifiers in its subtree marked as
    /// grouped.
    static func grouped(_ node: ViewNode) -> ViewNode {
        var node = node
        node.modifiers = node.modifiers.map { modifier in
            guard case .custom(var custom) = modifier, custom.name == modifierName,
                custom.parameters["grouped"] == nil
            else { return modifier }
            custom.parameters["grouped"] = "true"
            return .custom(custom)
        }
        node.children = node.children.map(grouped)
        return node
    }

    /// The glass shapes of the nodes and their descendants, in the order
    /// they draw, not looking into a container inside: it draws its own.
    static func collect(_ nodes: [ViewNode], opacity: Double, into shapes: inout [GlassShape]) {
        for node in nodes where node.kind != "GlassEffectContainer" {
            let opacity = opacity * node.opacity
            var id: GlassIdentity?
            for case .custom(let modifier) in node.modifiers where modifier.name == idModifierName {
                id = GlassIdentity(
                    id: modifier.parameters["id"] ?? "",
                    namespace: modifier.parameters["namespace"] ?? "")
            }
            for (index, modifier) in node.modifiers.enumerated() {
                guard case .custom(let custom) = modifier, custom.name == modifierName,
                    index < node.modifierFrames.count,
                    let parameters = GlassParameters(custom.parameters)
                else { continue }
                var shape = GlassShape(
                    frame: node.modifierFrames[index], parameters: parameters, opacity: opacity)
                shape.identity = id
                shapes.append(shape)
            }
            collect(node.children, opacity: opacity, into: &shapes)
        }
    }
}

/// A `glassEffect` modifier's parameters, read back from the tree.
struct GlassParameters {
    var kind: String
    var tint: String?
    var isInteractive: Bool
    var geometry: ShapeGeometry
    var isGrouped: Bool

    init?(_ parameters: [String: String]) {
        guard let kind = parameters["glass"], let json = parameters["shape"],
            let geometry = try? JSONDecoder().decode(ShapeGeometry.self, from: Data(json.utf8))
        else { return nil }
        self.kind = kind
        self.geometry = geometry
        tint = parameters["tint"]
        isInteractive = parameters["interactive"] == "true"
        isGrouped = parameters["grouped"] == "true"
    }
}

/// The `glassEffectID` of a view: its ID and its namespace.
struct GlassIdentity: Hashable {
    var id: String
    var namespace: String
}

/// One glass surface to draw.
struct GlassShape {
    /// The bounds of the shape, from the `glassEffect` modifier's place in
    /// the chain.
    var frame: CGRect
    var kind: String
    var tint: String?
    var geometry: ShapeGeometry
    /// The product of the opacities from the container down to the view
    /// that has the modifier: below 1 while the view fades in or out.
    var opacity: Double
    var identity: GlassIdentity?

    init(frame: CGRect, parameters: GlassParameters, opacity: Double) {
        self.frame = frame
        kind = parameters.kind
        tint = parameters.tint
        geometry = parameters.geometry
        self.opacity = opacity
    }
}

/// A piece of glass to draw: a path, and, when it is a rounded rectangle,
/// the rectangle whose edge gets the bright line and the ring.
struct GlassPiece {
    var path: Path
    var bounds: CGRect
    var ring: (rect: CGRect, radius: CGFloat, style: RoundedCornerStyle)?

    init(roundedRect rect: CGRect, radius: CGFloat, style: RoundedCornerStyle) {
        path = Path(roundedRect: rect, cornerRadius: radius, style: style)
        bounds = rect
        ring = (rect, radius, style)
    }

    /// A path that lies inside `bounds`.
    init(path: Path, bounds: CGRect) {
        self.path = path
        self.bounds = bounds
        ring = nil
    }

    /// A text form that tells two pieces apart, for the render cache.
    var signature: String {
        if let ring { return "\(ring.rect) \(ring.radius) \(ring.style)" }
        return path.svgPathData
    }
}

/// What a group of merged glass shapes draws with, apart from the pixels
/// beneath it, for the render cache.
struct MergedGlassKey: Hashable {
    var pieces: [String]
    var material: GlassMaterial
    var tint: RGBA?
    var opacity: Double
    var scale: Double
    var canvasWidth: Int
    var canvasHeight: Int
    var clip: [Double]?
}

extension TreeRenderer {
    /// Draws glass shapes: one at a time when they are apart, and as one
    /// piece when they are closer than `spacing`.
    func drawGlassShapes(
        _ shapes: [GlassShape], spacing: CGFloat, drawing: NodeDrawing, into canvas: inout Canvas
    ) {
        let shapes = shapes.filter { $0.kind != "identity" && !$0.frame.isEmpty }
        guard !shapes.isEmpty else { return }
        let frames = Self.morphedFrames(shapes)

        // Group the shapes with the same glass that are closer than the
        // spacing, or touch.
        var group = Array(shapes.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while group[index] != index { index = group[index] }
            return index
        }
        for first in shapes.indices {
            for second in shapes.indices where second > first {
                let distance = Self.gap(frames[first].frame, frames[second].frame)
                guard shapes[first].kind == shapes[second].kind,
                    shapes[first].tint == shapes[second].tint,
                    distance == 0 || distance < spacing
                else { continue }
                group[root(second)] = root(first)
            }
        }
        var order: [Int] = []
        for index in shapes.indices where !order.contains(root(index)) { order.append(root(index)) }

        for leader in order {
            let members = shapes.indices.filter { root($0) == leader }
            let opacity = drawing.opacity * (members.map { frames[$0].opacity }.max() ?? 1)
            var pieces: [GlassPiece] = []
            for member in members {
                let frame = frames[member].frame
                if let rounded = shapes[member].geometry.roundedRect(in: frame) {
                    pieces.append(
                        GlassPiece(
                            roundedRect: rounded.rect, radius: rounded.radius,
                            style: rounded.style))
                } else {
                    pieces.append(
                        GlassPiece(path: shapes[member].geometry.path(in: frame), bounds: frame))
                }
            }
            for (offset, first) in members.enumerated() {
                for second in members[(offset + 1)...] {
                    if let bridge = Self.bridge(
                        frames[first].frame, frames[second].frame, spacing: spacing)
                    {
                        pieces.append(bridge)
                    }
                }
            }
            drawGlassGroup(
                pieces, shape: shapes[leader], opacity: opacity, drawing: drawing, into: &canvas)
        }
    }

    /// The frame and the opacity each shape draws with. A shape that is
    /// fading in or out and has an ID draws between the frame of the
    /// nearest settled shape in its namespace and its own, and fills in
    /// quickly, so it seems to grow out of that glass.
    private static func morphedFrames(_ shapes: [GlassShape]) -> [(frame: CGRect, opacity: Double)]
    {
        shapes.map { shape in
            let progress = min(max(shape.opacity, 0), 1)
            guard progress < 1, let identity = shape.identity else {
                return (shape.frame, progress)
            }
            let center = CGPoint(x: shape.frame.midX, y: shape.frame.midY)
            let source =
                shapes.filter {
                    $0.opacity >= 1 && $0.identity?.namespace == identity.namespace
                        && $0.kind != "identity"
                }
                .min {
                    hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
                        < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
                }
            guard let source else { return (shape.frame, progress) }
            func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
                from + (to - from) * CGFloat(progress)
            }
            return (
                CGRect(
                    x: mix(source.frame.minX, shape.frame.minX),
                    y: mix(source.frame.minY, shape.frame.minY),
                    width: mix(source.frame.width, shape.frame.width),
                    height: mix(source.frame.height, shape.frame.height)),
                min(progress * 3, 1)
            )
        }
    }

    /// The distance between two rectangles: 0 where they touch or overlap.
    private static func gap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, first.minX - second.maxX, second.minX - first.maxX)
        let dy = max(0, first.minY - second.maxY, second.minY - first.maxY)
        return hypot(dx, dy)
    }

    /// The neck that joins two shapes closer than the spacing: a capsule
    /// from one center to the other, as thick as the thinner shape's 70%
    /// where they touch, and thinning to a quarter of that as they move
    /// apart. `nil` when the shapes are too far apart, or not side by side.
    private static func bridge(_ first: CGRect, _ second: CGRect, spacing: CGFloat) -> GlassPiece? {
        let distance = gap(first, second)
        guard distance == 0 || distance < spacing else { return nil }
        let strength = distance == 0 ? 1 : max(0.25, 1 - distance / spacing)
        let dx = max(0, first.minX - second.maxX, second.minX - first.maxX)
        let dy = max(0, first.minY - second.maxY, second.minY - first.maxY)
        let rect: CGRect
        if dx >= dy {
            let low = max(first.minY, second.minY)
            let high = min(first.maxY, second.maxY)
            guard high > low else { return nil }
            let thickness = min(min(first.height, second.height) * 0.7 * strength, high - low)
            rect = CGRect(
                x: min(first.midX, second.midX), y: (low + high) / 2 - thickness / 2,
                width: abs(first.midX - second.midX), height: thickness)
        } else {
            let low = max(first.minX, second.minX)
            let high = min(first.maxX, second.maxX)
            guard high > low else { return nil }
            let thickness = min(min(first.width, second.width) * 0.7 * strength, high - low)
            rect = CGRect(
                x: (low + high) / 2 - thickness / 2, y: min(first.midY, second.midY),
                width: thickness, height: abs(first.midY - second.midY))
        }
        guard rect.width > 0, rect.height > 0 else { return nil }
        return GlassPiece(
            roundedRect: rect, radius: min(rect.width, rect.height) / 2, style: .circular)
    }

    /// The material for a kind of glass. Regular glass is the small glass of
    /// toolbar buttons, and the large glass of alerts for shapes at least
    /// 140 points across; clear glass keeps only a trace of the frosting;
    /// tinted glass is the prominent glass of tinted buttons.
    private static func material(
        kind: String, tinted: Bool, size: CGSize, palette: ColorPalette.Appearance
    ) -> GlassMaterial {
        if tinted { return palette.prominentGlass }
        var material = min(size.width, size.height) >= 140 ? palette.largeGlass : palette.smallGlass
        if kind == "clear" {
            material.blurRadius = min(material.blurRadius, 2)
            material.saturation = 1
            material.tint = material.tint.map { layer in
                var layer = layer
                layer.color.alpha = UInt8((Double(layer.color.alpha) * 0.2).rounded())
                return layer
            }
            material.shadow.color.alpha = UInt8(
                (Double(material.shadow.color.alpha) * 0.6).rounded())
        }
        return material
    }

    private func drawGlassGroup(
        _ pieces: [GlassPiece], shape: GlassShape, opacity: Double, drawing: NodeDrawing,
        into canvas: inout Canvas
    ) {
        let bounds = pieces.dropFirst().reduce(pieces[0].bounds) { $0.union($1.bounds) }
        let material = Self.material(
            kind: shape.kind, tinted: shape.tint != nil, size: bounds.size,
            palette: drawing.palette)
        var tint: RGBA?
        if let name = shape.tint {
            var color = ColorPalette.color(
                named: name == "tint" ? drawing.tint ?? name : name, in: drawing.scheme)
            color.alpha = UInt8(
                (Double(color.alpha) * (shape.kind == "clear" ? 0.45 : 0.85)).rounded())
            tint = color
        }

        // One rounded rectangle: the same drawing and cache as the bars.
        if pieces.count == 1, let ring = pieces[0].ring {
            if let cache {
                cache.drawGlass(
                    ring.rect, cornerRadius: ring.radius, style: ring.style, material: material,
                    tint: tint, opacity: opacity, into: &canvas)
            } else {
                canvas.drawGlass(
                    ring.rect, cornerRadius: ring.radius, style: ring.style, material: material,
                    tint: tint, opacity: opacity)
            }
            return
        }

        let draw: (inout Canvas) -> Void = { canvas in
            Self.drawMerged(
                pieces, bounds: bounds, material: material, tint: tint, opacity: opacity,
                into: &canvas)
        }
        guard let cache else {
            draw(&canvas)
            return
        }
        let key = MergedGlassKey(
            pieces: pieces.map(\.signature), material: material, tint: tint, opacity: opacity,
            scale: canvas.scale, canvasWidth: canvas.width, canvasHeight: canvas.height,
            clip: canvas.clipRect.map {
                [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)]
            })
        cache.reuse(
            .merged(key), region: canvas.glassRegion(bounds, material: material, tint: tint),
            into: &canvas, draw: draw)
    }

    /// Draws pieces of glass as one: the shadow of their union, the glass
    /// inside it, and then the bright line and the ring around each
    /// piece's edge, cut away where another piece covers it, so the edge
    /// follows the outline of the union.
    private static func drawMerged(
        _ pieces: [GlassPiece], bounds: CGRect, material: GlassMaterial, tint: RGBA?,
        opacity: Double, into canvas: inout Canvas
    ) {
        func faded(_ color: RGBA) -> RGBA {
            var color = color
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            return color
        }
        var union = Path()
        for piece in pieces { union.addPath(piece.path) }

        canvas.drawShadow(
            of: union, color: faded(material.shadow.color),
            offset: CGSize(width: 0, height: material.shadow.offset), blur: material.shadow.blur)

        // The glass itself: `drawGlass` over the pieces' bounds with the
        // edges turned off, limited to the union.
        var fill = material
        fill.shadow.color = .clear
        fill.highlightTop = 0
        fill.highlightBottom = 0
        fill.rimWidth = 0
        let clip = canvas.beginClip(to: union)
        canvas.drawGlass(
            bounds, cornerRadius: 0, material: fill, tint: tint, opacity: opacity)
        canvas.endClip(clip)

        var edge = material
        edge.shadow.color = .clear
        edge.blurRadius = 0
        edge.tint = []
        let reach = material.highlightWidth + material.rimWidth + 2
        for (index, piece) in pieces.enumerated() {
            guard let ring = piece.ring else { continue }
            let area = ring.rect.insetBy(dx: -reach, dy: -reach)
            var clips: [Canvas.Clip] = []
            for (other, covering) in pieces.enumerated()
            where other != index && covering.bounds.intersects(area) {
                // Everything in the area except the covering piece.
                var outside = Path(area)
                outside.addPath(covering.path)
                clips.append(canvas.beginClip(to: outside, evenOdd: true))
            }
            canvas.drawGlass(
                ring.rect, cornerRadius: ring.radius, style: ring.style, material: edge,
                opacity: opacity)
            for clip in clips.reversed() { canvas.endClip(clip) }
        }
    }
}
