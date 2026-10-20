import Foundation

/// What `parhelion run` builds and runs for a package.
public struct RunPlan: Equatable, Sendable {
    /// The package that `swift build` runs in: the app's own package, or a
    /// generated runner package.
    public var buildPackagePath: String
    /// The executable product to build.
    public var product: String
    /// The directory whose sources trigger a rebuild when they change.
    public var watchRoot: String
    /// A generated runner package, when the app is a library.
    public var runner: Runner?

    public struct Runner: Equatable, Sendable {
        public var directory: String
        public var manifest: String
        /// Symbolic links to create, from a path in the runner to an app
        /// source directory.
        public var links: [String: String]
    }

    public enum PlanError: Error, CustomStringConvertible, Equatable {
        case noApp
        case ambiguous([String])
        case noSuchProduct(String)

        public var description: String {
            switch self {
            case .noApp:
                "The package has no executable or library product to run."
            case .ambiguous(let names):
                "The package has several apps: \(names.joined(separator: ", ")). Choose one with --product."
            case .noSuchProduct(let name):
                "The package has no product named \(name)."
            }
        }
    }

    /// Chooses what to run.
    ///
    /// An executable product is built as it is. A library product, the
    /// shape `xtool` apps use, is built through a generated runner package
    /// that compiles the library's sources as an executable, so that its
    /// `@main` type becomes the entry point.
    public static func make(
        for package: AppPackage, at packagePath: String, product: String?
    )
        throws -> RunPlan
    {
        let root = URL(fileURLWithPath: packagePath).standardizedFileURL.path
        // SwiftPM gives every executable target a product of the same name,
        // even when the manifest does not declare one.
        var executables = package.products.filter(\.isExecutable)
        for target in package.targets where target.kind == .executable {
            if !executables.contains(where: { $0.name == target.name }) {
                executables.append(
                    AppPackage.Product(
                        name: target.name, isExecutable: true, targets: [target.name])
                )
            }
        }
        let libraries = package.products.filter { !$0.isExecutable }

        let chosen: AppPackage.Product
        if let product {
            guard let match = (executables + libraries).first(where: { $0.name == product }) else {
                throw PlanError.noSuchProduct(product)
            }
            chosen = match
        } else if executables.count == 1 {
            chosen = executables[0]
        } else if executables.count > 1 {
            throw PlanError.ambiguous(executables.map(\.name))
        } else if libraries.count == 1 {
            chosen = libraries[0]
        } else if libraries.count > 1 {
            throw PlanError.ambiguous(libraries.map(\.name))
        } else {
            throw PlanError.noApp
        }

        if chosen.isExecutable {
            return RunPlan(
                buildPackagePath: root, product: chosen.name, watchRoot: root, runner: nil)
        }
        guard
            let appTarget = chosen.targets.first.flatMap({ name in
                package.targets.first { $0.name == name }
            })
        else { throw PlanError.noApp }

        let directory = root + "/.build/parhelion-runner"
        let runner = RunnerGenerator(package: package, packageRoot: root)
            .runner(appTarget: appTarget, directory: directory)
        return RunPlan(
            buildPackagePath: directory,
            product: appTarget.name,
            watchRoot: root,
            runner: runner
        )
    }

    /// Writes the runner package, if there is one.
    public func prepare() throws {
        guard let runner else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            atPath: runner.directory + "/Sources",
            withIntermediateDirectories: true
        )
        for (link, destination) in runner.links {
            let linkPath = runner.directory + "/" + link
            if (try? fileManager.destinationOfSymbolicLink(atPath: linkPath)) == destination {
                continue
            }
            try? fileManager.removeItem(atPath: linkPath)
            try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: destination)
        }
        let manifestPath = runner.directory + "/Package.swift"
        // Rewriting an unchanged manifest would make SwiftPM resolve again.
        if fileManager.contents(atPath: manifestPath) != Data(runner.manifest.utf8) {
            try runner.manifest.write(toFile: manifestPath, atomically: true, encoding: .utf8)
        }
    }
}

/// Generates the manifest of a runner package for a library-shaped app.
struct RunnerGenerator {
    let package: AppPackage
    let packageRoot: String

