import Foundation
import Testing

@testable import ParhelionTooling

/// `swift package dump-package` output for an app shaped like `xtool new`
/// creates: one library product whose target depends on Parhelion on Linux
/// only, plus a local helper target and a Git dependency.
private let libraryAppJSON = """
    {
      "name": "MyApp",
      "toolsVersion": {"_version": "6.0.0"},
      "dependencies": [
        {"fileSystem": [{"identity": "parhelion", "path": "/src/parhelion", "productFilter": null}]},
        {"sourceControl": [{
          "identity": "swift-collections",
          "location": {"remote": [{"urlString": "https://github.com/apple/swift-collections.git"}]},
          "productFilter": null,
          "requirement": {"range": [{"lowerBound": "1.1.0", "upperBound": "2.0.0"}]}
        }]}
      ],
      "products": [{"name": "MyApp", "type": {"library": ["automatic"]}, "targets": ["MyApp"]}],
      "targets": [
        {
          "name": "MyApp", "type": "regular",
          "dependencies": [
            {"product": ["SwiftUI", "parhelion", null, {"platformNames": ["linux"]}]},
            {"product": ["Collections", "swift-collections", null, null]},
            {"byName": ["Model", null]}
          ]
        },
        {"name": "Model", "type": "regular", "path": "Sources/Shared/Model", "dependencies": []},
        {"name": "MyAppTests", "type": "test", "dependencies": [{"target": ["MyApp", null]}]}
      ]
    }
    """

@Suite("Package inspection")
struct AppPackageTests {
    @Test("Dependencies, targets, and products are read from dump-package JSON")
    func parse() throws {
        let package = try AppPackage.parse(Data(libraryAppJSON.utf8))
        #expect(package.name == "MyApp")
        #expect(package.toolsVersion == "6.0.0")
        #expect(
            package.dependencies == [
                .fileSystem(name: "parhelion", path: "/src/parhelion"),
                .sourceControl(
                    url: "https://github.com/apple/swift-collections.git",
                    requirement: .range(lower: "1.1.0", upper: "2.0.0")
                ),
            ]
        )
        let app = try #require(package.targets.first { $0.name == "MyApp" })
        #expect(app.path == "Sources/MyApp")
        #expect(
            app.dependencies == [
                .product(name: "SwiftUI", package: "parhelion", platforms: ["linux"]),
                .product(name: "Collections", package: "swift-collections", platforms: nil),
                .byName("Model", platforms: nil),
            ]
        )
        #expect(package.targets.first { $0.name == "Model" }?.path == "Sources/Shared/Model")
        #expect(package.products == [.init(name: "MyApp", isExecutable: false, targets: ["MyApp"])])
    }

    @Test("A path dependency keeps the name it was declared with")
    func renamedPathDependency() throws {
        // A clone in a directory called `work` has the identity `work`, but
        // targets still refer to the package as `parhelion`.
        let json = """
            {"name": "A", "dependencies": [{"fileSystem": [{
              "identity": "work", "nameForTargetDependencyResolutionOnly": "parhelion",
              "path": "/work"}]}]}
            """
        let package = try AppPackage.parse(Data(json.utf8))
        #expect(package.dependencies == [.fileSystem(name: "parhelion", path: "/work")])
    }

    @Test("Registry dependencies are reported as unsupported")
    func registryDependency() {
        let json = #"{"name": "A", "dependencies": [{"registry": [{"identity": "x.y"}]}]}"#
        #expect(throws: AppPackage.InspectionError.self) {
            try AppPackage.parse(Data(json.utf8))
        }
    }
}

