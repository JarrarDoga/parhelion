#if canImport(Foundation)
import Foundation
#endif

/// A shape made of straight lines and quadratic curves.
public struct Path: Sendable {
    enum Element: Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
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

    /// Approximates a quarter circle with two quadratic curves.
    private mutating func quarter(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
        let middle = CGPoint(x: (control1.x + control2.x) / 2, y: (control1.y + control2.y) / 2)
        addQuadCurve(to: middle, control: control1)
        addQuadCurve(to: end, control: control2)
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
            case .close:
                finish()
            }
        }
        finish()
        return polygons
    }
}
