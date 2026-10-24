import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Drawing images: symbols, images from asset catalogs, and images that
// `AsyncImage` loaded.

extension TreeRenderer {
    /// Draws an image node in its frame.
    func drawImage(
        _ node: ViewNode, in frame: CGRect, foreground: String?, opacity: Double,
        paint color: (String) -> RGBA, into canvas: inout Canvas
    ) {
        let style = foreground ?? "primary"
        if node.attributes["systemName"] != nil {
            drawSymbol(
                node, in: frame,
                paint: paint(of: style, in: frame, foreground: nil, color: color), into: &canvas)
            return
        }
        guard node.attributes["missingImage"] != "true",
            let size = parseSize(node.attributes["size"]),
            let (levels, key) = bitmapLevels(node, scale: canvas.scale)
        else {
            drawMissingImage(in: frame, color: color(style), into: &canvas)
            return
        }
        let tint = node.attributes["renderingMode"] == "template" ? color(style) : nil
        // A tint already carries the opacity.
        let strength = tint == nil ? opacity : 1
        let insets = Self.capInsets(node)
        let tiles = node.attributes["resizingMode"] == "tile"
        guard insets != EdgeInsets() || tiles else {
            let bitmap = ImageLibrary.shared.level(
                of: levels, key: key, forWidth: Double(frame.width) * canvas.scale)
            canvas.draw(bitmap, in: frame, opacity: strength, tint: tint)
            return
        }
        drawSlices(
            levels[0], pointSize: size, insets: insets, tiles: tiles, in: frame, opacity: strength,
            tint: tint, into: &canvas)
    }

    /// The decoded levels of an image node's file, and the key the library
    /// keeps them by: for an asset, the file for the canvas's scale and the
    /// node's appearance; for a loaded image, the image its URL loaded.
    private func bitmapLevels(_ node: ViewNode, scale: Double) -> ([Bitmap], String)? {
        let library = ImageLibrary.shared
        if let url = node.attributes["url"] {
            return library.loaded(url).map { ($0, "url:" + url) }
        }
        guard let name = node.attributes["name"],
            let asset = library.asset(named: name, bundle: node.attributes["bundle"]),
            let entry = ImageAsset.entry(
                in: asset.entries(dark: node.attributes["appearance"] == "dark"), forScale: scale),
            let levels = library.levels(of: entry.url)
        else { return nil }
        return (levels, entry.url.path)
    }

    private static func capInsets(_ node: ViewNode) -> EdgeInsets {
        let values = (node.attributes["capInsets"] ?? "").components(separatedBy: ", ")
            .compactMap(Double.init).map { CGFloat($0) }
        guard values.count == 4 else { return EdgeInsets() }
        return EdgeInsets(
            top: values[0], leading: values[1], bottom: values[2], trailing: values[3])
    }