@Suite("Run plans")
struct RunPlanTests {
    @Test("A library app runs through a generated runner package")
    func libraryApp() throws {
        let package = try AppPackage.parse(Data(libraryAppJSON.utf8))
        let plan = try RunPlan.make(for: package, at: "/work/MyApp", product: nil)
        #expect(plan.product == "MyApp")
        #expect(plan.buildPackagePath == "/work/MyApp/.build/parhelion-runner")
        #expect(plan.watchRoot == "/work/MyApp")

        let runner = try #require(plan.runner)
        #expect(
            runner.links == [
                "Sources/MyApp": "/work/MyApp/Sources/MyApp",
                "Sources/Model": "/work/MyApp/Sources/Shared/Model",
            ]
        )
        let manifest = runner.manifest
        #expect(manifest.hasPrefix("// swift-tools-version: 6.0\n"))
        #expect(manifest.contains(#".package(name: "parhelion", path: "/src/parhelion")"#))
        #expect(
            manifest.contains(
                #".package(url: "https://github.com/apple/swift-collections.git", "1.1.0"..<"2.0.0")"#
            )
        )
        #expect(manifest.contains(#".executableTarget("#))
        #expect(
            manifest.contains(
                #".product(name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux]))"#
            )
        )
        #expect(manifest.contains(#".target(name: "Model")"#))
        #expect(!manifest.contains("MyAppTests"))
    }

    @Test("An executable target runs as it is, even without a declared product")
    func executableTarget() throws {
        let json = """
            {"name": "Examples", "products": [],
             "targets": [{"name": "Counter", "type": "executable", "dependencies": []}]}
            """
        let plan = try RunPlan.make(
            for: try AppPackage.parse(Data(json.utf8)),
            at: "/work/Examples",
            product: nil
        )
        #expect(plan.product == "Counter")
        #expect(plan.buildPackagePath == "/work/Examples")
        #expect(plan.runner == nil)
    }

    @Test("Several apps need --product")
    func ambiguous() throws {
        let json = """
            {"name": "E", "products": [], "targets": [
              {"name": "A", "type": "executable", "dependencies": []},
              {"name": "B", "type": "executable", "dependencies": []}]}
            """
        let package = try AppPackage.parse(Data(json.utf8))
        #expect(throws: RunPlan.PlanError.ambiguous(["A", "B"])) {
            try RunPlan.make(for: package, at: "/w", product: nil)
        }
        #expect(try RunPlan.make(for: package, at: "/w", product: "B").product == "B")
        #expect(throws: RunPlan.PlanError.noSuchProduct("C")) {
            try RunPlan.make(for: package, at: "/w", product: "C")
        }
    }

    @Test("Build errors point at the app's sources, not the runner's links")
    func errorPaths() throws {
        let package = try AppPackage.parse(Data(libraryAppJSON.utf8))
        let plan = try RunPlan.make(for: package, at: "/work/MyApp", product: nil)
        let output = """
            Compiling MyApp ContentView.swift
            /work/MyApp/.build/parhelion-runner/Sources/MyApp/ContentView.swift:3:5: error: oops
            """
        let summary = AppBuilder(plan: plan).errorSummary(output)
        #expect(summary == "/work/MyApp/Sources/MyApp/ContentView.swift:3:5: error: oops")
    }

    @Test("Preparing a plan writes the manifest and links")
    func prepare() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-plan-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(
            atPath: root + "/Sources/MyApp",
            withIntermediateDirectories: true
        )
        let package = try AppPackage.parse(Data(libraryAppJSON.utf8))
        let plan = try RunPlan.make(for: package, at: root, product: nil)
        try plan.prepare()
        try plan.prepare()  // Preparing again keeps the same files.

        let runner = try #require(plan.runner)
        let manifest = try String(
            contentsOfFile: runner.directory + "/Package.swift", encoding: .utf8)
        #expect(manifest == runner.manifest)
        let link = try FileManager.default.destinationOfSymbolicLink(
            atPath: runner.directory + "/Sources/MyApp"
        )
        #expect(link == root + "/Sources/MyApp")
    }
}

@Suite("Source watcher")
struct SourceWatcherTests {
    @Test("Changes to Swift files are detected, and build output is ignored")
    func detectsChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-watch-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(
            atPath: root + "/.build",
            withIntermediateDirectories: true
        )
        try "let a = 1".write(toFile: root + "/A.swift", atomically: true, encoding: .utf8)

        var watcher = SourceWatcher(root: root)
        var changed = watcher.checkForChanges()
        #expect(!changed)

        try "let b = 2".write(toFile: root + "/B.swift", atomically: true, encoding: .utf8)
        changed = watcher.checkForChanges()
        #expect(changed)
        changed = watcher.checkForChanges()
        #expect(!changed, "A change is reported once")

        try "notes".write(toFile: root + "/README.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: root + "/.build/C.swift", atomically: true, encoding: .utf8)
        changed = watcher.checkForChanges()
        #expect(!changed, "Other files and build output are ignored")

        try FileManager.default.removeItem(atPath: root + "/A.swift")
        changed = watcher.checkForChanges()
        #expect(changed, "Removed files count as changes")
    }
}
