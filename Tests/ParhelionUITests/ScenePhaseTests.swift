import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

@MainActor
private final class PhaseLog {
    var entries: [String] = []
}

private struct PhaseScreen: View {
    let log: PhaseLog
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack {
            Text("Phase \(scenePhase.name)")
            Text("Sync")
        }
        .onChange(of: scenePhase) { old, new in
            log.entries.append("\(old.name) -> \(new.name)")
        }
    }
}

private struct PhaseApp: App {
    @MainActor static var log = PhaseLog()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Text("Phase \(scenePhase.name)")
        }
        .onChange(of: scenePhase) { old, new in
            Self.log.entries.append("scene \(old.name) -> \(new.name)")
        }
    }
}

@MainActor
@Suite("scenePhase")
struct ScenePhaseTests {
    @Test("The scene is active until the host moves it, and the root records the other phases")
    func tree() {
        let host = ViewHost(PhaseScreen(log: PhaseLog()))
        #expect(host.scenePhase == .active)
        #expect(
            host.root.outline()
                == "Root\n└─ VStack\n   ├─ Text \"Phase active\"\n   └─ Text \"Sync\"")
        host.scenePhase = .inactive
        #expect(
            host.root.outline()
                == "Root scenePhase=inactive\n└─ VStack\n   ├─ Text \"Phase inactive\"\n   └─ Text \"Sync\""
        )
        host.scenePhase = .background
        #expect(host.root.attributes["scenePhase"] == "background")
        host.scenePhase = .active
        #expect(host.root.attributes["scenePhase"] == nil)
    }

    @Test("onChange(of: scenePhase) runs each time the app goes to the background and back")
    func backgroundAndForeground() {
        let log = PhaseLog()
        let host = ViewHost(PhaseScreen(log: log))
        #expect(log.entries.isEmpty)
        host.scenePhase = .background
        #expect(log.entries == ["active -> background"])
        host.scenePhase = .active
        #expect(log.entries == ["active -> background", "background -> active"])
        host.scenePhase = .background
        host.scenePhase = .active
        #expect(log.entries.count == 4)
        // Setting the phase it already has changes nothing.
        host.scenePhase = .active
        #expect(log.entries.count == 4)
    }

    @Test("The phase moves straight to the one set, and inactive is a phase of its own")
    func steps() {
        let log = PhaseLog()
        let host = ViewHost(PhaseScreen(log: log))
        host.scenePhase = .inactive
        host.scenePhase = .background
        host.scenePhase = .active
        #expect(
            log.entries == ["active -> inactive", "inactive -> background", "background -> active"])
    }

    @Test("The set-scene-phase command moves the scene and rejects an unknown phase")
    func command() {
        let log = PhaseLog()
        let host = ViewHost(PhaseScreen(log: log))
        let reply = host.execute(.setScenePhase("background"))
        #expect(reply.ok)
        #expect(reply.message == "The scene is background.")
        #expect(host.scenePhase == .background)
        #expect(log.entries == ["active -> background"])
        let bad = host.execute(.setScenePhase("asleep"))
        #expect(!bad.ok)
        #expect(bad.message.contains("Unknown scene phase"))
        #expect(host.scenePhase == .background)
        #expect(host.execute(.setScenePhase("active")).ok)
        #expect(log.entries.count == 2)
    }

    @Test("An App reads the phase, and Scene.onChange runs without changing node identity")
    func app() {
        PhaseApp.log = PhaseLog()
        let host = ViewHost(anyRootView: AppRoot(app: PhaseApp()))
        #expect(host.root.outline() == "Root\n└─ Text \"Phase active\"")
        let before = host.root.allNodes.map(\.id)
        host.scenePhase = .background
        #expect(host.root.outline() == "Root scenePhase=background\n└─ Text \"Phase background\"")
        host.scenePhase = .active
        #expect(
            PhaseApp.log.entries == ["scene active -> background", "scene background -> active"])
        #expect(host.root.allNodes.map(\.id) == before)
    }

    @Test("The phases have SwiftUI's names and ordering of cases")
    func names() {
        for phase in [ScenePhase.active, .inactive, .background] {
            #expect(ScenePhase(name: phase.name) == phase)
        }
        #expect(ScenePhase(name: "asleep") == nil)
        #expect(PreviewCapability.all.contains(PreviewCapability.scenePhase))
    }
}
