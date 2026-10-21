import ArgumentParser

@main
struct Parhelion: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parhelion",
        abstract: "Run SwiftUI apps on Linux with Parhelion.",
        subcommands: [Run.self, Preview.self, MCP.self]
    )
}
