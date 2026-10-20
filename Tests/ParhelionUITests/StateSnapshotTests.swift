import Foundation
import Testing

@testable import ParhelionUI

private struct Profile: Codable, Equatable {
    var name: String
    var age: Int
}

private struct Screen: View {
    @State private var count = 0
    @State private var title = "Start"
    @State private var profile = Profile(name: "Ada", age: 36)
    @State private var action: () -> Void = {}  // Not Codable: never saved.

    var body: some View {
        VStack {
            Text("\(title) \(count) \(profile.name)")
            Button("Change") {
                count = 7
                title = "Saved"
                profile = Profile(name: "Grace", age: 85)
            }
        }
    }
}

private struct RenamedState: View {
    @State private var count = "a string now"

    var body: some View {
        Text(count)
    }
}

@MainActor
@Suite("State snapshots")
struct StateSnapshotTests {
    @Test("Codable state survives a snapshot and restore")
    func roundTrip() throws {
        let first = ViewHost(Screen())
        try first.tapButton(labeled: "Change")
        let snapshot = first.stateSnapshot()

        let second = ViewHost(Screen(), restoring: snapshot)
        #expect(second.nodes(withText: "Saved 7 Grace").count == 1)
    }

    @Test("The snapshot is readable JSON keyed by structural position")
    func format() throws {
        let host = ViewHost(Screen())
        let values = try JSONDecoder().decode([String: String].self, from: host.stateSnapshot())
        #expect(values["Screen._count"] == "0")
        #expect(values["Screen._title"] == "\"Start\"")
        #expect(values["Screen._action"] == nil)
    }

    @Test("State whose type changed starts from its initial value")
    func typeChange() {
        let snapshot = Data(#"{"RenamedState._count": "5"}"#.utf8)
        let host = ViewHost(RenamedState(), restoring: snapshot)
        #expect(host.nodes(withText: "a string now").count == 1)
    }

    @Test("An unreadable snapshot is ignored")
    func badSnapshot() {
        let host = ViewHost(Screen(), restoring: Data("not json".utf8))
        #expect(host.nodes(withText: "Start 0 Ada").count == 1)
    }
}
