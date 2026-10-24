import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

/// A triangle pointing up, as an app would write a shape of its own.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A shape whose path depends on a property, so its description must too.
private struct Inset: Shape {
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: amount, dy: amount))
    }
}

@MainActor
@Suite("Shapes and gradients")
struct ShapeTests {
    @Test("Shapes resolve to nodes named after their types, with their geometry and fill")
    func shapeNodes() {
        let host = ViewHost(
            VStack {
                Rectangle()
                RoundedRectangle(cornerRadius: 12)
                RoundedRectangle(cornerRadius: 4, style: .circular).fill(.red)
                Circle().fill(.blue)
                Capsule(style: .circular)
                Capsule()
                Ellipse().fill(.tint, style: FillStyle(eoFill: true))
            },
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Rectangle
                   ├─ RoundedRectangle cornerRadius=12
                   ├─ RoundedRectangle cornerRadius=4 fill=red style=circular
                   ├─ Circle fill=blue
                   ├─ Capsule style=circular
                   ├─ Capsule
                   └─ Ellipse eoFill=true fill=tint
                """)
        #expect(host.root.children[0].children[3].id == "VStack/3/Circle")
    }

    @Test("A shape fills the space it is offered, and 10 points without a proposal")
    func shapeSizes() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Rectangle().frame(width: 50, height: 20)
                Circle().fill(.red).frame(width: 30)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.children[0].frame?.size == CGSize(width: 50, height: 20))
        #expect(stack.children[1].frame?.width == 30)
        let capsule = ViewNode(id: "Capsule", kind: "Capsule")
        #expect(
            LayoutEngine(device: square).sizeThatFits(capsule, .unspecified, parentAxis: nil)
                == CGSize(width: 10, height: 10))
    }

    @Test("A shape of an app's own type records its description and draws its path")
    func customShape() {
        let host = ViewHost(
            Triangle().fill(.blue).frame(width: 100, height: 100),
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ Triangle frame(width: 100, height: 100) fill=blue shape=Triangle()
                """)
        let frame = host.render(scale: 2)
        // The triangle spans (50, 50) to (150, 150), its apex at the top.
        #expect(components(frame.color(at: CGPoint(x: 100, y: 140))) == [0, 136, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 60, y: 60))) == [255, 255, 255, 255])
    }