    /// Draws a resizable image in nine parts: the corners inside its cap
    /// insets at their size, the edges stretched or tiled along one axis,
    /// and the middle stretched or tiled along both.
    private func drawSlices(
        _ bitmap: Bitmap, pointSize: CGSize, insets: EdgeInsets, tiles: Bool, in frame: CGRect,
        opacity: Double, tint: RGBA?, into canvas: inout Canvas
    ) {
        guard pointSize.width > 0, pointSize.height > 0 else { return }
        let pixelsPerPoint = (
            x: CGFloat(bitmap.width) / pointSize.width,
            y: CGFloat(bitmap.height) / pointSize.height
        )
        // Cap insets wider than the image or the frame shrink to fit.
        func fit(_ low: CGFloat, _ high: CGFloat, _ length: CGFloat) -> (CGFloat, CGFloat) {
            let total = low + high
            guard total > length, total > 0 else { return (low, high) }
            return (low * length / total, high * length / total)
        }
        let source = (
            x: fit(insets.leading, insets.trailing, pointSize.width),
            y: fit(insets.top, insets.bottom, pointSize.height)
        )
        let target = (
            x: fit(source.x.0, source.x.1, frame.width),
            y: fit(source.y.0, source.y.1, frame.height)
        )
        let sourceColumns = [
            (0, source.x.0), (source.x.0, pointSize.width - source.x.1),
            (pointSize.width - source.x.1, pointSize.width),
        ]
        let sourceRows = [
            (0, source.y.0), (source.y.0, pointSize.height - source.y.1),
            (pointSize.height - source.y.1, pointSize.height),
        ]
        // The parts meet at whole pixels, so their anti-aliased edges do not
        // leave seams between them.
        let scale = canvas.scale
        func snap(_ value: CGFloat) -> CGFloat {
            CGFloat((Double(value) * scale).rounded() / scale)
        }
        let innerX = (snap(frame.minX + target.x.0), snap(frame.maxX - target.x.1))
        let innerY = (snap(frame.minY + target.y.0), snap(frame.maxY - target.y.1))
        let targetColumns = [
            (frame.minX, innerX.0), (innerX.0, innerX.1), (innerX.1, frame.maxX),
        ]
        let targetRows = [
            (frame.minY, innerY.0), (innerY.0, innerY.1), (innerY.1, frame.maxY),
        ]
        for row in 0..<3 {
            for column in 0..<3 {
                let piece = CGRect(
                    x: sourceColumns[column].0 * pixelsPerPoint.x,
                    y: sourceRows[row].0 * pixelsPerPoint.y,
                    width: (sourceColumns[column].1 - sourceColumns[column].0) * pixelsPerPoint.x,
                    height: (sourceRows[row].1 - sourceRows[row].0) * pixelsPerPoint.y)
                let destination = CGRect(
                    x: targetColumns[column].0, y: targetRows[row].0,
                    width: targetColumns[column].1 - targetColumns[column].0,
                    height: targetRows[row].1 - targetRows[row].0)
                guard piece.width > 0, piece.height > 0, destination.width > 0,
                    destination.height > 0
                else { continue }
                guard tiles, row == 1 || column == 1 else {
                    canvas.draw(
                        bitmap, from: piece, in: destination, opacity: opacity, tint: tint)
                    continue
                }
                // A tiled part repeats at its own size along the axes it
                // fills.
                let tile = CGSize(
                    width: column == 1 ? piece.width / pixelsPerPoint.x : destination.width,
                    height: row == 1 ? piece.height / pixelsPerPoint.y : destination.height)
                let outerClip = canvas.clipRect
                canvas.clipRect = outerClip.map { $0.intersection(destination) } ?? destination
                var y = destination.minY
                while y < destination.maxY {
                    var x = destination.minX
                    while x < destination.maxX {
                        // Tiles, too, meet at whole pixels.
                        let left = snap(x)
                        let top = snap(y)
                        canvas.draw(
                            bitmap, from: piece,
                            in: CGRect(
                                x: left, y: top, width: snap(x + tile.width) - left,
                                height: snap(y + tile.height) - top),
                            opacity: opacity, tint: tint)
                        x += tile.width
                    }
                    y += tile.height
                }
                canvas.clipRect = outerClip
            }
        }
    }

    /// Draws a symbol image with a color or a gradient.
    private func drawSymbol(
        _ node: ViewNode, in frame: CGRect, paint: Paint, into canvas: inout Canvas
    ) {
        switch paint {
        case .color(let color):
            drawSymbol(node, in: frame, color: color, into: &canvas)
        case .gradient(let gradient):
            guard let name = node.attributes["systemName"] else { return }
            let side = min(frame.width, frame.height)
            let symbol = SymbolLibrary.resolve(
                name, fill: node.attributes["symbolVariant"] == "fill")
            canvas.fill(
                symbol.path.applying(
                    scaleX: Double(side), scaleY: Double(side),
                    translateX: Double(frame.midX - side / 2),
                    translateY: Double(frame.midY - side / 2)),
                gradient: gradient)
        }
    }

    /// Draws the ring that stands for an image Parhelion cannot draw, the
    /// one a missing symbol draws, as large as a symbol of the body font
    /// or the frame, whichever is smaller.
    private func drawMissingImage(in frame: CGRect, color: RGBA, into canvas: inout Canvas) {
        let side = min(frame.width, frame.height, LayoutDefaults.symbolSide(for: .medium))
        guard side > 0 else { return }
        let ring = SymbolLibrary.resolve("parhelion.missing-image").path
        canvas.fill(
            ring.applying(
                scaleX: Double(side), scaleY: Double(side),
                translateX: Double(frame.midX - side / 2), translateY: Double(frame.midY - side / 2)
            ),
            color: color)
    }
}
