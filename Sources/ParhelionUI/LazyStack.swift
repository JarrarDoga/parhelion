#if canImport(Foundation)
import Foundation
#endif

/// A vertical stack that creates its views only when they are near the
/// screen, mirroring SwiftUI's `LazyVStack`.
///
/// Inside a scroll view, the stack evaluates the views on screen and a margin
/// of about half a screen on each side. Views that scroll out are released,
/// and views that scroll in are created, with the `@State` they had before,
/// kept by identity. `onAppear` runs when a view is created. The stack
/// takes the width it is offered, as in SwiftUI.
///
/// The tree lists only the views that exist. A stack with views that are not
/// created records `lazyCount` and `lazyResolved`, the number of views it has
/// and the range of them that exist.
public struct LazyVStack<Content: View>: View {
    public typealias Body = Never

    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let pinnedViews: PinnedScrollableViews
    let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVStack is a primitive view and has no body.")
    }
}

/// A horizontal stack that creates its views only when they are near the
/// screen, mirroring SwiftUI's `LazyHStack`. See ``LazyVStack``.
public struct LazyHStack<Content: View>: View {
    public typealias Body = Never

    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let pinnedViews: PinnedScrollableViews
    let content: Content

    public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHStack is a primitive view and has no body.")
    }
}

extension LazyVStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        return [
            makeLazyStackNode(
                "LazyVStack", vertical: true, attributes, pinnedViews, content, evaluator, path)
        ]
    }
}

extension LazyHStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        return [
            makeLazyStackNode(
                "LazyHStack", vertical: false, attributes, pinnedViews, content, evaluator, path)
        ]
    }
}

@MainActor
private func makeLazyStackNode(
    _ kind: String,
    vertical: Bool,
    _ attributes: [String: String],
    _ pinnedViews: PinnedScrollableViews,
    _ content: some View,
    _ evaluator: Evaluator,
    _ path: ViewPath
) -> ViewNode {
    NodeExtensions.registerOnce(kind: kind) {
        NodeBehavior(
            size: { engine, node, proposal, _ in
                engine.lazyStackSize(node, proposal, vertical: vertical)
            },
            place: { engine, node, rect in
                engine.lazyStackPlace(node, in: rect, vertical: vertical)
            })
    }
    let ownPath = path.appending(kind)
    var sink = LazySink(mode: .stack, ownPath: ownPath)
    sink.append(content, evaluator: evaluator, at: ownPath)
    var budget = LazyDefaults.initialSlots
    let resolved = evaluator.resolveLazySlots(
        id: ownPath.id, sink.slots, vertical: vertical, pinned: pinnedViews, budget: &budget)
    var attributes = attributes
    var pins: [String] = []
    if pinnedViews.contains(.sectionHeaders) { pins.append("headers") }
    if pinnedViews.contains(.sectionFooters) { pins.append("footers") }
    if !pins.isEmpty { attributes["pinnedViews"] = pins.joined(separator: ",") }
    attributes.merge(resolved.attributes) { $1 }
    return ViewNode(id: ownPath.id, kind: kind, attributes: attributes, children: resolved.nodes)
}

// MARK: - Windows

/// Numbers that choose how many views a lazy stack creates.
enum LazyDefaults {
    /// The slots created when nothing is known about the screen yet. A stack
    /// with no more slots than this creates all of them while it is on
    /// screen.
    static let initialSlots = 40
    /// The length of a slot along the stack, before any slot is measured.
    static let estimatedLength: CGFloat = 44
    /// The fewest slots beyond the screen on each side that a stack creates.
    static let minimumMargin = 4
    /// How far beyond the screen a stack creates views, as a fraction of the
    /// scroll view's length. Assumed: SwiftUI prefetches about as much.
    static let marginFraction: CGFloat = 0.5
}

/// A scroll view that is being placed, which lazy stacks inside it measure
/// against.
struct LazyViewport {
    var id: NodeID
    var rect: CGRect
    /// Room at the top and the bottom of the scroll view that bars cover.
    var topInset: CGFloat
    var bottomInset: CGFloat
}

