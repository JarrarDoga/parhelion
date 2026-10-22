import Foundation
import Testing

@testable import ParhelionTooling

/// A package that depends on Parhelion with `requirement`, as
/// `swift package dump-package` describes it.
private func appJSON(parhelion requirement: String) -> String {
    """
    {
      "name": "MyApp",
      "dependencies": [
        {"sourceControl": [{
          "identity": "parhelion",
          "location": {"remote": [{"urlString": "https://github.com/JarrarDoga/parhelion.git"}]},
          "productFilter": null,
          "requirement": \(requirement)
        }]}
      ],
      "products": [{"name": "MyApp", "type": {"executable": null}, "targets": ["MyApp"]}],
      "targets": [
        {"name": "MyApp", "type": "executable", "dependencies": [
          {"product": ["SwiftUI", "parhelion", null, {"platformNames": ["linux"]}]}
        ]}
      ]
    }
    """
}

private func plan(_ json: String) throws -> RunPlan {
    try RunPlan.make(for: try AppPackage.parse(Data(json.utf8)), at: "/work/MyApp", product: nil)
}

@Suite("Optimized framework builds")
struct FrameworkOptimizationTests {
    @Test("A path, branch, or revision dependency optimizes only Parhelion")
    func unpinned() throws {
        let path = """
            {"name": "MyApp",
             "dependencies": [{"fileSystem": [{"identity": "parhelion", "path": "/src/parhelion"}]}],
             "products": [],
             "targets": [{"name": "MyApp", "type": "executable", "dependencies": [
               {"product": ["SwiftUI", "parhelion", null, null]}]}]}
            """
        #expect(try plan(path).optimization == .frameworkOnly)
        #expect(
            try plan(appJSON(parhelion: #"{"branch": ["main"]}"#)).optimization == .frameworkOnly)
        #expect(
            try plan(appJSON(parhelion: #"{"revision": ["abc123"]}"#)).optimization
                == .frameworkOnly)
    }

    @Test("A dependency pinned to versions optimizes the whole build")
    func pinned() throws {
        let range = #"{"range": [{"lowerBound": "0.1.0", "upperBound": "1.0.0"}]}"#
        #expect(try plan(appJSON(parhelion: range)).optimization == .wholeBuild)
        #expect(try plan(appJSON(parhelion: #"{"exact": ["0.1.0"]}"#)).optimization == .wholeBuild)
    }

    @Test("Parhelion's own examples optimize only Parhelion")
    func rootPackage() throws {
        let json = """
            {"name": "Parhelion",
             "products": [{"name": "ParhelionUI", "type": {"library": ["automatic"]}, "targets": ["ParhelionUI"]}],
             "targets": [{"name": "Counter", "type": "executable", "dependencies": []}]}
            """
        #expect(try plan(json).optimization == .frameworkOnly)
    }

    @Test("A package that does not say where Parhelion comes from optimizes the whole build")
    func unknown() throws {
        let json = """
            {"name": "E", "products": [],
             "targets": [{"name": "Counter", "type": "executable", "dependencies": []}]}
            """
        #expect(try plan(json).optimization == .wholeBuild)
    }

    @Test("Package identities come from the last part of the URL")
    func identity() {
        #expect(
            RunPlan.identity(ofURL: "https://github.com/JarrarDoga/Parhelion.git") == "parhelion")
        #expect(RunPlan.identity(ofURL: "git@host:me/parhelion") == "parhelion")
    }
}

@Suite("Build commands")
struct BuildCommandTests {
    @Test("A debug build sets the variable and uses its own scratch directory")
    func frameworkOnly() throws {
        let builder = AppBuilder(plan: try plan(appJSON(parhelion: #"{"branch": ["main"]}"#)))
        let command = builder.buildCommand()
        #expect(
            command.arguments == [
                "build", "--product", "MyApp", "--package-path", "/work/MyApp",
                "--scratch-path", "/work/MyApp/.build/parhelion", "--configuration", "debug",
            ])
        #expect(command.environment == ["PARHELION_OPTIMIZE_FRAMEWORK": "1"])
        #expect(builder.modeDescription.contains("Parhelion optimized"))
    }

    @Test("Asking for the products' directory uses the same location and environment")
    func binPath() throws {
        let builder = AppBuilder(plan: try plan(appJSON(parhelion: #"{"branch": ["main"]}"#)))
        let build = builder.buildCommand()
        let binPath = builder.binPathCommand()
        #expect(binPath.environment == build.environment)
        #expect(binPath.arguments.contains("--show-bin-path"))
        #expect(
            Array(binPath.arguments.drop { $0 != "--package-path" })
                == Array(build.arguments.drop { $0 != "--package-path" }))
    }

    @Test("A pinned Parhelion falls back to -O for everything and clears the variable")
    func wholeBuild() throws {
        let range = #"{"exact": ["0.1.0"]}"#
        let builder = AppBuilder(plan: try plan(appJSON(parhelion: range)))
        let command = builder.buildCommand()
        #expect(command.arguments.suffix(2) == ["-Xswiftc", "-O"])
        #expect(command.environment == ["PARHELION_OPTIMIZE_FRAMEWORK": "0"])
        #expect(builder.modeDescription.contains("pinned"))
    }

    @Test("A release build adds no optimization flags of its own")
    func release() throws {
        for requirement in [#"{"exact": ["0.1.0"]}"#, #"{"branch": ["main"]}"#] {
            let builder = AppBuilder(
                plan: try plan(appJSON(parhelion: requirement)), configuration: "release")
            let command = builder.buildCommand()
            #expect(!command.arguments.contains("-Xswiftc"))
            #expect(command.arguments.contains("release"))
            #expect(command.arguments.contains("/work/MyApp/.build/parhelion"))
            #expect(builder.modeDescription == "release build")
        }
    }

    @Test("A library app builds its runner in the runner's own scratch directory")
    func runner() throws {
        let json = """
            {"name": "MyApp",
             "dependencies": [{"fileSystem": [{"identity": "parhelion", "path": "/src/parhelion"}]}],
             "products": [{"name": "MyApp", "type": {"library": ["automatic"]}, "targets": ["MyApp"]}],
             "targets": [{"name": "MyApp", "type": "regular", "dependencies": [
               {"product": ["SwiftUI", "parhelion", null, null]}]}]}
            """
        let builder = AppBuilder(plan: try plan(json))
        #expect(builder.scratchPath == "/work/MyApp/.build/parhelion-runner/.build/parhelion")
    }

    @Test("Compiled modules are read from both build systems' progress lines")
    func compiledModules() {
        let swiftBuild = """
            Building for debugging...
            [4 / 15] ParhelionPreview
            [17 / 26] ParhelionUI
            [17 / 27] ParhelionUI
            [31 / 35] Tasks-product
            Build complete! (1.63 secs)
            """
        #expect(AppBuilder.compiledModules(in: swiftBuild) == ["ParhelionPreview", "ParhelionUI"])
        let native = """
            [1/4] Compiling Tasks TasksApp.swift
            [2/4] Emitting module Tasks
            [3/4] Linking Tasks
            """
        #expect(AppBuilder.compiledModules(in: native) == ["Tasks"])
    }
}
