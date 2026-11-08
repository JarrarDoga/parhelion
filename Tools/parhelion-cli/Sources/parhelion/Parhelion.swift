import ArgumentParser
import ParhelionTooling

@main
struct Parhelion: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parhelion",
        abstract: "Run SwiftUI apps on Linux with Parhelion.",
        subcommands: [Run.self, Preview.self, MCP.self, TestCommand.self, Symbols.self]
    )

    /// Registers the tools and window hooks that plug in from their own
    /// files, then runs the command.
    static func main() {
        ClipboardSupport.register(clipboard: SDLClipboard())
        main(nil)
    }
}
