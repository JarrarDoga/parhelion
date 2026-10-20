#if canImport(Foundation)
import Foundation
#endif

/// The structure and behavior of an app, mirroring SwiftUI's `App`.
///
/// Mark your type with `@main`. Under Parhelion, `main()` currently runs the app
/// without a window: it resolves and lays out the first window's content and
/// prints the view tree. Pass `--frames` to include each node's frame, `--ids`
/// to include identifiers, or `--json` to print the tree as JSON.
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
        guard let content = windowContent(of: app.body) else {
            FileHandle.standardError.write(Data("parhelion: the app declares no window.\n".utf8))
            exit(1)
        }
        let host = ViewHost(anyRootView: content)
        if CommandLine.arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(host.root)) ?? Data()
            print(String(decoding: data, as: UTF8.self))
        } else {
            let arguments = CommandLine.arguments
            print(
                host.root.outline(
                    includeIDs: arguments.contains("--ids"),
                    includeFrames: arguments.contains("--frames")
                )
            )
        }
    }
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
