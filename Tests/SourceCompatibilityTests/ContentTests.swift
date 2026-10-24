// Written the way an iOS app is written, against `import SwiftUI`, to check
// that shapes, paths, gradients, the styling modifiers, images, AsyncImage,
// and grids compile as they do with Apple's SDK.

import SwiftUI
import Testing

private struct Wedge: Shape {
    var angle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center, radius: min(rect.width, rect.height) / 2, startAngle: .zero,
            endAngle: angle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct Gallery: View {
    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Rectangle().fill(.red)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange)
                    Circle().fill(.green, style: FillStyle(eoFill: true, antialiased: true))
                    Capsule(style: .circular).fill(.blue)
                    Ellipse()
                    Wedge(angle: .degrees(120)).fill(.purple)
                    Path { path in
                        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
                        path.addEllipse(in: CGRect(x: 2, y: 2, width: 6, height: 6))
                        path.addRoundedRect(
                            in: CGRect(x: 0, y: 0, width: 4, height: 4),
                            cornerSize: CGSize(width: 1, height: 1))
                        path.addLines([.zero, CGPoint(x: 3, y: 3)])
                    }
                }
                .frame(height: 40)

                LinearGradient(
                    gradient: Gradient(colors: [.indigo, .pink]), startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                Text("Gradient")
                    .foregroundStyle(
                        .linearGradient(
                            stops: [
                                Gradient.Stop(color: .red, location: 0),
                                Gradient.Stop(color: .blue, location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                    )
                    .background(
                        LinearGradient(
                            colors: [.white, .gray], startPoint: .topLeading,
                            endPoint: UnitPoint(x: 1, y: 1)))

                Image(systemName: "star.fill")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                    }
                    .overlay(.white.opacity(0.2), in: Capsule())
                    .clipShape(RoundedRectangle(cornerRadius: 8), style: FillStyle())
                    .shadow(radius: 4)
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    .scaleEffect(1.2)
                    .scaleEffect(x: -1, anchor: .leading)
                    .scaleEffect(CGSize(width: 1, height: 1), anchor: .center)
                Image("Photo")
                    .resizable(capInsets: EdgeInsets(), resizingMode: .tile)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipped()
                Image("Photo", bundle: .main).scaledToFill()
                Color.teal.aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)

                // File URLs, so that the test never reaches the network.
                AsyncImage(url: URL(string: "file:///nonexistent/a.png"))
                AsyncImage(url: nil, scale: 2) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                AsyncImage(
                    url: URL(string: "file:///nonexistent/b.png"),
                    transaction: Transaction(animation: .easeInOut)
                ) { phase in
                    switch phase {
                    case .empty: Color.gray
                    case .success(let image): image.resizable()
                    case .failure(let error): Text(error.localizedDescription)
                    @unknown default: EmptyView()
                    }
                }
                AsyncImage(request: URLRequest(url: URL(fileURLWithPath: "/nonexistent/c.png")))
                    .asyncImageURLSession(.shared)

                LazyVGrid(
                    columns: columns, alignment: .leading, spacing: 12,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(0..<6) { index in
                        RoundedRectangle(cornerRadius: 8).fill(.blue).frame(height: 60)
                    }
                }
                LazyHGrid(rows: [
                    GridItem(.fixed(40)), GridItem(.flexible(minimum: 20, maximum: 80)),
                ]) {
                    Text("A")
                    Text("B")
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow(alignment: .top) {
                        Text("Name").gridColumnAlignment(.trailing)
                        Text("Value")
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("Wide").gridCellColumns(2).gridCellAnchor(.center)
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("Content source compatibility")
struct ContentTests {
    @Test("Shapes, images, and grids compile under `import SwiftUI` and resolve to their nodes")
    func content() {
        let host = ViewHost(Gallery())
        let kinds = Set(host.root.allNodes.map(\.kind))
        for kind in [
            "Rectangle", "RoundedRectangle", "Circle", "Capsule", "Ellipse", "Wedge", "Path",
            "LinearGradient", "Image", "Overlay", "AsyncImage", "LazyVGrid", "LazyHGrid", "Grid",
            "GridRow",
        ] {
            #expect(kinds.contains(kind), "\(kind)")
        }
    }
}
