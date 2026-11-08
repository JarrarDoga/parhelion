import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test", screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets())

/// A stand-in for an export of the SF Symbols app: a square per weight, in
/// the layout of an export (one group per weight and scale), and nothing
/// from Apple.
private func export(squares: [String: Int], scale: String = "M", extra: String = "") -> String {
    var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\">\n<g id=\"Notes\"><rect/></g>\n"
    for (weight, side) in squares {
        let group = "\(weight)-\(scale)"
        svg += "<g id=\"\(group)\" transform=\"matrix(1 0 0 1 10 90)\">"
        svg += "<path d=\"M0 0H\(side)V\(-side)H0Z\"/>\(extra)</g>\n"
    }
    return svg + "</svg>\n"
}

private func makeFolder(_ files: [String: String]) throws -> String {
    let directory = NSTemporaryDirectory() + "parhelion-symbols-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (name, contents) in files {
        try contents.write(toFile: directory + "/" + name, atomically: true, encoding: .utf8)
    }
    return directory
}

/// Points Parhelion at a folder of exports for the length of a body.
@MainActor
private func withUserSymbols<T>(_ files: [String: String], _ body: () throws -> T) throws -> T {
    let directory = try makeFolder(files)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    setenv(SymbolTemplate.environmentVariable, directory, 1)
    defer { unsetenv(SymbolTemplate.environmentVariable) }
    return try body()
}

