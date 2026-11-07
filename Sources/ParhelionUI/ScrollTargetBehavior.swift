import Foundation

/// How a scroll view settles after a drag, mirroring SwiftUI's
/// `ScrollTargetBehavior`. Custom behaviors are not supported: only
/// ``PagingScrollTargetBehavior`` and ``ViewAlignedScrollTargetBehavior``
/// change where a scroll view settles.
public protocol ScrollTargetBehavior {}

/// Settles on a page: a drag moves the content by one page, or back.
public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {}
}

/// Settles with the start of a view from `scrollTargetLayout()` at the start
/// of the scroll view.
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    /// How many views one drag can pass.
    public struct LimitBehavior: Hashable, Sendable {
        let name: String

        /// Assumed: one view along a horizontal scroll view, where the
        /// platform limits compact-width scroll views, and any number along
        /// a vertical one.
        public static let automatic = LimitBehavior(name: "automatic")
        public static let always = LimitBehavior(name: "always")
        public static let alwaysByFew = LimitBehavior(name: "alwaysByFew")
        public static let alwaysByOne = LimitBehavior(name: "alwaysByOne")
        public static let never = LimitBehavior(name: "never")
    }

    let limitBehavior: LimitBehavior

    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
    }
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    public static var viewAligned: ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior()
    }

    public static func viewAligned(
        limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior = .automatic
    ) -> ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }
}

// MARK: - Modifier

/// The behavior the scroll views below a view settle with, as the tree
/// records it: `paging`, or `viewAligned` with a limit behavior.
struct ScrollTargetBehaviorKey: EnvironmentKey {
    static var defaultValue: String? { nil }
}

extension View {
    /// Sets how the scroll views in this view settle after a drag. A scroll
    /// view that is moved by `scroll(by:at:)`, the mouse wheel, or
    /// ``ViewHost/scroll(_:to:)`` does not settle.
    public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        let recorded: String? =
            switch behavior {
            case is PagingScrollTargetBehavior: "paging"
            case let aligned as ViewAlignedScrollTargetBehavior:
                aligned.limitBehavior.name == "automatic"
                    ? "viewAligned" : "viewAligned(\(aligned.limitBehavior.name))"
            default: nil
            }
        return EnvironmentWriter(content: self) { values in
            values[ScrollTargetBehaviorKey.self] = recorded
        }
    }
}

// MARK: - Settling

/// What a drag leaves a scroll view to settle on.
private enum SettleBehavior {
    case paging
    case viewAligned(limit: String)

    init?(recorded: String?) {
        switch recorded {
        case "paging": self = .paging
        case "viewAligned": self = .viewAligned(limit: "automatic")
        case let name? where name.hasPrefix("viewAligned("):
            self = .viewAligned(limit: String(name.dropFirst(12).dropLast()))
        default: return nil
        }
    }
}

extension ViewHost {
    /// The speed past which a release turns the page, in points per second.
    /// Assumed: a flick, not a slow drag.
    private static let pageFlingSpeed: CGFloat = 300

    /// Settles a scroll view that a drag just released, if it has a scroll
    /// target behavior: paging moves by at most one page from where the drag
    /// began, and view alignment moves to the start of a view.
    ///
    /// - Returns: Whether the scroll view settled, so it should not coast.
    func settleScroll(
        _ id: NodeID, from start: CGPoint?,
        samples: [(time: TimeInterval, point: CGPoint)]
    ) -> Bool {
        guard let node = root.node(withID: id), let metrics = scrolling.metrics[id],
            let behavior = SettleBehavior(recorded: node.attributes["scrollTargetBehavior"])
        else { return false }
        let axes = LayoutEngine.scrollAxes(of: node)
        let velocity = releaseVelocity(of: samples)
        let start = start ?? metrics.offset
        let targets = scrollTargets(in: node)
        var offset = metrics.offset
        var settled = false

        for horizontal in [true, false] where horizontal ? axes.horizontal : axes.vertical {
            let maximum = horizontal ? metrics.maxOffset.x : metrics.maxOffset.y
            let current = horizontal ? metrics.offset.x : metrics.offset.y
            let origin = horizontal ? start.x : start.y
            // The content moves opposite to the pointer.
            let speed = horizontal ? -velocity.width : -velocity.height
            var result: CGFloat?
            switch behavior {
            case .paging:
                let length =
                    horizontal
                    ? metrics.viewport.width
                    : metrics.viewport.height - metrics.topInset - metrics.bottomInset
                guard length > 0 else { continue }
                let page = (origin / length).rounded()
                let moved = current - origin
                let turns = abs(moved) > length / 2 || abs(speed) > Self.pageFlingSpeed
                let direction = abs(speed) > Self.pageFlingSpeed ? speed : moved
                let target = page + (turns ? (direction < 0 ? -1 : 1) : 0)
                result = target * length
            case .viewAligned(let limit):
                // Where each view's start sits when it is at the start of
                // the visible region.
                let positions = targets.compactMap { target -> CGFloat? in
                    guard let frame = target.frame else { return nil }
                    return horizontal
                        ? frame.minX - metrics.viewport.minX + metrics.offset.x
                        : frame.minY - (metrics.viewport.minY + metrics.topInset)
                            + metrics.offset.y
                }.map { min(max($0, 0), maximum) }.sorted()
                guard !positions.isEmpty else { continue }
                func nearest(to value: CGFloat) -> Int {
                    positions.indices.min {
                        abs(positions[$0] - value) < abs(positions[$1] - value)
                    }!
                }
                // How far the content would coast: the integral of the
                // decaying speed.
                let coast = speed / CGFloat(-log(LayoutDefaults.scrollDecelerationRate) * 1000)
                var index = nearest(to: current + coast)
                let limited = limit == "automatic" ? horizontal : limit != "never"
                if limited {
                    let few = limit == "alwaysByFew" ? 3 : 1
                    let first = nearest(to: origin)
                    index = min(max(index, first - few), first + few)
                }
                result = positions[index]
            }
            guard let result else { continue }
            let clamped = min(max(result, 0), maximum)
            if horizontal { offset.x = clamped } else { offset.y = clamped }
            settled = true
        }
        guard settled else { return false }
        momentum[id] = nil
        if pendingAnimation == nil { pendingAnimation = .some(Self.settleAnimation) }
        scrolling.offsets[id] = offset
        relayout()
        return true
    }

    /// Assumed: the settle of a page turn or an alignment.
    private static let settleAnimation = Animation.spring(response: 0.35, dampingFraction: 1)

    /// The velocity at which a drag was released, in points per second, as
    /// the pointer moved.
    private func releaseVelocity(of samples: [(time: TimeInterval, point: CGPoint)]) -> CGSize {
        // Only the last moments before release count; see startMomentum.
        guard let release = samples.last else { return .zero }
        var moving = samples.filter { release.time - $0.time <= 0.15 }
        while moving.count > 1, moving[moving.count - 1].point == moving[moving.count - 2].point {
            moving.removeLast()
        }
        guard let first = moving.first, let last = moving.last, last.time > first.time else {
            return .zero
        }
        let dt = CGFloat(last.time - first.time)
        return CGSize(
            width: (last.point.x - first.point.x) / dt, height: (last.point.y - first.point.y) / dt)
    }
}
