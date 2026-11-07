import Foundation

/// The parts of a Swift package that `parhelion run` needs, read from
/// `swift package dump-package`.
public struct AppPackage: Equatable, Sendable {
    public struct Target: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case executable, regular, test, other
        }

        public var name: String
        public var kind: Kind
        /// The source directory, relative to the package root.
        public var path: String
        public var dependencies: [TargetDependency]
        /// Settings that a runner package must repeat, because the linker
        /// needs them to find the libraries that the target links.
        public var linkerSettings: [LinkerSetting] = []
    }

    /// A linker setting from a target's `linkerSettings`.
    public struct LinkerSetting: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// `.linkedLibrary(name)`.
            case library(String)
            /// `.unsafeFlags(flags)` for the linker.
            case unsafeFlags([String])
        }

        public var kind: Kind
        public var platforms: [String]?
    }

    public struct Product: Equatable, Sendable {
        public var name: String
        public var isExecutable: Bool
        public var targets: [String]
    }

    public enum TargetDependency: Equatable, Sendable {
        /// A product from another package.
        case product(name: String, package: String, platforms: [String]?)
        /// A target in this package, or a product of a dependency with the
        /// same name.
        case byName(String, platforms: [String]?)
    }

    public enum PackageDependency: Equatable, Sendable {
        /// A local package. `name` is what target dependencies call it.
        case fileSystem(name: String, path: String)
        case sourceControl(url: String, requirement: Requirement)

        public enum Requirement: Equatable, Sendable {
            case range(lower: String, upper: String)
            case exact(String)
            case branch(String)
            case revision(String)
        }
    }

    public var name: String
    public var toolsVersion: String
    public var swiftLanguageModes: [String]?
    public var dependencies: [PackageDependency]
    public var targets: [Target]
    public var products: [Product]

    public enum InspectionError: Error, CustomStringConvertible {
        case dumpFailed(String)
        case unsupported(String)

        public var description: String {
            switch self {
            case .dumpFailed(let output): "Could not read the package:\n\(output)"
            case .unsupported(let detail): detail
            }
        }
    }

    /// Reads the package at `path` with `swift package dump-package`.
    public static func load(at path: String) throws -> AppPackage {
        let result = try Shell.run(
            "swift",
            ["package", "dump-package", "--package-path", path],
            captureOutput: true
        )
        guard result.status == 0 else { throw InspectionError.dumpFailed(result.output) }
        return try parse(Data(result.output.utf8))
    }

    /// Parses the JSON that `swift package dump-package` prints.
    public static func parse(_ json: Data) throws -> AppPackage {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw InspectionError.unsupported("The package description is not a JSON object.")
        }
        let toolsVersion =
            ((root["toolsVersion"] as? [String: Any])?["_version"] as? String) ?? "6.0.0"
        let modes = (root["swiftLanguageModes"] as? [Any])?.compactMap(languageMode)

        return AppPackage(
            name: root["name"] as? String ?? "App",
            toolsVersion: toolsVersion,
            swiftLanguageModes: modes,
            dependencies: try (root["dependencies"] as? [[String: Any]] ?? []).map(dependency),
            targets: (root["targets"] as? [[String: Any]] ?? []).map(target),
            products: (root["products"] as? [[String: Any]] ?? []).map(product)
        )
    }

    // MARK: - Parsing

    private static func languageMode(_ value: Any) -> String? {
        if let string = value as? String { return string }
        // Newer toolchains encode modes as {"version": ["6"]} or {"v6": {}}.
        if let object = value as? [String: Any], let key = object.keys.first {
            if let versions = object[key] as? [String], let version = versions.first {
                return version
            }
            return key.hasPrefix("v") ? String(key.dropFirst()) : key
        }
        return nil
    }

    private static func dependency(_ object: [String: Any]) throws -> PackageDependency {
        if let entry = (object["fileSystem"] as? [[String: Any]])?.first,
            let identity = entry["identity"] as? String,
            let path = entry["path"] as? String
        {
            // A path dependency declared with `name:` keeps that name for
            // target dependencies, while its identity comes from the
            // directory name.
            let name = entry["nameForTargetDependencyResolutionOnly"] as? String ?? identity
            return .fileSystem(name: name, path: path)
        }
        if let entry = (object["sourceControl"] as? [[String: Any]])?.first,
            let location = entry["location"] as? [String: Any],
            let remote = (location["remote"] as? [[String: Any]])?.first,
            let url = remote["urlString"] as? String,
            let requirement = entry["requirement"] as? [String: Any]
        {
            return .sourceControl(url: url, requirement: try self.requirement(requirement))
        }
        throw InspectionError.unsupported(
            "parhelion run supports path and Git dependencies only. Found: \(object.keys.sorted())"
        )
    }

    private static func requirement(
        _ object: [String: Any]
    ) throws
        -> PackageDependency.Requirement
    {
        if let range = (object["range"] as? [[String: Any]])?.first,
            let lower = range["lowerBound"] as? String,
            let upper = range["upperBound"] as? String
        {
            return .range(lower: lower, upper: upper)
        }
        if let exact = (object["exact"] as? [String])?.first { return .exact(exact) }
        if let branch = (object["branch"] as? [String])?.first { return .branch(branch) }
        if let revision = (object["revision"] as? [String])?.first { return .revision(revision) }
        throw InspectionError.unsupported(
            "Unsupported version requirement: \(object.keys.sorted())")
    }

    private static func target(_ object: [String: Any]) -> Target {
        let name = object["name"] as? String ?? ""
        let kind = Target.Kind(rawValue: object["type"] as? String ?? "") ?? .other
        let defaultPath = kind == .test ? "Tests/\(name)" : "Sources/\(name)"
        return Target(
            name: name,
            kind: kind,
            path: object["path"] as? String ?? defaultPath,
            dependencies: (object["dependencies"] as? [[String: Any]] ?? []).compactMap(
                targetDependency
            ),
            linkerSettings: (object["settings"] as? [[String: Any]] ?? []).compactMap(
                linkerSetting)
        )
    }

    private static func linkerSetting(_ object: [String: Any]) -> LinkerSetting? {
        guard object["tool"] as? String == "linker",
            let kind = object["kind"] as? [String: Any]
        else { return nil }
        let platforms = platforms(object["condition"])
        if let name = (kind["linkedLibrary"] as? [String: Any])?["_0"] as? String {
            return LinkerSetting(kind: .library(name), platforms: platforms)
        }
        if let flags = (kind["unsafeFlags"] as? [String: Any])?["_0"] as? [String] {
            return LinkerSetting(kind: .unsafeFlags(flags), platforms: platforms)
        }
        return nil
    }

    private static func platforms(_ condition: Any?) -> [String]? {
        (condition as? [String: Any])?["platformNames"] as? [String]
    }

    private static func targetDependency(_ object: [String: Any]) -> TargetDependency? {
        if let values = object["product"] as? [Any], let name = values.first as? String {
            let package = values.count > 1 ? values[1] as? String : nil
            return .product(
                name: name,
                package: package ?? name,
                platforms: values.count > 3 ? platforms(values[3]) : nil
            )
        }
        if let values = (object["byName"] ?? object["target"]) as? [Any],
            let name = values.first as? String
        {
            return .byName(name, platforms: values.count > 1 ? platforms(values[1]) : nil)
        }
        return nil
    }

    private static func product(_ object: [String: Any]) -> Product {
        let type = object["type"] as? [String: Any] ?? [:]
        return Product(
            name: object["name"] as? String ?? "",
            isExecutable: type["executable"] != nil,
            targets: object["targets"] as? [String] ?? []
        )
    }
}

