import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// Drawing that `ViewHost` keeps from one frame to the next, so that an
/// animation frame redraws only what moved. Whatever it reuses is the same,
/// pixel for pixel, as drawing it again.
///
/// - **The backdrop**: the screen beneath the frontmost presentation, which
///   usually stays still while a sheet or an alert animates. It is kept
///   while that part of the tree, and the pressed or focused view in it,
///   stay the same.
/// - **A fading presentation**, drawn at full opacity over the backdrop.
///   Each frame of its fade is then one blend of the two.
/// - **Glass surfaces** whose pixels beneath did not change, such as
///   toolbar buttons over a bar while a list scrolls below them. A surface
///   drawn with the same arguments in two frames in a row is kept with the
///   pixels it read and the pixels it left; a later frame that finds the
///   same pixels beneath copies the result instead of drawing it.
/// - **Scroll edge effects**, kept the same way: while a scroll view's
///   content under a bar does not move, as when only a toggle animates,
///   the blur is copied instead of computed again.
///
/// It holds at most two full-screen canvases, each about 5 MB at 2× and 12
/// to 15 MB at 3×, and glass up to ``glassByteLimit``. The backdrop goes
/// when nothing is presented, the layer when nothing fades over it, and
/// glass that a frame did not draw after that frame.
final class RenderCache {
    /// What the backdrop's pixels depend on.
    struct BackdropKey: Equatable {
        var scale: Double
        var device: Device
        /// The window's color scheme, which the root records and its
        /// children inherit.
        var colorScheme: ColorScheme
        /// The nodes drawn before the frontmost presentation.
        var nodes: [ViewNode]
        /// The pressed button and the focused field, only when they are
        /// among those nodes.
        var pressedNodeID: NodeID?
        var focusedNodeID: NodeID?
        var caretOffset: Int
        /// The other end of the selected text, if any.
        var selectionAnchor: Int?
    }

    struct Backdrop {
        var key: BackdropKey
        var canvas: Canvas
        /// Increases each time the backdrop is drawn again, so that a layer
        /// knows which backdrop it was drawn over.
        var generation: Int
    }

    /// What a fading presentation's layer depends on.
    struct LayerKey: Equatable {
        var backdropGeneration: Int
        /// The window's color scheme, which the presentation inherits.
        var colorScheme: ColorScheme
        /// The presentation, without its own opacity.
        var node: ViewNode
        var pressedNodeID: NodeID?
        var focusedNodeID: NodeID?
        var caretOffset: Int
        /// The other end of the selected text, if any.
        var selectionAnchor: Int?
    }

    /// A fading presentation drawn at full opacity over a backdrop.
    struct Layer {
        var key: LayerKey
        var canvas: Canvas
    }

