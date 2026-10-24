import ParhelionPreview

#if canImport(Foundation)
import Foundation
#endif

/// The structure and behavior of an app, mirroring SwiftUI's `App`.
///
/// Mark your type with `@main`. When the `parhelion` window host launches the
/// app, `main()` runs it in the preview window. Otherwise it runs the app
/// without a window: it resolves and lays out the first window's content and
/// prints the view tree. Pass `--frames` to include each node's frame, `--ids`
/// to include identifiers, or `--json` to print the tree as JSON. Pass
/// `--png PATH` to draw the screen to a PNG file instead, with the status bar
/// and the home indicator, at `--scale` pixels per point (2 by default). Set
/// `PARHELION_DEVICE` to a preset's name, such as "iPhone 17 Pro", to
/// simulate that device, `PARHELION_COLOR_SCHEME` to `dark` for the dark
/// appearance, and `PARHELION_DYNAMIC_TYPE_SIZE` to a size such as
/// `accessibility2` for larger text. Without a window, the app first lets `task` work
/// finish, for up to five seconds, so that the output shows what it loaded.
///
/// The app's own `@State` belongs to the host, as a view's does: it is
/// keyed by the app's type name, kept in state snapshots, and changing it
/// updates the tree.
@MainActor
@preconcurrency
public protocol App {
    associatedtype Body: Scene

    @SceneBuilder
    var body: Body { get }

    init()
}

extension App {
    public static func main() {
        let app = Self()
        guard windowContent(of: app.body) != nil else {
            FileHandle.standardError.write(Data("parhelion: the app declares no window.\n".utf8))
            exit(1)
        }
        let content = AppRoot(app: app)
        #if canImport(Glibc)
        let appName = String(describing: Self.self)
        if PreviewSession.runIfRequested(content: content, appName: appName) { return }
        #endif
        let appearance = simulatedAppearance()
        let host = ViewHost(
            anyRootView: content, device: simulatedDevice(), colorScheme: appearance.colorScheme,
            dynamicTypeSize: appearance.dynamicTypeSize)
        host.runTasks(until: Date(timeIntervalSinceNow: 5))
        let arguments = CommandLine.arguments
        if let pngPath = value(after: "--png", in: arguments) {
            let scale = value(after: "--scale", in: arguments).flatMap(Double.init) ?? 2
            do {
                try host.render(scale: scale, chrome: .systemBars).pngData()
                    .write(to: URL(fileURLWithPath: pngPath))
            } catch {
                FileHandle.standardError.write(Data("parhelion: \(error)\n".utf8))
                exit(1)
            }
        } else if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(host.root)) ?? Data()
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(
                host.root.outline(
                    includeIDs: arguments.contains("--ids"),
                    includeFrames: arguments.contains("--frames")
                )
            )
        }
    }
}

/// The device `PARHELION_DEVICE` names, or iPhone 16. Exits with a message
/// listing the presets if the name is unknown.
func simulatedDevice() -> Device {
    do {
        return try Device.simulated(
            named: ProcessInfo.processInfo.environment[previewDeviceEnvironmentKey])
    } catch {
        FileHandle.standardError.write(Data("parhelion: \(error)\n".utf8))
        exit(1)
    }
}

/// The appearance and text size that `PARHELION_COLOR_SCHEME` and
/// `PARHELION_DYNAMIC_TYPE_SIZE` name, or light at the Large size. Exits with
/// a message listing the names if one is unknown.
func simulatedAppearance() -> (colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize) {
    let environment = ProcessInfo.processInfo.environment
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("parhelion: \(message)\n".utf8))
        exit(1)
    }
    var colorScheme = ColorScheme.light
    if let name = environment[previewColorSchemeEnvironmentKey] {
        guard let scheme = ColorScheme(name: name) else {
            fail("\(previewColorSchemeEnvironmentKey) is \"\(name)\". Use light or dark.")
        }
        colorScheme = scheme
    }
    var dynamicTypeSize = DynamicTypeSize.large
    if let name = environment[previewDynamicTypeSizeEnvironmentKey] {
        guard let size = DynamicTypeSize(name: name) else {
            let names = DynamicTypeSize.allCases.map(\.name).joined(separator: ", ")
            fail(
                "\(previewDynamicTypeSizeEnvironmentKey) is \"\(name)\". Use one of: \(names).")
        }
        dynamicTypeSize = size
    }
    return (colorScheme, dynamicTypeSize)
}

/// The argument that follows `flag`, as in `--png out.png`.
private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

/// A part of an app's user interface with a lifecycle managed by the system.
@MainActor
@preconcurrency
public protocol Scene {
    associatedtype Body: Scene

    @SceneBuilder
    var body: Body { get }
}

extension Never: Scene {}

/// Builds scenes from closures.
@MainActor
@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content {
        content
    }
}

@MainActor
protocol WindowContentProviding {
    var windowContent: any View { get }
}

/// A scene that presents a window of the given content.
public struct WindowGroup<Content: View>: Scene {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        fatalError("WindowGroup is a primitive scene and has no body.")
    }
}

extension WindowGroup: WindowContentProviding {
    var windowContent: any View { content }
}

/// The root view of an app. It installs the app's own dynamic properties,
/// such as `@State`, the way the evaluator installs a view's, and then
/// evaluates the first window's content in its place, so that the content's
/// identifiers do not change.
struct AppRoot<Root: App>: View {
    typealias Body = Never

    let app: Root

    var body: Never {
        fatalError("AppRoot is a primitive view and has no body.")
    }
}

extension AppRoot: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.installDynamicProperties(of: app, at: path.appending(baseTypeName(of: Root.self)))
        guard let content = windowContent(of: app.body) else { return [] }
        return evaluator.evaluate(content, at: path)
    }
}

@MainActor
private func windowContent(of scene: any Scene) -> (any View)? {
    if let window = scene as? any WindowContentProviding {
        return window.windowContent
    }
    if scene is Never { return nil }
    return windowContent(of: sceneBody(of: scene))
}

@MainActor
private func sceneBody<S: Scene>(of scene: S) -> any Scene {
    scene.body
}
