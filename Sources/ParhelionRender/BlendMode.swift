#if canImport(Foundation)
import Foundation
#endif

extension Canvas {
    /// How a drawn color combines with the pixel under it.
    ///
    /// The separable modes follow the W3C Compositing and Blending spec: the
    /// mode's function mixes the source color with the backdrop color, and
    /// the result is composited "source over", weighted by the source's
    /// opacity and coverage. `plusLighter` and `plusDarker` follow Core
    /// Graphics and add or subtract the colors themselves. All of them work
    /// on straight-alpha 8-bit colors in sRGB, without linearizing.
    ///
    /// `luminosity` is not separable: it mixes all three channels at once,
    /// also as the W3C spec defines it.
    ///
    /// Liquid Glass recipes use `plusLighter` for specular highlights,
    /// `plusDarker` for rims, and `lighten`, `darken`, `screen`, and, in the
    /// dark appearance, `luminosity` in their tint stacks. The color, hue,
    /// saturation, overlay, and light and dodge modes are not implemented.
    public enum BlendMode: Sendable, Hashable {
        /// The source covers the backdrop in proportion to its opacity.
        case normal
        /// Source × backdrop: never lighter than either.
        case multiply
        /// 1 − (1 − source) × (1 − backdrop): never darker than either.
        case screen
        /// The lighter of the source and the backdrop, per channel.
        case lighten
        /// The darker of the source and the backdrop, per channel.
        case darken
        /// Backdrop + opacity × source, clamped: a white source at 40%
        /// raises each channel by 102 levels.
        case plusLighter
        /// Backdrop − opacity × (1 − source), clamped: a 219 gray source
        /// lowers each channel by 36 levels.
        case plusDarker
        /// The backdrop's hue and saturation with the source's luminosity:
        /// over a gray backdrop, a gray source acts as `normal` does.
        case luminosity
    }

    /// Blends `color`, weighted by `coverage` in `0...1`, over the pixel at a
    /// byte offset with a blend mode, quickly when the pixel is opaque.
    ///
    /// Over an opaque pixel, "source over" is a straight mix of the two
    /// colors, done here in integers with the amount in 4096ths. Shadows
    /// and gradients, which blend a different amount into every pixel, use
    /// this. It can round a level differently from `blend`, which shapes
    /// and text keep using so their pixels stay as they were.
    @inline(__always)
    static func blendQuickly(
        _ color: RGBA,
        _ coverage: Float,
        _ mode: BlendMode,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        at index: Int
    ) {
        guard mode == .normal, bytes[index + 3] == 255 else {
            blend(color, coverage, mode, into: bytes, at: index)
            return
        }
        let weight = Int(min(coverage, 1) * Float(color.alpha) * (4096 / 255) + 0.5)
        guard weight > 0 else { return }
        @inline(__always) func channel(_ source: UInt8, _ destination: UInt8) -> UInt8 {
            let base = Int(destination)
            return UInt8(truncatingIfNeeded: base + (((Int(source) - base) * weight + 2048) >> 12))
        }
        bytes[index] = channel(color.red, bytes[index])
        bytes[index + 1] = channel(color.green, bytes[index + 1])
        bytes[index + 2] = channel(color.blue, bytes[index + 2])
    }

    /// Blends `color`, weighted by `coverage` in `0...1`, over the pixel at a
    /// byte offset with a mode other than `normal`.
    static func blendSeparately(
        _ color: RGBA,
        _ coverage: Float,
        mode: BlendMode,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        at index: Int
    ) {
        if mode == .luminosity {
            blendLuminosity(color, coverage, into: bytes, at: index)
            return
        }
        if bytes[index + 3] == 255 {
            blendOverOpaque(color, coverage, mode: mode, into: bytes, at: index)
            return
        }
        let sourceAlpha = min(coverage, 1) * Float(color.alpha) / 255
        guard sourceAlpha > 0 else { return }
        let backdropAlpha = Float(bytes[index + 3]) / 255
        let outAlpha: Float
        switch mode {
        case .plusLighter, .plusDarker: outAlpha = min(sourceAlpha + backdropAlpha, 1)
        default: outAlpha = sourceAlpha + backdropAlpha * (1 - sourceAlpha)
        }
        guard outAlpha > 0 else { return }

        // Each channel is computed premultiplied, then divided by the
        // resulting opacity.
        func channel(_ sourceByte: UInt8, _ backdropByte: UInt8) -> UInt8 {
            let source = Float(sourceByte) / 255
            let backdrop = Float(backdropByte) / 255
            let premultiplied: Float
            switch mode {
            case .plusLighter:
                premultiplied = min(sourceAlpha * source + backdropAlpha * backdrop, 1)
            case .plusDarker:
                premultiplied = max(
                    outAlpha - (sourceAlpha - sourceAlpha * source)
                        - (backdropAlpha - backdropAlpha * backdrop), 0)
            default:
                let mixed: Float
                switch mode {
                case .multiply: mixed = source * backdrop
                case .screen: mixed = source + backdrop - source * backdrop
                case .lighten: mixed = max(source, backdrop)
                case .darken: mixed = min(source, backdrop)
                default: mixed = source
                }
                // Over a transparent backdrop the mode has nothing to mix
                // with, so the source shows as it is.
                let blended = (1 - backdropAlpha) * source + backdropAlpha * mixed
                premultiplied =
                    sourceAlpha * blended + (1 - sourceAlpha) * backdropAlpha * backdrop
            }
            let value = premultiplied / outAlpha * 255
            return UInt8(min(max(value.rounded(), 0), 255))
        }
        bytes[index] = channel(color.red, bytes[index])
        bytes[index + 1] = channel(color.green, bytes[index + 1])
        bytes[index + 2] = channel(color.blue, bytes[index + 2])
        bytes[index + 3] = UInt8(min(max((outAlpha * 255).rounded(), 0), 255))
    }

