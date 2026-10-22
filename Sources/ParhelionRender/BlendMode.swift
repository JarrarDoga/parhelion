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
    /// Liquid Glass recipes use `plusLighter` for specular highlights,
    /// `plusDarker` for rims, and `lighten`, `darken`, and `screen` in their
    /// tint stacks. The luminosity, color, hue, saturation, overlay, and
    /// light and dodge modes are not implemented: the glass tints they make
    /// over gray backdrops reduce to `normal` and `plusLighter` fills.
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
}