    /// What a glass surface's pixels depend on, apart from the pixels
    /// beneath it.
    struct GlassKey: Hashable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var cornerRadius: CGFloat
        var style: Path.CornerStyle
        var material: GlassMaterial
        var tint: RGBA?
        var opacity: Double
        var scale: Double
        var canvasWidth: Int
        var canvasHeight: Int
        var clip: [Double]?
    }

    /// What a scroll edge effect's pixels depend on, apart from the pixels
    /// beneath it.
    struct EdgeKey: Hashable {
        var rect: [Double]
        var effect: ScrollEdgeEffect
        var scale: Double
        var canvasWidth: Int
        var canvasHeight: Int
        var clip: [Double]?
    }

    /// A kept drawing: glass, merged glass, or a scroll edge effect.
    enum EntryKey: Hashable {
        case glass(GlassKey)
        /// Glass shapes of a `GlassEffectContainer` drawn as one piece;
        /// see Rendering+GlassEffect.swift.
        case merged(MergedGlassKey)
        case edge(EdgeKey)
    }

    struct GlassEntry {
        var region: PixelBox
        /// The region's pixels before the glass was drawn, and after.
        var before: [UInt32]
        var after: [UInt32]
        var lastFrame: Int
    }

    /// The most memory that kept glass surfaces use: 16 MB.
    static let glassByteLimit = 16 << 20

    private(set) var backdrop: Backdrop?
    /// The presentation fading now, at full opacity.
    private(set) var layer: Layer?
    /// Whether this frame drew a fading presentation over the backdrop.
    private var layerUsed = false
    private var backdropGeneration = 0
    private var glass: [EntryKey: GlassEntry] = [:]
    private var glassBytes = 0
    /// The glass surfaces drawn in the previous frame and in this one.
    private var previousGlass: Set<EntryKey> = []
    private var currentGlass: Set<EntryKey> = []
    /// Checksums of the pixels beneath scroll edge effects, in the previous
    /// frame and in this one.
    private var previousStamps: [EntryKey: UInt64] = [:]
    private var currentStamps: [EntryKey: UInt64] = [:]
    private var frame = 0

    /// The number of glass surfaces kept, and how many times one was
    /// reused, for tests.
    var glassCount: Int { glass.count }
    private(set) var glassReuses = 0

    /// Starts drawing a frame.
    func beginFrame() {
        frame += 1
        previousGlass = currentGlass
        currentGlass = []
        previousStamps = currentStamps
        currentStamps = [:]
        layerUsed = false
    }

    /// Finishes a frame: forgets glass this frame did not draw, the layer
    /// when nothing faded, and both canvases when nothing was presented.
    func endFrame(presenting: Bool) {
        if !presenting { backdrop = nil }
        if !presenting || !layerUsed { layer = nil }
        for (key, entry) in glass where entry.lastFrame != frame {
            glassBytes -= Self.bytes(of: entry)
            glass[key] = nil
        }
    }

    /// Keeps a newly drawn backdrop, and returns its generation.
    func keepBackdrop(_ canvas: Canvas, key: BackdropKey) -> Int {
        backdropGeneration += 1
        backdrop = Backdrop(key: key, canvas: canvas, generation: backdropGeneration)
        layer = nil
        return backdropGeneration
    }

    /// The kept layer of a fading presentation, if it was drawn for the
    /// same key.
    func layer(for key: LayerKey) -> Canvas? {
        guard let layer, layer.key == key else { return nil }
        layerUsed = true
        return layer.canvas
    }

    /// Keeps the layer of a fading presentation.
    func keepLayer(_ canvas: Canvas, key: LayerKey) {
        layerUsed = true
        layer = Layer(key: key, canvas: canvas)
    }

    /// Draws a glass surface, or copies it from an earlier frame when the
    /// pixels beneath it are the same.
    func drawGlass(
        _ rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle, material: GlassMaterial,
        tint: RGBA?, opacity: Double, into canvas: inout Canvas
    ) {
        let key = GlassKey(
            x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width),
            height: Double(rect.height), cornerRadius: cornerRadius, style: style,
            material: material, tint: tint, opacity: opacity, scale: canvas.scale,
            canvasWidth: canvas.width, canvasHeight: canvas.height,
            clip: canvas.clipRect.map {
                [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)]
            })
        reuse(
            .glass(key), region: canvas.glassRegion(rect, material: material, tint: tint),
            into: &canvas
        ) { canvas in
            canvas.drawGlass(
                rect, cornerRadius: cornerRadius, style: style, material: material, tint: tint,
                opacity: opacity)
        }
    }

    /// Draws a scroll edge effect over a rectangle, or copies it from an
    /// earlier frame when the pixels beneath it are the same.
    func drawScrollEdge(_ effect: ScrollEdgeEffect, in rect: CGRect, into canvas: inout Canvas) {
        let key = EdgeKey(
            rect: [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)],
            effect: effect, scale: canvas.scale, canvasWidth: canvas.width,
            canvasHeight: canvas.height,
            clip: canvas.clipRect.map {
                [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)]
            })
        reuse(
            .edge(key), region: canvas.scrollEdgeRegion(effect, in: rect), checksummed: true,
            into: &canvas
        ) { canvas in
            canvas.drawScrollEdge(effect, in: rect)
        }
    }

    /// Runs `draw` on the canvas, or copies what it drew in an earlier frame
    /// when the pixels of `region`, which `draw` reads and changes, are the
    /// same as then.
    func reuse(
        _ key: EntryKey, region: PixelBox, checksummed: Bool = false, into canvas: inout Canvas,
        draw: (inout Canvas) -> Void
    ) {
        currentGlass.insert(key)
        if var entry = glass[key], entry.region == region,
            canvas.pixels(in: region, equal: entry.before)
        {
            canvas.replacePixels(in: region, with: entry.after)
            entry.lastFrame = frame
            glass[key] = entry
            glassReuses += 1
            return
        }
        // Only a drawing that stays where it was is worth keeping: one that
        // moves or fades would be kept and dropped every frame. A scroll
        // edge effect covers a large region, which scrolling content under
        // it changes in every frame, so it is kept only when the pixels it
        // reads are the same as in the previous frame, by a checksum.
        let replaced = glass[key].map(Self.bytes(of:)) ?? 0
        var still = true
        if checksummed {
            let sum = canvas.checksum(of: region)
            still = previousStamps[key] == sum
            currentStamps[key] = sum
        }
        let keep =
            previousGlass.contains(key) && still
            && glassBytes - replaced + region.area * 8 <= Self.glassByteLimit
        let before = keep ? canvas.pixels(in: region) : []
        draw(&canvas)
        guard keep else { return }
        if let old = glass[key] { glassBytes -= Self.bytes(of: old) }
        let entry = GlassEntry(
            region: region, before: before, after: canvas.pixels(in: region), lastFrame: frame)
        glassBytes += Self.bytes(of: entry)
        glass[key] = entry
    }

    private static func bytes(of entry: GlassEntry) -> Int {
        (entry.before.count + entry.after.count) * 4
    }
}

