import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Images from an app's asset catalog.
//
// On Linux, SwiftPM copies an `Assets.xcassets` folder in an app's target,
// unprocessed, into the target's `<Package>_<Target>.bundle` beside the
// executable, and generates `Bundle.module` for it (research for #30,
// section 4.2, measured with Swift 6.4.1). So Parhelion reads the raw
// catalog: each image set's `Contents.json` and its files. The layout is
// Apple's Asset Catalog Format Reference
// (https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/ImageSetType.html),
// and dark appearances follow xtool's AssetKit schema
// (https://github.com/xtool-org/AssetKit/blob/main/Sources/AssetKit/Schema/Contents.swift).

/// One image set in an asset catalog.
struct ImageAsset: Sendable {
    /// One file of an image set.
    struct Entry: Sendable {
        var url: URL
        /// The scale the file is drawn at: 1, 2, or 3.
        var scale: Int
        /// Whether the file is for the dark appearance.
        var isDark: Bool
    }

    var entries: [Entry]
    /// Whether the set renders as a template, from its
    /// `template-rendering-intent`, or from its name ending in `Template`
    /// when it has none.
    var isTemplate: Bool

    /// The files for an appearance: the dark ones when asked for and there
    /// are any, and otherwise the others, or any at all.
    func entries(dark: Bool) -> [Entry] {
        let matching = entries.filter { $0.isDark == dark }
        return matching.isEmpty ? entries : matching
    }

    /// Whether the set has files for the dark appearance.
    var hasDarkEntries: Bool { entries.contains(where: \.isDark) }

    /// The file to draw at a number of pixels per point: the smallest
    /// scale at least as large, or else the largest.
    static func entry(in entries: [Entry], forScale scale: Double) -> Entry? {
        let sorted = entries.sorted { $0.scale < $1.scale }
        return sorted.first { Double($0.scale) >= scale - 0.01 } ?? sorted.last
    }
}

/// Finds images in apps' asset catalogs, reads their sizes, and decodes
/// them, keeping what it learns. Images that `AsyncImage` loads are kept
/// here too, by their URL.
///
/// It is shared by every host in the process. Decoded images are kept up
/// to `byteLimit` bytes, the least recently drawn going first.
final class ImageLibrary: @unchecked Sendable {
    static let shared = ImageLibrary()
    static let byteLimit = 256 << 20

    private let lock = NSLock()
    private var catalogs: [URL: [String: URL]] = [:]
    private var assets: [String: ImageAsset?] = [:]
    private var sizes: [URL: (width: Int, height: Int)?] = [:]
    private var bundles: [String: URL] = [:]
    private var decoded: [String: [Bitmap]] = [:]
    private var order: [String] = []
    private var bytes = 0
    private var warned: Set<String> = []

    // MARK: - Finding image sets

    /// The name a bundle is recorded by, its folder's name without
    /// `.bundle`, after remembering where it is.
    func register(bundle url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        lock.lock()
        defer { lock.unlock() }
        bundles[name] = url
        return name
    }

    /// The image set with a name, in the bundle recorded by a name, or, for
    /// `nil`, in the main bundle and every bundle beside it, where SwiftPM
    /// puts an app's resources on Linux.
    func asset(named name: String, bundle: String?) -> ImageAsset? {
        let key = (bundle ?? "") + "\u{0}" + name
        lock.lock()
        if let known = assets[key] {
            lock.unlock()
            return known
        }
        let directories: [URL]
        if let bundle {
            directories = bundles[bundle].map { [$0] } ?? []
        } else {
            directories = Self.searchDirectories()
        }
        lock.unlock()
        var found: ImageAsset?
        for directory in directories {
            if let set = imageSets(in: directory)[name] {
                found = Self.readImageSet(set, name: name)
                break
            }
        }
        lock.lock()
        assets[key] = found
        lock.unlock()
        return found
    }