    @Test("A custom shape's description includes its properties, so each draws its own path")
    func customShapesWithProperties() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Inset(amount: 0).fill(.red).frame(width: 100, height: 100)
                Inset(amount: 40).fill(.red).frame(width: 100, height: 100)
            },
            device: square
        )
        let shapes = host.root.children[0].children
        #expect(shapes[0].attributes["shape"] == "Inset(amount: 0.0)")
        #expect(shapes[1].attributes["shape"] == "Inset(amount: 40.0)")
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 10, y: 60))) == [255, 56, 60, 255])
        #expect(components(frame.color(at: CGPoint(x: 110, y: 60))) == [255, 255, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 150, y: 100))) == [255, 56, 60, 255])
    }

    @Test("A path draws itself as a view, recorded as SVG path data")
    func pathView() {
        let host = ViewHost(
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: 40, height: 40))
                path.addRect(CGRect(x: 10, y: 10, width: 20, height: 20))
            }
            .fill(.red, style: FillStyle(eoFill: true)),
            device: square
        )
        let node = host.root.children[0]
        #expect(node.kind == "Path")
        #expect(node.attributes["path"] == "M0 0L40 0L40 40L0 40ZM10 10L30 10L30 30L10 30Z")
        let frame = host.render(scale: 1)
        // A path ignores its frame, so it draws at the top-leading corner,
        // and the even-odd rule leaves the inner square empty.
        #expect(components(frame.color(at: CGPoint(x: 5, y: 5))) == [255, 56, 60, 255])
        #expect(components(frame.color(at: CGPoint(x: 20, y: 20))) == [255, 255, 255, 255])
    }

    @Test("A shape takes the foreground style when no fill is given")
    func foregroundFill() {
        let host = ViewHost(
            Circle().foregroundStyle(.green).frame(width: 100, height: 60),
            device: square
        )
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 100))) == [52, 199, 89, 255])
        // The circle is as wide as the frame is tall, so the frame's corner
        // is empty.
        #expect(components(frame.color(at: CGPoint(x: 55, y: 75))) == [255, 255, 255, 255])
    }

    @Test("A linear gradient view records its stops and points and fills its frame")
    func gradientView() {
        let host = ViewHost(
            LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
                .frame(width: 100, height: 100),
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ LinearGradient frame(width: 100, height: 100) endPoint=bottom gradient=red 0, blue 1 startPoint=top
                """)
        let frame = host.render(scale: 1)
        let top = frame.color(at: CGPoint(x: 100, y: 50))
        let bottom = frame.color(at: CGPoint(x: 100, y: 149))
        #expect(top.red > 250 && top.blue < 70)
        #expect(bottom.blue > 250 && bottom.red < 10)
    }

    @Test("A gradient is a shape style for backgrounds and fills")
    func gradientStyle() {
        let gradient = LinearGradient(
            stops: [
                Gradient.Stop(color: .red, location: 0),
                Gradient.Stop(color: Color(red: 0, green: 0, blue: 1).opacity(0.5), location: 1),
            ],
            startPoint: .leading, endPoint: UnitPoint(x: 1, y: 0.25))
        let host = ViewHost(
            VStack(spacing: 0) {
                Color.clear.frame(width: 100, height: 50).background(gradient)
                Rectangle().fill(
                    .linearGradient(colors: [.green, .red], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 100, height: 50)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(
            stack.children[0].modifiers.last?.outlineDescription
                == "background(linearGradient(red 0, rgba(0,0,1,1)@0.5 1, leading, 1 0.25))")
        #expect(
            stack.children[1].attributes["fill"]
                == "linearGradient(green 0, red 1, top, bottom)")
        let frame = host.render(scale: 1)
        let left = frame.color(at: CGPoint(x: 50, y: 75))
        #expect(left.red > 250 && left.green < 70)
        let right = frame.color(at: CGPoint(x: 149, y: 60))
        // Blue at half opacity over white.
        #expect(right.blue >= 250 && right.red > 110 && right.red < 145)
        let top = frame.color(at: CGPoint(x: 100, y: 100))
        #expect(top.green > 190 && top.red < 70)
    }

    @Test("Shapes, gradients, backgrounds, and effects resolve colors for the node's scheme")
    func darkColors() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Circle().fill(.red).frame(width: 40, height: 40)
                Color.clear.frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [.green, .green], startPoint: .top, endPoint: .bottom))
                Color.clear.frame(width: 40, height: 40)
                    .overlay(.orange, in: Rectangle())
                    .clipShape(Circle())
            },
            device: square
        )
        host.colorScheme = .dark
        #expect(host.root.attributes["colorScheme"] == "dark")
        let frame = host.render(scale: 1)
        func expectColor(_ point: CGPoint, _ name: String) {
            let expected = ColorPalette.color(named: name, in: .dark)
            #expect(
                components(frame.color(at: point))
                    == [expected.red, expected.green, expected.blue, 255], "\(name)")
        }
        expectColor(CGPoint(x: 100, y: 60), "red")
        expectColor(CGPoint(x: 100, y: 100), "green")
        expectColor(CGPoint(x: 100, y: 140), "orange")
        // The dark red is not the light one.
        #expect(ColorPalette.color(named: "red", in: .dark) != ColorPalette.color(named: "red"))
    }

    @Test("Style descriptions read back colors and gradients")
    func styleDescriptions() {
        #expect(StyleDescription("blue@0.5") == .color("blue@0.5"))
        #expect(StyleDescription("foreground") == .foreground)
        #expect(
            StyleDescription("linearGradient(rgba(1,0,0,1) 0, blue@0.5 0.25, tint 1, top, 0.5 1)")
                == .linearGradient(
                    stops: [
                        .init(color: "rgba(1,0,0,1)", location: 0),
                        .init(color: "blue@0.5", location: 0.25),
                        .init(color: "tint", location: 1),
                    ],
                    start: .top, end: .bottom))
        #expect(StyleDescription("linearGradient(nonsense)") == .color("linearGradient(nonsense)"))
        #expect(
            Gradient(colors: [.red, .green, .blue]).stopsDescription == "red 0, green 0.5, blue 1")
    }

    @Test("Arcs follow SwiftUI's angles: clockwise means decreasing angles")
    func arcs() {
        var path = Path()
        path.addArc(
            center: CGPoint(x: 50, y: 50), radius: 10, startAngle: .zero,
            endAngle: .degrees(90), clockwise: false)
        let end = path.currentPoint
        #expect(abs((end?.x ?? 0) - 50) < 0.001 && abs((end?.y ?? 0) - 60) < 0.001)

        var clockwise = Path()
        clockwise.addArc(
            center: .zero, radius: 10, startAngle: .zero, endAngle: .degrees(90),
            clockwise: true)
        // Three quarter turns the other way, so the curve passes through
        // (0, -10).
        #expect(clockwise.svgPathData.contains("C") && clockwise.svgPathData.contains(" -10"))
        #expect(Angle(degrees: 180).radians == .pi)
    }
}
