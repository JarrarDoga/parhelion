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
            )
        )
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
