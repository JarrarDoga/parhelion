import ArgumentParser
import Foundation
import ParhelionPreview
import ParhelionRender
import ParhelionTooling

/// `--overlay board.png`: draws a design board over the preview window.
struct OverlayOptions: ParsableArguments {
    @Option(
        help: """
            A design board PNG to draw over the preview, stretched to the screen, \
            to compare by eye.
            """)
    var overlay: String?

    @Option(help: "How opaque the overlay is, from 0 to 1.")
    var overlayOpacity: Double = 0.5

    func validate() throws {
        guard (0...1).contains(overlayOpacity) else {
            throw ValidationError("--overlay-opacity must be between 0 and 1.")
        }
        if overlay == nil, overlayOpacity != 0.5 {
            throw ValidationError("--overlay-opacity needs --overlay.")
        }
    }

    /// Reads the board, or returns `nil` without `--overlay`.
    func loadBoard() throws -> Bitmap? {
        guard let overlay else { return nil }
        let path = (overlay as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ValidationError("Cannot read the overlay \(overlay).")
        }
        do {
            return try Bitmap(pngData: [UInt8](data))
        } catch {
            throw ValidationError("The overlay \(overlay) is not a PNG image: \(error).")
        }
    }

    /// Draws the board over `window`, and prints a warning if it is not
    /// the screen's shape.
    func apply(to window: WindowHost, hello: PreviewHello) throws {
        guard let board = try loadBoard() else { return }
        if let warning = BoardComparison.stretchWarning(
            boardWidth: board.width, boardHeight: board.height, screenWidth: hello.screenWidth,
            screenHeight: hello.screenHeight)
        {
            print(warning)
        }
        try window.setOverlay(board, opacity: overlayOpacity)
    }
}
