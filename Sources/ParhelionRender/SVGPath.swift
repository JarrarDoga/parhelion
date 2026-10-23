#if canImport(Foundation)
import Foundation
#endif

extension Path {
    /// A path from SVG path data, the `d` attribute of an SVG `path`
    /// element, in the same coordinates: x to the right and y down.
    ///
    /// Every command is supported, in its absolute and relative forms:
    /// moves, lines, horizontal and vertical lines, cubic and quadratic
    /// curves and their smooth forms, elliptical arcs, and close. Arcs become
    /// cubic curves. Returns `nil` if the data is malformed.
    public init?(svgPathData data: some StringProtocol) {
        var parser = SVGPathParser(bytes: Array(data.utf8))
        guard let path = parser.parse() else { return nil }
        self = path
    }
}

/// Reads SVG path data, following the grammar in the SVG specification's
/// path data section.
private struct SVGPathParser {
    let bytes: [UInt8]
    var index = 0
    var path = Path()
    /// The current point, and the start of the current subpath, which a
    /// close returns to.
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    /// The second control point of the last cubic curve, or the control
    /// point of the last quadratic one, which smooth curves reflect.
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?
    /// Whether the last command closed a subpath, so that a drawing command
    /// after it starts a new one.
    var isClosed = false

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parse() -> Path? {
        var command: UInt8?
        while true {
            skipSeparators()
            guard index < bytes.count else { break }
            let byte = bytes[index]
            if Self.commands.contains(byte) {
                command = byte
                index += 1
            } else if command == nil || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z")
            {
                // Numbers must follow a command that takes them.
                return nil
            }
            guard let current = command, apply(current) else { return nil }
            // Coordinates after a move are lines.
            if current == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
            if current == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
        }
        return path
    }

    private static let commands = Set("MmLlHhVvCcSsQqTtAaZz".utf8)

    /// Reads one command's arguments and adds it to the path.
    private mutating func apply(_ command: UInt8) -> Bool {
        let isRelative = command >= UInt8(ascii: "a")
        func point(_ x: Double, _ y: Double) -> CGPoint {
            isRelative
                ? CGPoint(x: Double(current.x) + x, y: Double(current.y) + y) : CGPoint(x: x, y: y)
        }
        var cubicControl: CGPoint?
        var quadControl: CGPoint?
        switch command | 0x20 {
        case UInt8(ascii: "m"):
            guard let x = number(), let y = number() else { return false }
            current = point(x, y)
            subpathStart = current
            path.move(to: current)
            isClosed = false
        case UInt8(ascii: "z"):
            path.closeSubpath()
            current = subpathStart
            isClosed = true
        case UInt8(ascii: "l"):
            guard let x = number(), let y = number() else { return false }
            line(to: point(x, y))
        case UInt8(ascii: "h"):
            guard let x = number() else { return false }
            line(to: CGPoint(x: isRelative ? Double(current.x) + x : x, y: Double(current.y)))
        case UInt8(ascii: "v"):
            guard let y = number() else { return false }
            line(to: CGPoint(x: Double(current.x), y: isRelative ? Double(current.y) + y : y))
        case UInt8(ascii: "c"):
            guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(),
                let x = number(), let y = number()
            else { return false }
            let control1 = point(x1, y1)
            let control2 = point(x2, y2)
            curve(to: point(x, y), control1: control1, control2: control2)
            cubicControl = control2
        case UInt8(ascii: "s"):
            guard let x2 = number(), let y2 = number(), let x = number(), let y = number()
            else { return false }
            let control1 = reflection(of: lastCubicControl)
            let control2 = point(x2, y2)
            curve(to: point(x, y), control1: control1, control2: control2)
            cubicControl = control2
        case UInt8(ascii: "q"):
            guard let x1 = number(), let y1 = number(), let x = number(), let y = number()
            else { return false }
            let control = point(x1, y1)
            quadCurve(to: point(x, y), control: control)
            quadControl = control
        case UInt8(ascii: "t"):
            guard let x = number(), let y = number() else { return false }
            let control = reflection(of: lastQuadControl)
            quadCurve(to: point(x, y), control: control)
            quadControl = control
        case UInt8(ascii: "a"):
            guard let rx = number(), let ry = number(), let rotation = number(),
                let largeArc = flag(), let sweep = flag(), let x = number(), let y = number()
            else { return false }
            arc(
                to: point(x, y), radii: (abs(rx), abs(ry)), rotation: rotation * .pi / 180,
                largeArc: largeArc, sweep: sweep)
        default:
            return false
        }
        lastCubicControl = cubicControl
        lastQuadControl = quadControl
        return true
    }