/// What lazy stacks know between evaluating and laying out: which of their
/// slots exist, how long each slot is, and which slots the screen needs.
///
/// Evaluation chooses a *window* of slots to create from the *demand* that
/// the last layout found, and layout measures the slots that exist. When
/// scrolling moves the demand out of the window, the host evaluates again.
final class LazyLayoutState {
    final class Stack {
        let id: NodeID
        /// The path that the state of the views in the slots starts with.
        var statePrefix: String
        /// The identity of each slot, in order.
        var identities: [AnyHashable] = []
        /// The length of each slot along the stack, without spacing: `nan`
        /// until the slot has been created and measured, and `-1` for a
        /// slot that has no views.
        var lengths: [CGFloat] = []
        /// The length across the stack that the lengths were measured at.
        var measuredAcross: CGFloat?
        /// The sizes of the stack's children at one length across the stack,
        /// from the last layout of this evaluation.
        var childSizes: (across: CGFloat, spacing: CGFloat, sizes: [CGSize])?
        /// The slots that exist, in the order of the stack's children.
        var resolved: [Int] = []
        /// The number of nodes in each of the `resolved` slots.
        var nodeCounts: [Int] = []
        /// The slots the stack asked for, not counting pinned headers and
        /// footers.
        var window: Range<Int> = 0..<0
        /// The slots that overlap the scroll view's bounds in the last
        /// layout, or `nil` before the stack was laid out.
        var demand: Range<Int>?
        /// The length of the scroll view along the stack in the last layout.
        var viewportLength: CGFloat = 0
        /// The mean length of the slots measured, or the default.
        var estimate = LazyDefaults.estimatedLength
        var sections: [LazySectionInfo] = []
        /// Where the stack's first slot starts on screen in the last layout,
        /// along the stack, and the spacing it used.
        var origin: CGFloat = 0
        var spacing: CGFloat = 0
        /// The scroll view the stack was inside in the last layout.
        var scrollView: LazyViewport?
        var visited = false
        /// The identities as text, for finding the state of a row that was
        /// released.
        private var liveIdentities: Set<String>?

        init(id: NodeID) {
            self.id = id
            statePrefix = id.rawValue
        }

        var count: Int { identities.count }

        /// Takes the slots of this evaluation, keeping the lengths of slots
        /// that are still there.
        func update(identities new: [AnyHashable]) {
            if new == identities { return }
            var known: [AnyHashable: CGFloat] = [:]
            for (index, length) in lengths.enumerated() where !length.isNaN {
                known[identities[index]] = length
            }
            identities = new
            lengths = new.map { known[$0] ?? .nan }
            liveIdentities = nil
        }

        /// Whether `key` is the state of a view in a slot that still exists.
        func retains(_ key: String) -> Bool {
            let prefix = statePrefix + "/"
            guard key.hasPrefix(prefix) else { return false }
            guard
                let marker = key.range(
                    of: "ForEach[",
                    range: key.index(key.startIndex, offsetBy: prefix.count)..<key.endIndex)
            else { return true }
            if liveIdentities == nil {
                liveIdentities = Set(identities.map { String(describing: $0) })
            }
            let live = liveIdentities!
            var end = marker.upperBound
            while let close = key[end...].firstIndex(of: "]") {
                if live.contains(String(key[marker.upperBound..<close])) { return true }
                end = key.index(after: close)
            }
            return false
        }

        /// Chooses the slots to create.
        func chooseWindow(budget: inout Int) {
            let n = count
            let previous = window.clamped(to: 0..<n)
            var chosen: Range<Int>
            if let demand {
                if demand.isEmpty {
                    chosen = 0..<0
                } else if n <= LazyDefaults.initialSlots {
                    chosen = 0..<n
                } else if !previous.isEmpty, previous.lowerBound <= demand.lowerBound,
                    previous.upperBound >= demand.upperBound
                {
                    chosen = previous
                } else {
                    let margin = max(
                        LazyDefaults.minimumMargin,
                        Int(
                            (LazyDefaults.marginFraction * viewportLength / max(estimate, 1))
                                .rounded(.up)))
                    chosen =
                        max(demand.lowerBound - margin, 0)..<min(demand.upperBound + margin, n)
                }
            } else if !previous.isEmpty {
                chosen = previous
            } else {
                let take = min(n, max(budget, 0))
                chosen = 0..<take
                budget -= take
            }
            window = chosen
        }