@MainActor
@Suite("The user's own SF Symbols", .serialized)
struct UserSymbolsTests {
    @Test("The template reader takes the medium group of each weight")
    func template() {
        let svg =
            export(squares: ["Regular": 40, "Bold": 60])
            + export(squares: ["Regular": 99], scale: "S")
        let paths = SymbolTemplate.pathData(inSVG: svg)
        #expect(Set(paths.keys) == [3, 6])
        #expect(paths[3] == "M0 0H40V-40H0Z")
        #expect(SymbolTemplate.outlines(inSVG: svg)[6]?.boundingRect?.width == 60)
        #expect(
            SymbolTemplate.pathData(inSVG: "<svg><g id=\"Regular-M\"><path d=\"M\"/>").count == 1)
        #expect(SymbolTemplate.pathData(inSVG: "not svg").isEmpty)
    }

    @Test("A group that holds other groups and several paths keeps all of its data")
    func nestedGroups() {
        let svg =
            "<svg><g id=\"Regular-M\"><g><path d=\"M0 0H10V-10Z\"/></g>"
            + "<path fill=\"none\" d=\"M20 0H30V-10Z\"/></g>"
            + "<g id=\"Bold-M\"><path d=\"M1 1Z\"/></g></svg>"
        let paths = SymbolTemplate.pathData(inSVG: svg)
        #expect(paths[3] == "M0 0H10V-10Z M20 0H30V-10Z")
        #expect(paths[6] == "M1 1Z")
    }

    @Test("Symbols from the folder come before Phosphor, and the tree says so")
    func sourceOrder() throws {
        let files = [
            "test.synthetic.svg": export(squares: ["Regular": 40, "Bold": 60]),
            "star.svg": export(squares: ["Regular": 50]),
        ]
        try withUserSymbols(files) {
            #expect(SymbolLibrary.source(of: "test.synthetic") == .sfSymbols)
            #expect(SymbolLibrary.source(of: "star") == .sfSymbols)
            // Not in the folder: Phosphor, then the placeholder.
            #expect(SymbolLibrary.source(of: "house") == .phosphor)
            #expect(SymbolLibrary.source(of: "no.such.symbol") == .placeholder)
            #expect(SymbolLibrary.source(of: "chevron.right") == .builtIn)

            let host = ViewHost(
                VStack {
                    Image(systemName: "test.synthetic")
                    Image(systemName: "house")
                    Image(systemName: "no.such.symbol")
                },
                device: screen)
            #expect(
                host.root.outline() == """
                    Root
                    └─ VStack
                       ├─ Image symbolSource=sfSymbols systemName=test.synthetic
                       ├─ Image systemName=house
                       └─ Image missingSymbol=true systemName=no.such.symbol
                    """)
        }
    }

    @Test("Without a folder, names draw with Phosphor as before")
    func withoutFolder() throws {
        setenv(SymbolTemplate.environmentVariable, "/nonexistent/parhelion-symbols", 1)
        defer { unsetenv(SymbolTemplate.environmentVariable) }
        #expect(SymbolLibrary.source(of: "star") == .phosphor)
        #expect(SymbolLibrary.resolve("star").source == .phosphor)
    }

    @Test("The font weight picks the weight; a missing one is interpolated or the nearest")
    func weights() throws {
        let files = ["test.weighted.svg": export(squares: ["Regular": 40, "Bold": 60])]
        try withUserSymbols(files) {
            func width(_ weight: Font.Weight) -> Double {
                Double(
                    SymbolLibrary.resolve("test.weighted", weight: weight).path.boundingRect?
                        .width ?? 0)
            }
            #expect(abs(width(.regular) - 0.4) < 0.001)
            #expect(abs(width(.bold) - 0.6) < 0.001)
            // Semibold lies between regular and bold, two thirds of the way.
            // Outside the two, the nearest stands in.
            #expect(abs(width(.semibold) - (0.4 + 0.2 * 2 / 3)) < 0.001)
            #expect(abs(width(.light) - 0.4) < 0.001)
            #expect(abs(width(.ultraLight) - 0.4) < 0.001)
            #expect(abs(width(.black) - 0.6) < 0.001)
        }
    }

    @Test("The fill variant uses the .fill symbol when the folder has it")
    func fill() throws {
        let files = [
            "test.shape.svg": export(squares: ["Regular": 40]),
            "test.shape.fill.svg": export(squares: ["Regular": 70]),
            "test.only.svg": export(squares: ["Regular": 40]),
        ]
        try withUserSymbols(files) {
            func width(_ name: String, fill: Bool = false) -> Double {
                Double(SymbolLibrary.resolve(name, fill: fill).path.boundingRect?.width ?? 0)
            }
            #expect(abs(width("test.shape") - 0.4) < 0.001)
            #expect(abs(width("test.shape.fill") - 0.7) < 0.001)
            #expect(abs(width("test.shape", fill: true) - 0.7) < 0.001)
            #expect(abs(width("test.only", fill: true) - 0.4) < 0.001)
        }
    }

    @Test("An unreadable or empty file is not a symbol")
    func unreadable() throws {
        let files = [
            "test.empty.svg": "<svg></svg>",
            "test.bad.svg": "<svg><g id=\"Regular-M\"><path d=\"M0 0Hx\"/></g></svg>",
        ]
        try withUserSymbols(files) {
            #expect(SymbolLibrary.source(of: "test.empty") == .placeholder)
            #expect(SymbolLibrary.source(of: "test.bad") == .placeholder)
        }
    }

    @Test("The symbol is drawn, centered, at the size of its font")
    func drawn() throws {
        let files = ["test.drawn.svg": export(squares: ["Regular": 50])]
        try withUserSymbols(files) {
            let host = ViewHost(
                Image(systemName: "test.drawn").frame(width: 200, height: 200)
                    .foregroundStyle(Color.red),
                device: screen)
            let frame = host.render(scale: 1)
            // The square is half the 17-point font's side: 8.5 points wide
            // around the center.
            let inside = frame.color(at: CGPoint(x: 100, y: 100))
            #expect(inside.red > 200 && inside.green < 60)
            let outside = frame.color(at: CGPoint(x: 120, y: 100))
            #expect(outside.green > 200)
        }
    }

    @Test func currentExportsHoldThreeSmallWeights() {
        // Current templates hold Ultralight, Regular, and Black at small
        // scale. The others are interpolated, and outlines grow to medium.
        let svg =
            "<svg><g id=\"Ultralight-S\"><path d=\"M0 0H10V-10H0Z\"/></g>"
            + "<g id=\"Regular-S\"><path d=\"M0 0H40V-40H0Z\"/></g>"
            + "<g id=\"Black-S\"><path d=\"M0 0H90V-90H0Z\"/></g></svg>"
        #expect(SymbolTemplate.scaleName(inSVG: svg) == "S")
        let outlines = SymbolTemplate.outlines(inSVG: svg)
        #expect(outlines.count == SymbolTemplate.weightNames.count)
        let width = { (index: Int) in Double(outlines[index]?.boundingRect?.width ?? 0) }
        #expect(abs(width(3) - 40 / 0.78) < 0.01)
        // Bold (6) is three fifths of the way from Regular (3) to Black (8).
        #expect(abs(width(6) - 70 / 0.78) < 0.01)
        #expect(width(1) > width(0) && width(1) < width(3))
    }

    @Test func outlinesThatDifferAreNotInterpolated() {
        #expect(SymbolTemplate.interpolate("M0 0H10Z", "M0 0H10V5Z", 0.5) == nil)
        let halfway = SymbolTemplate.interpolate("M0-1L2.5 3", "M2-3L4.5 5", 0.5)
        #expect(halfway.map { Path(svgPathData: $0) != nil } == true)
        #expect(halfway?.split(separator: " ").count == 6)
    }
}