    /// The reflection of a control point about the current point, or the
    /// current point when the last command was not a curve of the same kind.
    private func reflection(of control: CGPoint?) -> CGPoint {
        guard let control else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    /// Starts a new subpath at the start of the last one if the last command
    /// closed it, as SVG does for drawing commands after a close.
    private mutating func continueSubpath() {
        guard isClosed else { return }
        path.move(to: current)
        isClosed = false
    }

    private mutating func line(to point: CGPoint) {
        continueSubpath()
        path.addLine(to: point)
        current = point
    }

    private mutating func curve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        continueSubpath()
        path.addCurve(to: point, control1: control1, control2: control2)
        current = point
    }

    private mutating func quadCurve(to point: CGPoint, control: CGPoint) {
        continueSubpath()
        path.addQuadCurve(to: point, control: control)
        current = point
    }

    /// Adds an elliptical arc as cubic curves of at most a quarter turn each,
    /// converting SVG's endpoint form to the center form as the
    /// specification's implementation notes describe.
    private mutating func arc(
        to end: CGPoint, radii: (Double, Double), rotation: Double, largeArc: Bool, sweep: Bool
    ) {
        let start = current
        guard start != end else { return }
        var (rx, ry) = radii
        guard rx > 0, ry > 0 else {
            line(to: end)
            return
        }
        continueSubpath()
        let cosine = cos(rotation)
        let sine = sin(rotation)
        // The start point in the ellipse's own axes, relative to the midpoint.
        let dx = Double(start.x - end.x) / 2
        let dy = Double(start.y - end.y) / 2
        let x1 = cosine * dx + sine * dy
        let y1 = -sine * dx + cosine * dy
        // Radii too small to reach the end point grow until they just do.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let sign: Double = largeArc == sweep ? -1 : 1
        let coefficient = sign * max(numerator / denominator, 0).squareRoot()
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx
        let center = CGPoint(
            x: cosine * cx1 - sine * cy1 + Double(start.x + end.x) / 2,
            y: sine * cx1 + cosine * cy1 + Double(start.y + end.y) / 2)
        let startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var sweepAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - startAngle
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }

        func pointOnEllipse(_ angle: Double) -> CGPoint {
            let x = rx * cos(angle)
            let y = ry * sin(angle)
            return CGPoint(
                x: Double(center.x) + cosine * x - sine * y,
                y: Double(center.y) + sine * x + cosine * y)
        }
        func tangent(_ angle: Double) -> (x: Double, y: Double) {
            let x = -rx * sin(angle)
            let y = ry * cos(angle)
            return (cosine * x - sine * y, sine * x + cosine * y)
        }
        let segments = max(Int((abs(sweepAngle) / (.pi / 2)).rounded(.up)), 1)
        let step = sweepAngle / Double(segments)
        // A cubic curve spanning an angle θ of a circle has its control points
        // 4/3 · tan(θ/4) of the radius along the tangents.
        let k = 4.0 / 3 * tan(step / 4)
        var angle = startAngle
        for segment in 0..<segments {
            let next = angle + step
            let from = pointOnEllipse(angle)
            let to = segment == segments - 1 ? end : pointOnEllipse(next)
            let t1 = tangent(angle)
            let t2 = tangent(next)
            path.addCurve(
                to: to,
                control1: CGPoint(x: Double(from.x) + k * t1.x, y: Double(from.y) + k * t1.y),
                control2: CGPoint(x: Double(to.x) - k * t2.x, y: Double(to.y) - k * t2.y))
            angle = next
        }
        current = end
    }

    // MARK: - Tokens

    private mutating func skipSeparators() {
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: " "), UInt8(ascii: ","), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
                UInt8(ascii: "\r"):
                index += 1
            default:
                return
            }
        }
    }

    /// Reads a number such as `12`, `-.5`, or `1e-3`. A second decimal point
    /// starts the next number, so `.5.5` is two numbers.
    private mutating func number() -> Double? {
        skipSeparators()
        let start = index
        func digits() {
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"),
                bytes[index] <= UInt8(ascii: "9")
            {
                index += 1
            }
        }
        if index < bytes.count,
            bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+")
        {
            index += 1
        }
        digits()
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            digits()
        }
        if index < bytes.count,
            bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E")
        {
            index += 1
            if index < bytes.count,
                bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+")
            {
                index += 1
            }
            digits()
        }
        guard index > start else { return nil }
        return Double(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    /// Reads an arc flag, a single `0` or `1`, which may run into the next
    /// number without a separator.
    private mutating func flag() -> Bool? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        switch bytes[index] {
        case UInt8(ascii: "0"): return false
        case UInt8(ascii: "1"): return true
        default: return nil
        }
    }
}