/// What an app package tells `parhelion run` and `parhelion mcp` about
/// building it, read from `parhelion.json` in the package's directory.
///
/// ```json
/// {
///   "preBuild": "scripts/build-ios.sh --linux",
///   "watch": ["../crates", "../Cargo.toml"],
///   "libraryPaths": ["../target/debug"]
/// }
/// ```
///
/// Relative paths are relative to the package's directory. Every key is
/// optional.
public struct AppConfig: Equatable, Sendable {
    /// A shell command that runs in the package's directory before every
    /// `swift build`, such as one that builds a Rust library and generates
    /// its bindings. A failure stops the build and is reported like a Swift
    /// error. The command finds the build configuration, `debug` or
    /// `release`, in `PARHELION_CONFIGURATION`.
    public var preBuild: String?
    /// Files and directories besides the Swift sources whose changes rebuild
    /// the app. A directory counts with everything under it.
    public var watch: [String]
    /// Directories with prebuilt `.a` and `.so` libraries. The linker looks
    /// for the libraries that a target links in them, and the app finds a
    /// `.so` there when it starts.
    public var libraryPaths: [String]

    public init(preBuild: String? = nil, watch: [String] = [], libraryPaths: [String] = []) {
        self.preBuild = preBuild
        self.watch = watch
        self.libraryPaths = libraryPaths
    }

    public static let fileName = "parhelion.json"

    public enum ConfigError: Error, CustomStringConvertible, Equatable {
        case invalid(String)

        public var description: String {
            switch self {
            case .invalid(let detail): "Could not read \(AppConfig.fileName): \(detail)"
            }
        }
    }

    /// Reads the file in the package at `path`. A package without one gets
    /// the default configuration.
    public static func load(at path: String) throws -> AppConfig {
        let file = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        guard let data = FileManager.default.contents(atPath: file.path) else {
            return AppConfig()
        }
        return try parse(data)
    }

    public static func parse(_ json: Data) throws -> AppConfig {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ConfigError.invalid("it is not a JSON object.")
        }
        let known: Set<String> = ["preBuild", "watch", "libraryPaths"]
        if let unknown = root.keys.filter({ !known.contains($0) }).min() {
            throw ConfigError.invalid(
                "unknown key \"\(unknown)\". The keys are \(known.sorted().joined(separator: ", "))."
            )
        }
        func strings(_ key: String) throws -> [String] {
            guard let value = root[key] else { return [] }
            guard let list = value as? [String] else {
                throw ConfigError.invalid("\"\(key)\" must be a list of strings.")
            }
            return list
        }
        var preBuild: String?
        if let value = root["preBuild"] {
            guard let command = value as? String else {
                throw ConfigError.invalid("\"preBuild\" must be a string.")
            }
            preBuild = command.isEmpty ? nil : command
        }
        return AppConfig(
            preBuild: preBuild, watch: try strings("watch"),
            libraryPaths: try strings("libraryPaths"))
    }

    /// The configuration with the command-line options on top: the pre-build
    /// command replaces the file's, and paths add to its paths.
    public func overriding(
        preBuild: String?, watch: [String], libraryPaths: [String]
    ) -> AppConfig {
        AppConfig(
            preBuild: preBuild ?? self.preBuild,
            watch: self.watch + watch,
            libraryPaths: self.libraryPaths + libraryPaths)
    }
}