        /// The slots to create: the window, and the headers and footers that
        /// stay on screen at its edges.
        func slotsToCreate(pinHeaders: Bool, pinFooters: Bool) -> [Int] {
            guard !window.isEmpty else { return [] }
            var before: [Int] = []
            var after: [Int] = []
            for section in sections {
                if pinHeaders, let header = section.header, header < window.lowerBound,
                    section.end > window.lowerBound
                {
                    before.append(header)
                }
                if pinFooters, let footer = section.footer, footer >= window.upperBound,
                    section.start < window.upperBound
                {
                    after.append(footer)
                }
            }
            return before + Array(window) + after
        }

        /// Whether the window covers what the last layout found on screen.
        var coversDemand: Bool {
            guard let demand else { return true }
            if demand.isEmpty { return window.isEmpty }
            if count <= LazyDefaults.initialSlots { return window == 0..<count }
            return window.lowerBound <= demand.lowerBound && window.upperBound >= demand.upperBound
        }
    }

    private(set) var stacks: [NodeID: Stack] = [:]
    /// The scroll views being placed, innermost last.
    var viewports: [LazyViewport] = []

    func stack(_ id: NodeID) -> Stack {
        if let stack = stacks[id] { return stack }
        let stack = Stack(id: id)
        stacks[id] = stack
        return stack
    }

    func beginEvaluation() {
        for stack in stacks.values { stack.visited = false }
    }

    /// Forgets the stacks that left the tree.
    func finishEvaluation() {
        stacks = stacks.filter { $0.value.visited }
    }

    /// Forgets a stack that an evaluation gave up on.
    func forget(_ id: NodeID) {
        stacks[id] = nil
    }

    func beginLayout() {
        for stack in stacks.values { stack.demand = nil }
        viewports = []
    }

    /// Whether any stack needs views that its window does not have.
    var needsWindowChange: Bool {
        stacks.values.contains { !$0.coversDemand }
    }

    /// Whether `key`, the key of a view's `@State`, belongs to a view in a
    /// lazy stack that was released and is still in the stack's data.
    func retainsState(_ key: String) -> Bool {
        stacks.values.contains { $0.retains(key) }
    }
}

extension Evaluator {
    /// What a lazy container evaluates for its slots.
    struct LazyResolution {
        var nodes: [ViewNode]
        var attributes: [String: String]
    }

    /// Chooses the window of a lazy container's slots and evaluates the
    /// slots in it.
    ///
    /// - Parameter transform: Changes the nodes of a slot, such as giving a
    ///   list row its insets.
    func resolveLazySlots(
        id: NodeID, statePrefix: String? = nil, _ slots: LazySlots, vertical: Bool,
        pinned: PinnedScrollableViews, budget: inout Int,
        transform: (@MainActor ([ViewNode], LazySlotRole) -> [ViewNode])? = nil
    ) -> LazyResolution {
        let stack = host.lazy.stack(id)
        stack.visited = true
        stack.statePrefix = statePrefix ?? id.rawValue
        stack.update(identities: slots.identities)
        stack.sections = slots.sections
        stack.chooseWindow(budget: &budget)
        let wanted = stack.slotsToCreate(
            pinHeaders: pinned.contains(.sectionHeaders),
            pinFooters: pinned.contains(.sectionFooters))
        var nodes: [ViewNode] = []
        var counts: [Int] = []
        for slot in wanted {
            let role = slots.role(of: slot)
            var made = slots.make(slot, in: self)
            if let transform { made = transform(made, role) }
            counts.append(made.count)
            nodes += made
        }
        stack.resolved = wanted
        stack.nodeCounts = counts
        stack.childSizes = nil
        var attributes: [String: String] = [:]
        if stack.window != 0..<stack.count {
            attributes["lazyCount"] = String(stack.count)
            let window = stack.window
            attributes["lazyResolved"] = "\(window.lowerBound)..<\(window.upperBound)"
        }
        return LazyResolution(nodes: nodes, attributes: attributes)
    }
}
