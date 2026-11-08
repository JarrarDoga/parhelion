import ArgumentParser
import Foundation
import ParhelionRender
import ParhelionTooling

struct Symbols: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "symbols",
        abstract: "Use your own copy of SF Symbols in previews.",
        discussion: """
            Parhelion draws Image(systemName:) with Phosphor Icons. If you have SF Symbols, \
            it draws those instead. Parhelion contains no SF Symbols and downloads none.

            Whether using your copy on Linux to preview an app is within Apple's SF Symbols \
            license is your responsibility. Apple's license allows SF Symbols only for \
            designing and developing apps for Apple platforms, and forbids redistributing them.
            """,
        subcommands: [Import.self, Status.self]
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Copy SF Symbols exported as SVG into your Parhelion data folder.",
            discussion: """
                In the SF Symbols app, select symbols (or all of them), choose File > Export \
                Symbol, and save them as SVG into a folder. Import that folder. Parhelion \
                keeps only the outlines it draws, in \(SymbolTemplate.defaultDirectory ?? "your data folder"), \
                never in a repository or a build.

                Instead of importing, you can set \(SymbolTemplate.environmentVariable) to \
                the folder of exports.
                """
        )

        @Argument(help: "A folder of SVG exports, or one SVG file.")
        var path: String

        @Option(help: "The folder to write to. (default: the active symbols folder)")
        var destination: String?

        func run() throws {
            guard let target = destination ?? SymbolTemplate.activeDirectory else {
                throw ValidationError("There is no home folder. Pass --destination.")
            }
            do {
                let report = try SymbolImporter.import(from: path, to: target)
                print("Imported \(report.imported) symbols into \(report.destination).")
                if !report.skipped.isEmpty {
                    print("Skipped \(report.skipped.count) files with no readable outline.")
                }
            } catch let failure as SymbolImporter.Failure {
                throw ValidationError(failure.description)
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Say which folder Parhelion reads SF Symbols from."
        )

        func run() {
            guard let directory = SymbolTemplate.activeDirectory else {
                print("No symbols folder: there is no home folder.")
                return
            }
            let count = SymbolImporter.count(in: directory)
            if count == 0 {
                print("No SF Symbols in \(directory). Images draw with Phosphor Icons.")
            } else {
                print("\(count) SF Symbols in \(directory).")
            }
        }
    }
}