    /// Blends with a mode other than `normal` over an opaque pixel, where
    /// the result stays opaque and each channel is the backdrop moved
    /// toward the mode's result by the source's opacity. It runs in
    /// integers, with the opacity in 4096ths.
    @inline(__always)
    private static func blendOverOpaque(
        _ color: RGBA,
        _ coverage: Float,
        mode: BlendMode,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        at index: Int
    ) {
        let weight = Int(min(coverage, 1) * Float(color.alpha) * (4096 / 255) + 0.5)
        guard weight > 0 else { return }
        @inline(__always) func channel(_ sourceByte: UInt8, _ backdropByte: UInt8) -> UInt8 {
            let source = Int(sourceByte)
            let backdrop = Int(backdropByte)
            let value: Int
            switch mode {
            case .plusLighter:
                value = min(backdrop &+ ((source &* weight &+ 2048) >> 12), 255)
            case .plusDarker:
                value = max(backdrop &- (((255 &- source) &* weight &+ 2048) >> 12), 0)
            default:
                let mixed: Int
                switch mode {
                case .multiply: mixed = (source &* backdrop &+ 127) / 255
                case .screen: mixed = source &+ backdrop &- (source &* backdrop &+ 127) / 255
                case .lighten: mixed = max(source, backdrop)
                case .darken: mixed = min(source, backdrop)
                default: mixed = source
                }
                value = backdrop &+ (((mixed &- backdrop) &* weight &+ 2048) >> 12)
            }
            return UInt8(truncatingIfNeeded: value)
        }
        bytes[index] = channel(color.red, bytes[index])
        bytes[index + 1] = channel(color.green, bytes[index + 1])
        bytes[index + 2] = channel(color.blue, bytes[index + 2])
    }
}

extension Canvas {
    /// Blends with `luminosity`, composited "source over" like the separable
    /// modes. The mixed color is the W3C spec's SetLum(backdrop, Lum(source)),
    /// with luminosity weighted 0.3, 0.59, and 0.11, and clipped back into
    /// range around its luminosity.
    private static func blendLuminosity(
        _ color: RGBA,
        _ coverage: Float,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        at index: Int
    ) {
        let sourceAlpha = min(coverage, 1) * Float(color.alpha) / 255
        guard sourceAlpha > 0 else { return }
        let backdropAlpha = Float(bytes[index + 3]) / 255
        let outAlpha = sourceAlpha + backdropAlpha * (1 - sourceAlpha)
        let source = SIMD3<Float>(Float(color.red), Float(color.green), Float(color.blue)) / 255
        let backdrop =
            SIMD3<Float>(Float(bytes[index]), Float(bytes[index + 1]), Float(bytes[index + 2]))
            / 255
        func luminosity(_ color: SIMD3<Float>) -> Float {
            0.3 * color.x + 0.59 * color.y + 0.11 * color.z
        }
        var mixed = backdrop + (luminosity(source) - luminosity(backdrop))
        let level = luminosity(mixed)
        let lowest = mixed.min()
        let highest = mixed.max()
        if lowest < 0 { mixed = level + (mixed - level) * (level / (level - lowest)) }
        if highest > 1 { mixed = level + (mixed - level) * ((1 - level) / (highest - level)) }
        // Over a transparent backdrop there is nothing to mix with, so the
        // source shows as it is.
        let blended = (1 - backdropAlpha) * source + backdropAlpha * mixed
        let premultiplied = sourceAlpha * blended + (1 - sourceAlpha) * backdropAlpha * backdrop
        let result = premultiplied / outAlpha * 255
        for channel in 0..<3 {
            bytes[index + channel] = UInt8(min(max(result[channel].rounded(), 0), 255))
        }
        bytes[index + 3] = UInt8(min(max((outAlpha * 255).rounded(), 0), 255))
    }
}
