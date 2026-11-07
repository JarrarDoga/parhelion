import Foundation
import Testing

@testable import ParhelionTooling

/// An app that links a library which a pre-build command builds, the way
/// Rustle's iOS package links its Rust core, as `swift package
/// dump-package` describes it.
private let nativeAppJSON = """
    {
      "name": "RustApp",
      "toolsVersion": {"_version": "6.0.0"},
      "dependencies": [
        {"fileSystem": [{"identity": "parhelion", "path": "/src/parhelion", "productFilter": null}]}
      ],
      "products": [{"name": "RustApp", "type": {"library": ["automatic"]}, "targets": ["RustApp"]}],
      "targets": [
        {
          "name": "ffiFFI", "type": "regular", "dependencies": [],
          "settings": [
            {"kind": {"linkedLibrary": {"_0": "ffi"}}, "tool": "linker"},
            {"kind": {"linkedLibrary": {"_0": "m"}}, "tool": "linker",
             "condition": {"platformNames": ["linux"]}},
            {"kind": {"unsafeFlags": {"_0": ["-Wl,--as-needed"]}}, "tool": "linker"},
            {"kind": {"define": {"_0": "X"}}, "tool": "c"}
          ]
        },
        {
          "name": "RustApp", "type": "regular", "settings": [],
          "dependencies": [
            {"byName": ["ffiFFI", null]},
            {"product": ["SwiftUI", "parhelion", null, {"platformNames": ["linux"]}]}
          ]
        }
      ]
    }
    """

private func makeDirectory() throws -> String {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("parhelion-native-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

@Suite("Apps that link a native library")
struct NativeLibraryTests {
    @Test("parhelion.json is read, and a typo is an error")
    func config() throws {
        let config = try AppConfig.parse(
            Data(
                """
                {"preBuild": "scripts/build-ios.sh --linux", "watch": ["../crates"],
                 "libraryPaths": ["../target/debug"]}
                """.utf8))
        #expect(
            config
                == AppConfig(
                    preBuild: "scripts/build-ios.sh --linux", watch: ["../crates"],
                    libraryPaths: ["../target/debug"]))
        #expect(try AppConfig.parse(Data("{}".utf8)) == AppConfig())
        #expect(throws: AppConfig.ConfigError.self) {
            try AppConfig.parse(Data(#"{"prebuild": "x"}"#.utf8))
        }
        #expect(throws: AppConfig.ConfigError.self) {
            try AppConfig.parse(Data(#"{"watch": "crates"}"#.utf8))
        }
        #expect(throws: AppConfig.ConfigError.self) {
            try AppConfig.parse(Data("[]".utf8))
        }
    }

    @Test("A package without parhelion.json gets the default configuration")
    func missingConfig() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(try AppConfig.load(at: directory) == AppConfig())
        try #"{"preBuild": "make"}"#.write(
            toFile: directory + "/" + AppConfig.fileName, atomically: true, encoding: .utf8)
        #expect(try AppConfig.load(at: directory).preBuild == "make")
    }

    @Test("Options add to the file's paths and replace its command")
    func overriding() {
        let config = AppConfig(preBuild: "a", watch: ["x"], libraryPaths: ["l"])
        #expect(
            config.overriding(preBuild: "b", watch: ["y"], libraryPaths: ["m"])
                == AppConfig(preBuild: "b", watch: ["x", "y"], libraryPaths: ["l", "m"]))
        #expect(config.overriding(preBuild: nil, watch: [], libraryPaths: []) == config)
    }

    @Test("The plan resolves paths against the package")
    func plan() throws {
        let package = try AppPackage.parse(Data(nativeAppJSON.utf8))
        let config = AppConfig(
            preBuild: "scripts/build-ios.sh --linux", watch: ["../crates", "/abs/Cargo.toml"],
            libraryPaths: ["../target/debug"])
        let plan = try RunPlan.make(for: package, at: "/work/ios", product: nil, config: config)
        #expect(plan.preBuild == "scripts/build-ios.sh --linux")
        #expect(plan.packageRoot == "/work/ios")
        #expect(plan.extraWatchPaths == ["/work/crates", "/abs/Cargo.toml"])
        #expect(plan.libraryPaths == ["/work/target/debug"])
    }

    @Test("Linker settings reach the runner package")
    func runnerLinkerSettings() throws {
        let package = try AppPackage.parse(Data(nativeAppJSON.utf8))
        let target = try #require(package.targets.first { $0.name == "ffiFFI" })
        #expect(
            target.linkerSettings == [
                .init(kind: .library("ffi"), platforms: nil),
                .init(kind: .library("m"), platforms: ["linux"]),
                .init(kind: .unsafeFlags(["-Wl,--as-needed"]), platforms: nil),
            ])
        let plan = try RunPlan.make(for: package, at: "/work/ios", product: nil)
        let manifest = try #require(plan.runner).manifest
        #expect(manifest.contains(#".linkedLibrary("ffi")"#))
        #expect(manifest.contains(#".linkedLibrary("m", .when(platforms: [.linux]))"#))
        #expect(manifest.contains(#".unsafeFlags(["-Wl,--as-needed"])"#))
        #expect(!manifest.contains("define"))
    }

    @Test("Library paths go to the linker and the loader")
    func libraryFlags() throws {
        let package = try AppPackage.parse(Data(nativeAppJSON.utf8))
        let config = AppConfig(libraryPaths: ["target/debug"])
        let plan = try RunPlan.make(for: package, at: "/work/ios", product: nil, config: config)
        let arguments = AppBuilder(plan: plan).buildCommand().arguments
        let flags = ["-Xlinker", "-L/work/ios/target/debug", "-Xlinker", "-rpath"]
        let start = try #require(arguments.firstIndex(of: flags[1]))
        #expect(Array(arguments[(start - 1)...(start + 2)]) == flags)
        #expect(arguments.contains("/work/ios/target/debug"))
        let plain = try RunPlan.make(for: package, at: "/work/ios", product: nil)
        #expect(!AppBuilder(plan: plain).buildCommand().arguments.contains("-rpath"))
    }
}

