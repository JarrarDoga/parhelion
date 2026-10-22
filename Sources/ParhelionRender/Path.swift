#if canImport(Foundation)
import Foundation
#endif

/// A shape made of straight lines and quadratic and cubic curves.
public struct Path: Sendable {
    enum Element: Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case cubicCurve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    private(set) var elements: [Element] = []

    public init() {}

    public var isEmpty: Bool { elements.isEmpty }

    public mutating func move(to point: CGPoint) {
        elements.append(.move(point))
    }

    public mutating func addLine(to point: CGPoint) {
        elements.append(.line(point))
    }

    public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
        elements.append(.quadCurve(to: point, control: control))
    }

    /// Adds a cubic Bézier curve from the current point to `point`.
    public mutating func addCurve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.cubicCurve(to: point, control1: control1, control2: control2))
    }

    public mutating func closeSubpath() {
        elements.append(.close)
    }

    /// Appends every subpath of another path.
    public mutating func addPath(_ other: Path) {
        elements += other.elements
    }

    // MARK: - Shapes

    /// A rectangle.
    public init(_ rect: CGRect) {
        move(to: CGPoint(x: rect.minX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        closeSubpath()
    }

    /// An ellipse inscribed in a rectangle, approximated with eight
    /// quadratic curves. A reversed ellipse runs the other way around, so
    /// adding it inside another shape cuts a hole.
    public init(ellipseIn rect: CGRect, reversed: Bool = false) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = Double(rect.width) / 2
        let ry = Double(rect.height) / 2
        let segments = 8
        // A quadratic curve spanning an angle θ has its control point at
        // radius r / cos(θ / 2).
        let controlScale = 1 / cos(Double.pi / Double(segments))
        func point(_ angle: Double, _ scale: Double = 1) -> CGPoint {
            CGPoint(
                x: Double(center.x) + rx * scale * cos(angle),
                y: Double(center.y) + ry * scale * sin(angle)
            )
        }
        let direction = reversed ? -1.0 : 1.0
        move(to: point(0))
        for segment in 0..<segments {
            let start = direction * Double(segment) * 2 * .pi / Double(segments)
            let end = direction * Double(segment + 1) * 2 * .pi / Double(segments)
            addQuadCurve(to: point(end), control: point((start + end) / 2, controlScale))
        }
        closeSubpath()
    }

    /// A rectangle with rounded corners. A reversed one runs the other way
    /// around, so adding it inside another shape cuts a hole.
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, reversed: Bool) {
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        // Mirroring the shape top to bottom reverses its direction and, since
        // the shape is symmetric, leaves it where it was.
        self =
            reversed
            ? path.applying(
                scaleX: 1, scaleY: -1, translateX: 0, translateY: Double(rect.minY + rect.maxY))
            : path
    }

    /// A rectangle with rounded corners.
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        guard radius > 0 else {
            self = Path(rect)
            return
        }
        let k = radius * 0.4142  // tan(π/8): the control point offset for a quarter circle
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        move(to: CGPoint(x: minX + radius, y: minY))
        addLine(to: CGPoint(x: maxX - radius, y: minY))
        quarter(
            CGPoint(x: maxX - radius + k, y: minY),
            CGPoint(x: maxX, y: minY + radius - k),
            CGPoint(x: maxX, y: minY + radius)
        )
        addLine(to: CGPoint(x: maxX, y: maxY - radius))
        quarter(
            CGPoint(x: maxX, y: maxY - radius + k),
            CGPoint(x: maxX - radius + k, y: maxY),
            CGPoint(x: maxX - radius, y: maxY)
        )
        addLine(to: CGPoint(x: minX + radius, y: maxY))
        quarter(
            CGPoint(x: minX + radius - k, y: maxY),
            CGPoint(x: minX, y: maxY - radius + k),
            CGPoint(x: minX, y: maxY - radius)
        )
        addLine(to: CGPoint(x: minX, y: minY + radius))
        quarter(
            CGPoint(x: minX, y: minY + radius - k),
            CGPoint(x: minX + radius - k, y: minY),
            CGPoint(x: minX + radius, y: minY)
        )
        closeSubpath()
    }

    /// The shape of a rounded rectangle's corners.
    public enum CornerStyle: Sendable, Hashable {
        /// Quarter circles of the corner radius, meeting the straight edges
        /// with a sudden change of curvature.
        case circular
        /// Apple's "continuous" corners: the curve starts about 1.53 × the
        /// radius from the corner and its curvature grows from zero, so the
        /// edge flows into the corner without a visible joint. Each corner
        /// is three cubic curves, using the widely published approximation
        /// of iOS's shape (PaintCode, 2013), made symmetric about the
        /// corner's diagonal.
        ///
        /// When the side is too short for the curve to start 1.53 × the
        /// radius from the corner, the corner blends toward a circular one,
        /// as iOS's does, so a radius of half the height still makes a
        /// capsule.
        case continuous
    }

    /// How far from the corner, in multiples of the radius, a continuous
    /// corner leaves the straight edge.
    static let continuousExtent = 1.528_664_83

    /// How far from the corner a rounded rectangle's corner leaves each
    /// straight edge, after limiting the radius to fit the rectangle.
    static func cornerExtent(
        of rect: CGRect, cornerRadius: CGFloat, style: CornerStyle
    ) -> CGFloat {
        let half = min(rect.width, rect.height) / 2
        let radius = max(min(cornerRadius, half), 0)
        switch style {
        case .circular:
            return radius
        case .continuous:
            guard radius > 0 else { return 0 }
            let smoothing = continuousSmoothing(radius: Double(radius), half: Double(half))
            return CGFloat(Double(radius) * (1 + (continuousExtent - 1) * smoothing))
        }
    }

    /// How continuous a corner can be, from 0 (circular) to 1 (fully
    /// continuous), given half the shorter side.
    private static func continuousSmoothing(radius: Double, half: Double) -> Double {
        min(max((half / radius - 1) / (continuousExtent - 1), 0), 1)
    }

    /// A rectangle with rounded corners of the given style. A reversed one
    /// runs the other way around, so adding it inside another shape cuts a
    /// hole. With `.circular`, this is the same path as
    /// `Path(roundedRect:cornerRadius:reversed:)`.
    public init(
        roundedRect rect: CGRect, cornerRadius: CGFloat, style: CornerStyle,
        reversed: Bool = false
    ) {
        guard style == .continuous else {
            self = Path(roundedRect: rect, cornerRadius: cornerRadius, reversed: reversed)
            return
        }
        let half = min(rect.width, rect.height) / 2
        let radius = Double(min(cornerRadius, half))
        guard radius > 0 else {
            self = Path(roundedRect: rect, cornerRadius: 0, reversed: reversed)
            return
        }
        let smoothing = Self.continuousSmoothing(radius: radius, half: Double(half))
        // One corner, in multiples of the radius, as (distance from the
        // vertical edge, distance from the horizontal edge), starting on the
        // horizontal edge. Each point blends between the continuous corner
        // and a quarter circle written with the same five segments.
        let continuous: [(Double, Double)] = [
            (1.528_664_83, 0), (1.088_493_23, 0), (0.868_406_89, 0), (0.669_934_27, 0.065_496),
            (0.631_493_99, 0.074_911), (0.372_823_92, 0.169_059), (0.169_059, 0.372_823_92),
            (0.074_911, 0.631_493_99), (0.065_496, 0.669_934_27), (0, 0.868_406_89),
            (0, 1.088_493_23), (0, 1.528_664_83),
        ]
        let k = 0.447_715  // 1 − 0.552285: a quarter circle's cubic control points
        let circular: [(Double, Double)] = [
            (1, 0), (1, 0), (1, 0), (1, 0), (1, 0), (k, 0), (0, k), (0, 1), (0, 1), (0, 1),
            (0, 1), (0, 1),
        ]
        let corner = zip(continuous, circular).map { smooth, round in
            (
                (round.0 + (smooth.0 - round.0) * smoothing) * radius,
                (round.1 + (smooth.1 - round.1) * smoothing) * radius
            )
        }
        // `x` and `y` are the corner's vertex, and the signs point into the
        // rectangle. A backward corner starts on the vertical edge.
        func addCorner(x: Double, y: Double, signX: Double, signY: Double, backward: Bool) {
            func point(_ index: Int) -> CGPoint {
                let (a, b) = corner[backward ? corner.count - 1 - index : index]
                return CGPoint(x: x + signX * a, y: y + signY * b)
            }
            addLine(to: point(0))
            addCurve(to: point(3), control1: point(1), control2: point(2))
            addLine(to: point(4))
            addCurve(to: point(7), control1: point(5), control2: point(6))
            addLine(to: point(8))
            addCurve(to: point(11), control1: point(9), control2: point(10))
        }
        let minX = Double(rect.minX)
        let maxX = Double(rect.maxX)
        let minY = Double(rect.minY)
        let maxY = Double(rect.maxY)
        move(to: CGPoint(x: minX + corner[0].0, y: minY))
        // Clockwise: top right, bottom right, bottom left, top left.
        addCorner(x: maxX, y: minY, signX: -1, signY: 1, backward: false)
        addCorner(x: maxX, y: maxY, signX: -1, signY: -1, backward: true)
        addCorner(x: minX, y: maxY, signX: 1, signY: -1, backward: false)
        addCorner(x: minX, y: minY, signX: 1, signY: 1, backward: true)
        closeSubpath()
        if reversed {
            self = applying(
                scaleX: 1, scaleY: -1, translateX: 0, translateY: Double(rect.minY + rect.maxY))
        }
    }

    /// Approximates a quarter circle with two quadratic curves.
    private mutating func quarter(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
        let middle = CGPoint(x: (control1.x + control2.x) / 2, y: (control1.y + control2.y) / 2)
        addQuadCurve(to: middle, control: control1)
        addQuadCurve(to: end, control: control2)
    }

    /// The smallest rectangle that holds every point and control point, or
    /// `nil` for an empty path. Curves stay inside their control points, so
    /// the shape lies inside it.
    var controlBounds: CGRect? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        func add(_ point: CGPoint) {
            minX = min(minX, Double(point.x))
            minY = min(minY, Double(point.y))
            maxX = max(maxX, Double(point.x))
            maxY = max(maxY, Double(point.y))
        }
        for element in elements {
            switch element {
            case .move(let point), .line(let point): add(point)
            case .quadCurve(let point, let control):
                add(point)
                add(control)
            case .cubicCurve(let point, let control1, let control2):
                add(point)
                add(control1)
                add(control2)
            case .close: break
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Transforms

    /// The path with every point transformed.
    public func applying(
        scaleX: Double, scaleY: Double, translateX: Double, translateY: Double
    )
        -> Path
    {
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: Double(point.x) * scaleX + translateX,
                y: Double(point.y) * scaleY + translateY
            )
        }
        var result = Path()
        result.elements = elements.map { element in
            switch element {
            case .move(let point): .move(map(point))
            case .line(let point): .line(map(point))
            case .quadCurve(let point, let control):
                .quadCurve(to: map(point), control: map(control))
            case .cubicCurve(let point, let control1, let control2):
                .cubicCurve(to: map(point), control1: map(control1), control2: map(control2))
            case .close: .close
            }
        }
        return result
    }

    /// The path as closed polygons, with curves split into line segments no
    /// farther than `tolerance` from the true curve.
    func polygons(tolerance: Double) -> [[CGPoint]] {
        var polygons: [[CGPoint]] = []
        var current: [CGPoint] = []
        func finish() {
            if current.count > 2 { polygons.append(current) }
            current = []
        }
        for element in elements {
            switch element {
            case .move(let point):
                finish()
                current = [point]
            case .line(let point):
                current.append(point)
            case .quadCurve(let end, let control):
                guard let start = current.last else {
                    current = [end]
                    continue
                }
                // A quadratic curve split into n segments deviates from its
                // chords by at most |p0 - 2c + p2| / (8 n²).
                let dx = Double(start.x - 2 * control.x + end.x)
                let dy = Double(start.y - 2 * control.y + end.y)
                let deviation = (dx * dx + dy * dy).squareRoot()
                let count = max(1, Int((deviation / (8 * tolerance)).squareRoot().rounded(.up)))
                for step in 1...count {
                    let t = Double(step) / Double(count)
                    let u = 1 - t
                    current.append(
                        CGPoint(
                            x: u * u * Double(start.x) + 2 * u * t * Double(control.x) + t * t
                                * Double(end.x),
                            y: u * u * Double(start.y) + 2 * u * t * Double(control.y) + t * t
                                * Double(end.y)
                        )
                    )
                }
            case .cubicCurve(let end, let control1, let control2):
                guard let start = current.last else {
                    current = [end]
                    continue
                }
                // A cubic curve's second derivative is at most
                // 6 · max(|p0 - 2c1 + c2|, |c1 - 2c2 + p3|), and a curve split
                // into n segments deviates from its chords by at most an
                // eighth of that over n².
                let ax = Double(start.x - 2 * control1.x + control2.x)
                let ay = Double(start.y - 2 * control1.y + control2.y)
                let bx = Double(control1.x - 2 * control2.x + end.x)
                let by = Double(control1.y - 2 * control2.y + end.y)
                let bend = max((ax * ax + ay * ay).squareRoot(), (bx * bx + by * by).squareRoot())
                let count = max(1, Int((0.75 * bend / tolerance).squareRoot().rounded(.up)))
                for step in 1...count {
                    let t = Double(step) / Double(count)
                    let u = 1 - t
                    let a = u * u * u
                    let b = 3 * u * u * t
                    let c = 3 * u * t * t
                    let d = t * t * t
                    current.append(
                        CGPoint(
                            x: a * Double(start.x) + b * Double(control1.x) + c
                                * Double(control2.x) + d * Double(end.x),
                            y: a * Double(start.y) + b * Double(control1.y) + c
                                * Double(control2.y) + d * Double(end.y)
                        )
                    )
                }
            case .close:
                finish()
            }
        }
        finish()
        return polygons
    }
}