    /// The main bundle's folder and the bundles in it.
    private static func searchDirectories() -> [URL] {
        let main = Bundle.main.bundleURL
        let siblings =
            (try? FileManager.default.contentsOfDirectory(
                at: main, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "bundle" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        return [main] + siblings
    }

    /// The image sets of the catalogs in a folder, or one level below it,
    /// by name.
    private func imageSets(in directory: URL) -> [String: URL] {
        lock.lock()
        if let known = catalogs[directory] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let fileManager = FileManager.default
        var found: [String: URL] = [:]
        let children =
            (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        var candidates = children.filter { $0.pathExtension == "xcassets" }
        for child in children where child.hasDirectoryPath && child.pathExtension != "xcassets" {
            candidates +=
                ((try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil))
                ?? []).filter { $0.pathExtension == "xcassets" }
        }
        for catalog in candidates.sorted(by: { $0.path < $1.path }) {
            Self.collectImageSets(in: catalog, prefix: "", into: &found)
        }
        lock.lock()
        catalogs[directory] = found
        lock.unlock()
        return found
    }

    /// Adds the image sets in a catalog folder to `found`. A group whose
    /// `Contents.json` says it provides a namespace prefixes the names
    /// inside it with its own, as in `mammals/Llama`.
    private static func collectImageSets(
        in folder: URL, prefix: String, into found: inout [String: URL]
    ) {
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            let name = child.deletingPathExtension().lastPathComponent
            switch child.pathExtension {
            case "imageset":
                if found[prefix + name] == nil { found[prefix + name] = child }
            case "":
                guard child.hasDirectoryPath || isDirectory(child) else { continue }
                let contents = try? JSONDecoder().decode(
                    GroupContents.self,
                    from: Data(contentsOf: child.appendingPathComponent("Contents.json")))
                let namespace = contents?.properties?.providesNamespace == true
                collectImageSets(
                    in: child, prefix: namespace ? prefix + name + "/" : prefix, into: &found)
            default:
                continue
            }
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Reads an image set's `Contents.json`: the files for iPhones, or
    /// for every device, by scale and appearance.
    private static func readImageSet(_ folder: URL, name: String) -> ImageAsset? {
        guard
            let data = try? Data(contentsOf: folder.appendingPathComponent("Contents.json")),
            let contents = try? JSONDecoder().decode(ImageSetContents.self, from: data)
        else { return nil }
        let images = contents.images ?? []
        let forPhone = images.filter { $0.idiom == "iphone" }
        let universal = images.filter { $0.idiom == nil || $0.idiom == "universal" }
        let chosen = forPhone.contains { $0.filename != nil } ? forPhone : universal
        let entries = chosen.compactMap { image -> ImageAsset.Entry? in
            guard let filename = image.filename else { return nil }
            let isDark =
                image.appearances?.contains {
                    $0.appearance == "luminosity" && $0.value == "dark"
                } ?? false
            // A file without a scale is for any scale; Apple says it should
            // be a PDF, which Parhelion does not draw, so it counts as 1×.
            let scale = image.scale.flatMap { Int($0.dropLast()) } ?? 1
            return ImageAsset.Entry(
                url: folder.appendingPathComponent(filename), scale: scale, isDark: isDark)
        }
        // Assumed: Xcode writes the intent under the set's properties, and
        // older catalogs per image; both are read.
        let intent =
            contents.properties?.templateRenderingIntent
            ?? images.lazy.compactMap(\.templateRenderingIntent).first
        let isTemplate = intent.map { $0 == "template" } ?? name.hasSuffix("Template")
        return ImageAsset(entries: entries, isTemplate: isTemplate)
    }

    // MARK: - Sizes and pixels

    /// The size in pixels of a PNG file, from its header, or `nil` if it is
    /// not a PNG image Parhelion can read.
    func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        lock.lock()
        if let known = sizes[url] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let size = (try? Data(contentsOf: url)).flatMap { Bitmap.pngSize([UInt8]($0)) }
        lock.lock()
        sizes[url] = size
        lock.unlock()
        return size
    }

    /// A file's pixels, decoded, with smaller levels for drawing it small,
    /// or `nil` if it is not a PNG image Parhelion can read.
    func levels(of url: URL) -> [Bitmap]? {
        if let known = kept(url.path) { return known }
        guard let data = try? Data(contentsOf: url),
            let bitmap = try? Bitmap(pngData: [UInt8](data))
        else { return nil }
        return keep([bitmap], for: url.path)
    }

    /// Keeps an image that `AsyncImage` loaded, by its URL.
    func store(_ bitmap: Bitmap, for key: String) {
        _ = keep([bitmap], for: "url:" + key)
    }

    /// An image that `AsyncImage` loaded, with smaller levels.
    func loaded(_ key: String) -> [Bitmap]? {
        kept("url:" + key)
    }

    /// The decoded levels kept for a key, marking them as just used.
    private func kept(_ key: String) -> [Bitmap]? {
        lock.lock()
        defer { lock.unlock() }
        guard let levels = decoded[key] else { return nil }
        if order.last != key, let index = order.lastIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return levels
    }

    private func keep(_ levels: [Bitmap], for key: String) -> [Bitmap] {
        lock.lock()
        defer { lock.unlock() }
        if let old = decoded.removeValue(forKey: key) {
            bytes -= old.reduce(0) { $0 + $1.pixels.count }
            order.removeAll { $0 == key }
        }
        decoded[key] = levels
        order.append(key)
        bytes += levels.reduce(0) { $0 + $1.pixels.count }
        while bytes > Self.byteLimit, order.count > 1 {
            let oldest = order.removeFirst()
            bytes -= decoded.removeValue(forKey: oldest)?.reduce(0) { $0 + $1.pixels.count } ?? 0
        }
        return levels
    }

    /// Adds a smaller level to a key's levels, for drawing it at a fraction
    /// of its size, and returns the level that `width` pixels should
    /// sample: the smallest one at least half as wide as the drawing.
    func level(of levels: [Bitmap], key: String, forWidth width: Double) -> Bitmap {
        var levels = levels
        while let last = levels.last, Double(last.width) >= width * 4, last.width > 1 {
            levels.append(last.halved())
        }
        if levels.count > 1 { _ = keep(levels, for: key) }
        return levels.last { Double($0.width) >= width * 2 } ?? levels[0]
    }

    /// Writes a warning, once per name, that an image is missing.
    func warnMissing(_ name: String) {
        lock.lock()
        let isNew = warned.insert(name).inserted
        lock.unlock()
        guard isNew else { return }
        FileHandle.standardError.write(
            Data(
                "parhelion: no PNG image named '\(name)' in an asset catalog; it draws as a missing image.\n"
                    .utf8))
    }
}

/// The parts of an image set's `Contents.json` that Parhelion reads.
private struct ImageSetContents: Decodable {
    struct Image: Decodable {
        var filename: String?
        var idiom: String?
        var scale: String?
        var appearances: [Appearance]?
        var templateRenderingIntent: String?

        enum CodingKeys: String, CodingKey {
            case filename, idiom, scale, appearances
            case templateRenderingIntent = "template-rendering-intent"
        }
    }

    struct Appearance: Decodable {
        var appearance: String
        var value: String
    }

    struct Properties: Decodable {
        var templateRenderingIntent: String?

        enum CodingKeys: String, CodingKey {
            case templateRenderingIntent = "template-rendering-intent"
        }
    }

    var images: [Image]?
    var properties: Properties?
}

/// The parts of a group's `Contents.json` that Parhelion reads.
private struct GroupContents: Decodable {
    struct Properties: Decodable {
        var providesNamespace: Bool?

        enum CodingKeys: String, CodingKey {
            case providesNamespace = "provides-namespace"
        }
    }

    var properties: Properties?
}

extension Image {
    /// The attributes of an asset image's node: its name; its bundle's name
    /// when one was given; its size in points, from its largest file; the
    /// dark appearance when the environment and the set have one; whether
    /// it renders as a template; and `missingImage` when there is no image
    /// set with the name, or none of its files is a PNG image.
    func assetAttributes(
        _ name: String, bundlePath: String?, in environment: EnvironmentValues
    ) -> [String: String] {
        let library = ImageLibrary.shared
        var attributes = ["name": name]
        let bundle = bundlePath.map { library.register(bundle: URL(fileURLWithPath: $0)) }
        if let bundle { attributes["bundle"] = bundle }
        guard let asset = library.asset(named: name, bundle: bundle) else {
            library.warnMissing(name)
            attributes["missingImage"] = "true"
            return attributes
        }
        let dark = environment.colorScheme == .dark && asset.hasDarkEntries
        if dark { attributes["appearance"] = "dark" }
        // Assumed: each file has the same size in points, so the largest
        // one gives it.
        guard let entry = asset.entries(dark: dark).max(by: { $0.scale < $1.scale }),
            let pixels = library.pixelSize(of: entry.url)
        else {
            library.warnMissing(name)
            attributes["missingImage"] = "true"
            return attributes
        }
        attributes["size"] = formatSize(
            CGSize(
                width: CGFloat(pixels.width) / CGFloat(entry.scale),
                height: CGFloat(pixels.height) / CGFloat(entry.scale)))
        if renderingMode.map({ $0 == .template }) ?? asset.isTemplate {
            attributes["renderingMode"] = "template"
        } else if renderingMode == .original {
            attributes["renderingMode"] = "original"
        }
        return attributes
    }
}

/// Formats a size as the tree records it: `40 × 30.5`.
func formatSize(_ size: CGSize) -> String {
    "\(formatPoints(size.width)) × \(formatPoints(size.height))"
}

/// Reads a size that `formatSize(_:)` wrote.
func parseSize(_ text: String?) -> CGSize? {
    guard let parts = text?.components(separatedBy: " × "), parts.count == 2,
        let width = Double(parts[0]), let height = Double(parts[1])
    else { return nil }
    return CGSize(width: width, height: height)
}