@Suite("Pre-build commands")
struct PreBuildTests {
    /// A plan for a package in `directory` that has `command` as pre-build
    /// command and an executable product that does not need building.
    private func builder(
        in directory: String, preBuild: String, libraryPaths: [String] = []
    ) throws -> AppBuilder {
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "App", targets: [.executableTarget(name: "App")])
        """.write(toFile: directory + "/Package.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            atPath: directory + "/Sources/App", withIntermediateDirectories: true)
        try "print(1)".write(
            toFile: directory + "/Sources/App/main.swift", atomically: true, encoding: .utf8)
        let package = try AppPackage.load(at: directory)
        let plan = try RunPlan.make(
            for: package, at: directory, product: nil,
            config: AppConfig(preBuild: preBuild, libraryPaths: libraryPaths))
        return AppBuilder(plan: plan)
    }

    @Test("The command runs in the package with the build configuration")
    func runs() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let builder = try builder(
            in: directory, preBuild: #"echo "$PARHELION_CONFIGURATION" > ran.txt"#)
        #expect(try builder.runPreBuild() == nil)
        let ran = try String(contentsOfFile: directory + "/ran.txt", encoding: .utf8)
        #expect(ran == "debug\n")
    }

    @Test("A failing command stops the build, and its output is the summary")
    func fails() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let builder = try builder(
            in: directory,
            preBuild: "echo 'error[E0308]: mismatched types'; echo '  --> src/lib.rs:3:5'; exit 3")
        let outcome = builder.build()
        #expect(!outcome.succeeded)
        #expect(outcome.output.hasPrefix("The pre-build command failed (exit status 3)"))
        let summary = builder.errorSummary(outcome.output)
        // Cargo's "error[...]:" is not a compiler line, and it is kept.
        #expect(summary.contains("error[E0308]: mismatched types"))
        #expect(summary.contains("src/lib.rs:3:5"))
        #expect(summary.contains("scripts") == false)
    }

    @Test("A command that does not exist is a failure too")
    func missing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let builder = try builder(in: directory, preBuild: "no-such-command-for-parhelion")
        let outcome = builder.build()
        #expect(!outcome.succeeded)
        #expect(builder.errorSummary(outcome.output).contains("no-such-command-for-parhelion"))
    }

    @Test("A rebuilt static library removes the product, so that it is linked again")
    func staticLibrary() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(
            atPath: directory + "/lib", withIntermediateDirectories: true)
        let library = directory + "/lib"
        let builder = try builder(
            in: directory, preBuild: "echo x >> lib/libx.a", libraryPaths: [library])
        let product = try builder.executablePath()
        try FileManager.default.createDirectory(
            atPath: (product as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        _ = FileManager.default.createFile(atPath: product, contents: Data())
        #expect(try builder.runPreBuild() == nil)
        #expect(!FileManager.default.fileExists(atPath: product), "A new .a is a change")

        // Nothing changes: the product stays.
        let unchanged = try self.builder(
            in: directory, preBuild: "true", libraryPaths: [library])
        _ = FileManager.default.createFile(atPath: product, contents: Data())
        #expect(try unchanged.runPreBuild() == nil)
        #expect(FileManager.default.fileExists(atPath: product))
    }
}

@Suite("Watching more than Swift")
struct ExtraWatchTests {
    private func makeRoot() throws -> (app: String, crates: String, cleanup: () -> Void) {
        let root = try makeDirectory()
        let app = root + "/ios"
        let crates = root + "/crates"
        for directory in [
            app + "/Sources/App", crates + "/core/src", crates + "/core/target/debug",
        ] {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true)
        }
        try "".write(toFile: crates + "/core/src/lib.rs", atomically: true, encoding: .utf8)
        try "".write(toFile: crates + "/core/Cargo.toml", atomically: true, encoding: .utf8)
        try "".write(toFile: root + "/Cargo.lock", atomically: true, encoding: .utf8)
        return (app, crates, { try? FileManager.default.removeItem(atPath: root) })
    }

    @Test("An edit to a Rust file under an extra path is a change")
    func rustSource() throws {
        let (app, crates, cleanup) = try makeRoot()
        defer { cleanup() }
        let watcher = SourceWatcher(root: app, extraPaths: [crates])
        #expect(!watcher.waitForChanges(timeout: 0.1))
        try "fn a() {}".write(
            toFile: crates + "/core/src/lib.rs", atomically: true, encoding: .utf8)
        #expect(watcher.waitForChanges(timeout: 2))
        #expect(!watcher.checkForChanges(), "One save is one change")

        // Without the extra path, the same edit is not a change.
        let plain = SourceWatcher(root: app)
        try "fn b() {}".write(
            toFile: crates + "/core/src/lib.rs", atomically: true, encoding: .utf8)
        #expect(!plain.waitForChanges(timeout: 0.2))
    }

    @Test("Cargo's target directory and editors' temporary files are not changes")
    func ignored() throws {
        let (app, crates, cleanup) = try makeRoot()
        defer { cleanup() }
        let watcher = SourceWatcher(root: app, extraPaths: [crates])
        try "x".write(
            toFile: crates + "/core/target/debug/libcore.rlib", atomically: false, encoding: .utf8)
        try FileManager.default.createDirectory(
            atPath: crates + "/core/target/debug/incremental", withIntermediateDirectories: true)
        try FileManager.default.removeItem(atPath: crates + "/core/target/debug/incremental")
        try "x".write(toFile: crates + "/core/src/.lib.rs.swp", atomically: false, encoding: .utf8)
        try "x".write(toFile: crates + "/core/src/lib.rs~", atomically: false, encoding: .utf8)
        #expect(!watcher.waitForChanges(timeout: 0.2))
    }

    @Test("A new file in a new directory under an extra path is a change")
    func newDirectory() throws {
        let (app, crates, cleanup) = try makeRoot()
        defer { cleanup() }
        let watcher = SourceWatcher(root: app, extraPaths: [crates])
        try FileManager.default.createDirectory(
            atPath: crates + "/ffi/src", withIntermediateDirectories: true)
        _ = watcher.waitForChanges(timeout: 0.1)
        try "x".write(toFile: crates + "/ffi/src/lib.rs", atomically: false, encoding: .utf8)
        #expect(watcher.waitForChanges(timeout: 2))
    }

    @Test("A single file is watched, and its neighbors are not")
    func file() throws {
        let (app, crates, cleanup) = try makeRoot()
        defer { cleanup() }
        let manifest = crates + "/core/Cargo.toml"
        let watcher = SourceWatcher(root: app, extraPaths: [manifest])
        try "x".write(toFile: crates + "/core/README.md", atomically: false, encoding: .utf8)
        #expect(!watcher.waitForChanges(timeout: 0.2))
        try "[package]".write(toFile: manifest, atomically: true, encoding: .utf8)
        #expect(watcher.waitForChanges(timeout: 2))
    }

    @Test("Modification times find the same changes, where inotify is missing")
    func snapshots() throws {
        let (app, crates, cleanup) = try makeRoot()
        defer { cleanup() }
        let before = SourceWatcher.snapshot(of: app, extraPaths: [crates])
        #expect(before.keys.contains(crates + "/core/src/lib.rs"))
        #expect(before.keys.contains(crates + "/core/Cargo.toml"))
        #expect(!before.keys.contains { $0.contains("/target/") })
        try "x".write(
            toFile: crates + "/core/target/debug/libcore.rlib", atomically: false, encoding: .utf8)
        #expect(SourceWatcher.snapshot(of: app, extraPaths: [crates]) == before)
        // A path that is missing is skipped.
        #expect(SourceWatcher.snapshot(of: app, extraPaths: [crates + "/nope"]).isEmpty)
    }
}
