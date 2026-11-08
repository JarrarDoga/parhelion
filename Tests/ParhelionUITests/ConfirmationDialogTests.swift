import Foundation
import Testing

@testable import ParhelionUI

/// The size of the phone the sweep measured: 440 × 956 points.
private let phone = Device.named("iPhone 18 Pro Max")!

/// What the actions of a dialog did, in order.
@MainActor
private final class Log {
    var entries: [String] = []
}

private struct RemoveSong: View {
    let log: Log
    @State var shown = true

    var body: some View {
        Text("Behind the dialog")
            .confirmationDialog("Remove the song?", isPresented: $shown, titleVisibility: .visible)
        {
            Button("Remove from Library", role: .destructive) { log.entries.append("remove") }
            Button("Cancel", role: .cancel) { log.entries.append("cancel") }
        }
    }
}

@MainActor
@Suite("Confirmation dialog")
struct ConfirmationDialogTests {
    @Test("A dialog is a popover of its title and actions, without the cancel action")
    func tree() {
        let host = ViewHost(RemoveSong(log: Log()), device: phone)
        #expect(
            host.root.outline() == """
                Root
                ├─ Text "Behind the dialog"
                └─ ConfirmationDialog anchor=RemoveSong/Text label=Dismiss
                   └─ ConfirmationDialogPanel arrow=220,481 arrowEdge=bottom
                      ├─ Text "Remove the song?"
                      └─ Button role=destructive
                         └─ Text "Remove from Library"
                """)
    }

    @Test("The popover sits above the view, with its arrow's tip on the view's top edge")
    func placement() throws {
        let host = ViewHost(RemoveSong(log: Log()), device: phone)
        let text = try #require(host.root.children.first?.frame)
        let panel = try #require(
            host.root.allNodes.first { $0.kind == "ConfirmationDialogPanel" }?.frame)
        let button = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Remove from Library" }?
                .frame)
        // Measured on an iPhone on iOS 27: the arrow is 13 points long, the
        // action is a 48-point capsule 16 points inside the panel, and the
        // panel is centered on the view.
        #expect(panel.maxY == text.minY - 13)
        #expect(abs(panel.midX - text.midX) < 0.01)
        #expect(button.height == 48)
        #expect(button.minX == panel.minX + 16)
        #expect(button.maxY == panel.maxY - 16)
        #expect(abs(panel.height - (20 + 22 + 18 + 48 + 16)) < 0.01)
    }

    @Test("Without a visible title, the dialog shows only its actions")
    func hiddenTitle() {
        struct Dialog: View {
            @State var shown = true
            var body: some View {
                Text("Song")
                    .confirmationDialog("Remove the song?", isPresented: $shown) {
                        Button("Remove") {}
                        Button("Keep") {}
                    } message: {
                        Text("It stays in your playlists.")
                    }
            }
        }
        let host = ViewHost(Dialog(), device: phone)
        let dialog = host.root.children.first { $0.kind == "ConfirmationDialog" }
        #expect(
            dialog?.outline() == """
                ConfirmationDialog anchor=Dialog/Text label=Dismiss
                └─ ConfirmationDialogPanel arrow=220,481 arrowEdge=bottom
                   ├─ Text "It stays in your playlists." font=subheadline foregroundStyle=secondary role=message
                   ├─ Button
                   │  └─ Text "Remove"
                   └─ Button
                      └─ Text "Keep"
                """)
    }

    @Test("Tapping an action runs it and dismisses the dialog")
    func action() throws {
        let log = Log()
        let host = ViewHost(RemoveSong(log: log), device: phone)
        try host.tapButton(labeled: "Remove from Library")
        #expect(log.entries == ["remove"])
        #expect(!host.root.allNodes.contains { $0.kind == "ConfirmationDialog" })
    }

    @Test("A tap outside the popover runs the cancel action and dismisses the dialog")
    func tapOutside() throws {
        let log = Log()
        let host = ViewHost(RemoveSong(log: log), device: phone)
        try host.tap(at: CGPoint(x: 20, y: 800))
        #expect(log.entries == ["cancel"])
        #expect(!host.root.allNodes.contains { $0.kind == "ConfirmationDialog" })
    }

    @Test("A dialog near the top of the screen opens below its view")
    func below() throws {
        struct Dialog: View {
            @State var shown = true
            var body: some View {
                VStack {
                    Text("Top")
                        .confirmationDialog(
                            "Remove the song?", isPresented: $shown, titleVisibility: .visible
                        ) {
                            Button("Remove") {}
                        }
                    Spacer()
                }
            }
        }
        let host = ViewHost(Dialog(), device: phone)
        let text = try #require(host.root.allNodes.first { $0.text == "Top" }?.frame)
        let panel = try #require(
            host.root.allNodes.first { $0.kind == "ConfirmationDialogPanel" })
        #expect(panel.attributes["arrowEdge"] == "top")
        #expect(panel.frame?.minY == text.maxY + 13)
    }
}
