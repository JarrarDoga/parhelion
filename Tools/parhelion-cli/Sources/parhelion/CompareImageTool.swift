import Foundation
import ParhelionPreview
import ParhelionTooling

extension AgentTools {
    /// `compare_image`: the screen against a design board.
    static let compareImage = MCPTool(
        name: "compare_image",
        title: "Compare the screen with a design board",
        description: """
            Renders the screen at the scale of a design board, a PNG of the whole screen such \
            as 1320 × 2868 pixels for an iPhone 18 Pro Max at 3×, and compares the two. \
            Returns the share of pixels that differ, the area they lie in, and a diff image: \
            the screen faded, with differing pixels in red. A pixel differs when a red, \
            green, blue, or alpha value is more than `tolerance` (0 to 255, default 8) from \
            the board's. The diff is also written to diff_path, or to a file in the \
            temporary directory that the result names.
            """,
        inputSchema: #"""
            {"type": "object", "properties": {
              "path": {"type": "string", "description": "The board's PNG file."},
              "tolerance": {"type": "integer", "minimum": 0, "maximum": 255, "default": 8},
              "diff_path": {"type": "string"}},
             "required": ["path"]}
            """#
    )
}

extension AgentController {
    func compareImage(_ arguments: MCPArguments) -> MCPToolResult {
        guard let path = arguments.string("path") else {
            return .text("compare_image needs path, the board's PNG file.", isError: true)
        }
        guard let app = currentApp, !app.isDisconnected else { return notRunning() }
        let hello = app.hello
        do {
            let outcome = try BoardComparison.compare(
                boardPath: (path as NSString).expandingTildeInPath,
                screenWidth: hello.screenWidth,
                screenHeight: hello.screenHeight,
                tolerance: arguments.int("tolerance") ?? ImageDiff.defaultTolerance,
                diffPath: arguments.string("diff_path")
            ) { scale in
                guard let reply = app.request(.screenshot(scale: scale)) else {
                    throw BoardComparison.Failure(
                        description:
                            "The app did not answer. It may have crashed; see app_output, then rebuild."
                    )
                }
                guard reply.ok, let png = reply.png else {
                    throw BoardComparison.Failure(description: reply.message)
                }
                return [UInt8](png)
            }
            return MCPToolResult(content: [
                .image(Data(outcome.diffPNG), mimeType: "image/png"), .text(outcome.summary),
            ])
        } catch {
            return .text("\(error)", isError: true)
        }
    }
}