    func runner(appTarget: AppPackage.Target, directory: String) -> RunPlan.Runner {
        let targets = localTargetClosure(of: appTarget)
        var links: [String: String] = [:]
        var declarations: [String] = []
        for target in targets {
            links["Sources/\(target.name)"] = packageRoot + "/" + target.path
            let kind = target.name == appTarget.name ? "executableTarget" : "target"
            let dependencies = target.dependencies.map(render).joined(separator: ",\n")
            declarations.append(
                """
                        .\(kind)(
                            name: \(quote(target.name)),
                            dependencies: [
                \(indent(dependencies, by: 16))
                            ],
                            path: \(quote("Sources/\(target.name)"))
                        )
                """
            )
        }

        let version = package.toolsVersion.split(separator: ".").prefix(2).joined(separator: ".")
        var settings = ""
        if let modes = package.swiftLanguageModes, !modes.isEmpty,
            (Double(version) ?? 6) >= 6
        {
            let rendered = modes.map { ".v" + $0.replacingOccurrences(of: ".", with: "_") }
            settings = ",\n    swiftLanguageModes: [\(rendered.joined(separator: ", "))]"
        }

        let manifest = """
            // swift-tools-version: \(version)
            // Generated by `parhelion run` for \(package.name). Do not edit: it is
            // rewritten on every run.

            import PackageDescription

            let package = Package(
                name: "ParhelionRunner",
                dependencies: [
            \(indent(package.dependencies.map(render).joined(separator: ",\n"), by: 8))
                ],
                targets: [
            \(declarations.joined(separator: ",\n"))
                ]\(settings)
            )

            """
        return RunPlan.Runner(directory: directory, manifest: manifest, links: links)
    }

    /// The app target and every target of the same package it depends on.
    private func localTargetClosure(of root: AppPackage.Target) -> [AppPackage.Target] {
        var result: [AppPackage.Target] = []
        var pending = [root]
        var seen: Set<String> = []
        while let target = pending.popLast() {
            guard seen.insert(target.name).inserted else { continue }
            result.append(target)
            for case .byName(let name, _) in target.dependencies {
                if let local = package.targets.first(where: { $0.name == name }) {
                    pending.append(local)
                }
            }
        }
        return result
    }

    private func render(_ dependency: AppPackage.PackageDependency) -> String {
        switch dependency {
        case .fileSystem(let name, let path):
            return ".package(name: \(quote(name)), path: \(quote(path)))"
        case .sourceControl(let url, let requirement):
            switch requirement {
            case .range(let lower, let upper):
                return ".package(url: \(quote(url)), \(quote(lower))..<\(quote(upper)))"
            case .exact(let version):
                return ".package(url: \(quote(url)), exact: \(quote(version)))"
            case .branch(let branch):
                return ".package(url: \(quote(url)), branch: \(quote(branch)))"
            case .revision(let revision):
                return ".package(url: \(quote(url)), revision: \(quote(revision)))"
            }
        }
    }

    private func render(_ dependency: AppPackage.TargetDependency) -> String {
        switch dependency {
        case .product(let name, let package, let platforms):
            return
                ".product(name: \(quote(name)), package: \(quote(package))\(condition(platforms)))"
        case .byName(let name, let platforms):
            if package.targets.contains(where: { $0.name == name }) {
                return ".target(name: \(quote(name))\(condition(platforms)))"
            }
            return ".byName(name: \(quote(name))\(condition(platforms)))"
        }
    }

    private func condition(_ platforms: [String]?) -> String {
        guard let platforms, !platforms.isEmpty else { return "" }
        let names: [String: String] = [
            "linux": ".linux", "ios": ".iOS", "macos": ".macOS", "tvos": ".tvOS",
            "watchos": ".watchOS", "visionos": ".visionOS", "maccatalyst": ".macCatalyst",
            "driverkit": ".driverKit", "android": ".android", "windows": ".windows",
            "wasi": ".wasi", "openbsd": ".openbsd",
        ]
        let rendered = platforms.map { names[$0] ?? ".custom(\(quote($0)))" }
        return ", condition: .when(platforms: [\(rendered.joined(separator: ", "))])"
    }

    private func quote(_ string: String) -> String {
        "\""
            + string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func indent(_ text: String, by spaces: Int) -> String {
        let padding = String(repeating: " ", count: spaces)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : padding + $0 }
            .joined(separator: "\n")
    }
}