/// The sizes `LayoutEngine` chose for nodes, kept from one layout to the
/// next, so that laying out a tree again after a scroll or an animation
/// frame measures only what changed.
///
/// An entry is the node as it was measured, the number of its modifiers
/// that were applied, and the proposal, which together decide the size. A
/// lookup uses an entry only when the node it is given is equal to the node
/// it was measured for. Equal nodes share storage when the host lays out
/// the same evaluated tree again, so the comparison is quick then, and a
/// node that evaluation made again still gets the size it had when nothing
/// in it changed.
///
/// A size that read layout state other than the node, such as the lengths
/// a lazy stack has measured, is not kept: whatever read that state calls
/// ``noteStateRead()``, and every size computed meanwhile, including the
/// sizes of the nodes around it, is dropped. A cached size is the same, bit
/// for bit, as measuring again.
final class SizeCache {
    struct Key: Hashable {
        var id: NodeID
        var modifierCount: Int
        var width: CGFloat?
        var height: CGFloat?
        /// 0 for no axis, 1 for horizontal, 2 for vertical.
        var axis: UInt8
    }

    private struct Entry {
        var node: ViewNode
        var size: CGSize
    }

    /// The most entries kept. A cache that fills starts over.
    static let limit = 50_000

    private var entries: [Key: Entry] = [:]
    private var stateReads = 0
    /// How many sizes were found and how many were measured, for tests and
    /// benchmarks.
    private(set) var hits = 0
    private(set) var misses = 0

    var count: Int { entries.count }

    /// Records that a size being computed read state that is not in its
    /// node, so that no size computed since it started is kept.
    func noteStateRead() {
        stateReads += 1
    }

    func size(
        of node: ViewNode, modifierCount: Int, proposal: ProposedSize, parentAxis: LayoutAxis?,
        measure: () -> CGSize
    ) -> CGSize {
        let key = Key(
            id: node.id, modifierCount: modifierCount, width: proposal.width,
            height: proposal.height,
            axis: parentAxis.map { $0 == .horizontal ? 1 : 2 } ?? 0)
        if let entry = entries[key], entry.node == node {
            hits += 1
            return entry.size
        }
        misses += 1
        let before = stateReads
        let size = measure()
        // A node that layout has placed carries frames, which differ from
        // one layout to the next; measuring it is rare.
        if stateReads == before, node.frame == nil {
            if entries.count >= Self.limit { entries.removeAll(keepingCapacity: true) }
            entries[key] = Entry(node: node, size: size)
        }
        return size
    }

    /// Forgets every size.
    func removeAll() {
        entries.removeAll()
    }
}
