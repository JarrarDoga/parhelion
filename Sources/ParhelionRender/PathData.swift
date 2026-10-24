#if canImport(Foundation)
import Foundation
#endif

extension Path {
    /// The path as SVG path data, with absolute commands and coordinates
    /// rounded to thousandths: `M0 0L10 0L10 10Z`. `Path(svgPathData:)`
    /// reads it back.
    public var svgPathData: String {
        func number(_ value: CGFloat) -> String {
            let rounded = (Double(value) * 1000).rounded() / 1000
            if rounded == rounded.rounded() { return String(Int(rounded)) }
            var text = String(format: "%.3f", rounded)
            while text.hasSuffix("0") { text.removeLast() }
            return text
        }
        func point(_ point: CGPoint) -> String {
            "\(number(point.x)) \(number(point.y))"
        }
        var data = ""
        for element in elements {
            switch element {
            case .move(let to): data += "M" + point(to)
            case .line(let to): data += "L" + point(to)
            case .quadCurve(let to, let control): data += "Q" + point(control) + " " + point(to)
            case .cubicCurve(let to, let control1, let control2):
                data += "C" + point(control1) + " " + point(control2) + " " + point(to)
            case .close: data += "Z"
            }
        }
        return data
    }

    /// The smallest rectangle that holds every point and control point of
    /// the path, or `nil` for an empty path.
    public var boundingRect: CGRect? { controlBounds }

    /// The point the next line or curve starts from, or `nil` for an empty
    /// path. After a subpath is closed, it is the subpath's first point.
    public var currentPoint: CGPoint? {
        var start: CGPoint?
        var current: CGPoint?
        for element in elements {
            switch element {
            case .move(let point):
                start = point
                current = point
            case .line(let point), .quadCurve(let point, _), .cubicCurve(let point, _, _):
                current = point
            case .close:
                current = start
            }
        }
        return current
    }
}
