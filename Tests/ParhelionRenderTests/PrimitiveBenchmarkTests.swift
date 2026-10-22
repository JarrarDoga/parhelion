import Foundation
import Testing

@testable import ParhelionRender

/// The average time of `body` over `count` runs, each on a fresh copy of
/// `canvas`, not counting the copy.
private func measure(
    _ canvas: Canvas, count: Int = 20, _ body: (inout Canvas) -> Void
) -> Duration {
    let clock = ContinuousClock()
    var total = Duration.zero
    for _ in 0..<count {
        var copy = canvas
        copy.fill(CGRect(x: 0, y: 0, width: 1, height: 1), color: .black)  // Copy the pixels now.
        total += clock.measure { body(&copy) }
    }
    return total / count
}

@Test(
    "Primitive timing",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func primitiveTiming() {
    // A phone screen at 3× with busy content, the worst case for blurs.
    let canvas = GlassScenes.busyBackground(width: 402, height: 874, scale: 3)
    let capsule = CGRect(x: 300, y: 70, width: 67, height: 44)
    let alert = CGRect(x: 51, y: 355, width: 300, height: 162)
    let shadow = RGBA(red: 0, green: 0, blue: 0, alpha: 13)
    let results: [(String, Duration)] = [
        (
            "44-pt capsule shadow, blur 15",
            measure(canvas) {
                $0.drawShadow(
                    of: capsule, cornerRadius: 22, color: shadow,
                    offset: CGSize(width: 0, height: 8), blur: 15)
            }
        ),
        (
            "alert shadow, blur 46",
            measure(canvas) {
                $0.drawShadow(
                    of: alert, cornerRadius: 34, style: .continuous,
                    color: RGBA(red: 0, green: 0, blue: 0, alpha: 64),
                    offset: CGSize(width: 0, height: 18), blur: 46)
            }
        ),
        (
            "44-pt capsule blur 6, saturation 2",
            measure(canvas) { $0.blur(capsule, cornerRadius: 22, radius: 6, saturation: 2) }
        ),
        (
            "alert blur 30, saturation 1.4",
            measure(canvas) {
                $0.blur(alert, cornerRadius: 34, style: .continuous, radius: 30, saturation: 1.4)
            }
        ),
        (
            "alert continuous fill",
            measure(canvas) {
                $0.fill(
                    alert, cornerRadius: 34, style: .continuous,
                    color: RGBA(red: 255, green: 255, blue: 255, alpha: 179))
            }
        ),
        (
            "alert circular fill",
            measure(canvas) {
                $0.fill(
                    alert, cornerRadius: 34,
                    color: RGBA(red: 255, green: 255, blue: 255, alpha: 179))
            }
        ),
        (
            "44-pt continuous capsule fill",
            measure(canvas) {
                $0.fill(
                    capsule, cornerRadius: 22, style: .continuous,
                    color: RGBA(red: 255, green: 255, blue: 255, alpha: 179))
            }
        ),
        (
            "alert 0.5-pt ring, plus-darker",
            measure(canvas) {
                $0.blendMode = .plusDarker
                $0.stroke(
                    alert, cornerRadius: 34, style: .continuous, lineWidth: 0.5,
                    alignment: .outside, color: RGBA(red: 219, green: 219, blue: 219))
            }
        ),
        (
            "77-pt scroll edge gradient",
            measure(canvas) {
                $0.fill(
                    CGRect(x: 0, y: 0, width: 402, height: 77),
                    gradient: Canvas.LinearGradient(
                        colors: [RGBA(red: 255, green: 255, blue: 255, alpha: 153), .clear],
                        start: .zero, end: CGPoint(x: 0, y: 77)))
            }
        ),
        (
            "whole small glass button",
            measure(canvas) {
                GlassScenes.smallGlass(&$0, capsule, label: "")
            }
        ),
        (
            "whole alert",
            measure(canvas, count: 5) { GlassScenes.alert(&$0, alert) }
        ),
    ]
    for (name, duration) in results {
        print("BENCH \(name): \(duration)")
    }
}
