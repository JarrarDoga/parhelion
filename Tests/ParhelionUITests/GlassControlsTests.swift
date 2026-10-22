import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

/// The width of a medium 17-point label.
private func mediumWidth(_ text: String) -> CGFloat {
    FontTextMeasurer().size(of: text, font: Font.body.weight(.medium).resolved(), width: nil).width
}

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [Int] {
    [Int(color.red), Int(color.green), Int(color.blue)]
}

@MainActor
private func bar(_ host: ViewHost) -> ViewNode {
    host.root.children[0].children[0]
}

@MainActor
private func frame(_ host: ViewHost, _ id: String) throws -> CGRect {
    try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix(id) }?.frame)
}

private struct Pushed: View {
    var body: some View {
        NavigationStack {
            NavigationLink("Open") {
                Text("Detail")
                    .navigationTitle("Detail")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: {}) { Image(systemName: "pencil") }
                        }
                    }
            }
            .navigationTitle("Home")
        }
    }
}

@MainActor
@Suite("Glass controls")
struct GlassControlsTests {
    // MARK: Toolbar items

    @Test("A text toolbar button is a 44-point capsule 16 points from the edge")
    func textToolbarItem() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Title")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Add") {} }
                    }
            },
            device: screen
        )
        #expect(
            bar(host).outline() == """
                NavigationBar titleDisplayMode=large
                ├─ Text "Title" font=largeTitle.bold
                └─ ToolbarItemGroup placement=trailing
                   └─ Button
                      └─ Text "Add" font=body.medium
                """)
        let group = try #require(bar(host).children[1].frame)
        let width = mediumWidth("Add") + 24
        #expect(abs(group.width - width) < 0.01)
        #expect(group.height == 44 && group.minY == 20)
        #expect(group.maxX == 284)
        // The button fills the capsule, so the whole capsule takes taps.
        #expect(try frame(host, "toolbar/0/Button") == group)
    }

    @Test("Toolbar labels are near-black on glass, not the tint color")
    func toolbarLabelColor() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .toolbar {
                        ToolbarItem { Button("MMMM") {} }
                    }
            },
            device: screen
        )
        let text = try frame(host, "toolbar/0/Button/Text")
        let rendered = host.render(scale: 3)
        var darkest = 255
        var bluest = 0
        for x in stride(from: text.minX, to: text.maxX, by: 0.33) {
            let pixel = components(rendered.color(at: CGPoint(x: x, y: text.midY)))
            darkest = min(darkest, pixel[0])
            bluest = max(bluest, pixel[2] - pixel[0])
        }
        #expect(darkest < 40)
        #expect(bluest < 10)
    }

    @Test("Symbols are 44-point circles alone and share a capsule side by side")
    func symbolItems() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .navigationTitle("Title")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: {}) { Image(systemName: "gear") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {}) { Image(systemName: "plus") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {}) { Image(systemName: "trash") }
                        }
                    }
            },
            device: screen
        )
        let groups = bar(host).children.filter { $0.kind == "ToolbarItemGroup" }
        #expect(groups.count == 2)
        let leading = try #require(groups[0].frame)
        #expect(leading == CGRect(x: 16, y: 20, width: 44, height: 44))
        let trailing = try #require(groups[1].frame)
        #expect(trailing == CGRect(x: 180, y: 20, width: 104, height: 44))
        #expect(try frame(host, "toolbar/1/Button") == CGRect(x: 180, y: 20, width: 52, height: 44))
        #expect(try frame(host, "toolbar/2/Button") == CGRect(x: 232, y: 20, width: 52, height: 44))
    }

    @Test("A confirmation action is prominent, in its own capsule at the trailing edge")
    func prominentItem() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {}) { Image(systemName: "plus") }
                        }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
                    }
            },
            device: screen
        )
        #expect(
            bar(host).outline() == """
                NavigationBar titleDisplayMode=inline
                ├─ ToolbarItemGroup placement=trailing
                │  └─ Button
                │     └─ Image systemName=plus
                └─ ToolbarItemGroup glass=prominent placement=trailing
                   └─ Button buttonStyle=glassProminent
                      └─ Text "Done" font=body.medium
                """)
        let done = try #require(bar(host).children[1].frame)
        #expect(done.maxX == 284)
        let plus = try #require(bar(host).children[0].frame)
        #expect(plus.maxX == done.minX - 12 && plus.width == 44)
        // Blue glass with a white label.
        let rendered = host.render(scale: 2)
        #expect(
            components(rendered.color(at: CGPoint(x: done.minX + 4, y: done.midY))) == [
                0, 136, 255,
            ])
    }

    @Test("A principal button draws without glass, in the tint color")
    func principalButton() throws {
        let host = ViewHost(
            NavigationStack {
                Text("Content")
                    .toolbar {
                        ToolbarItem(placement: .principal) { Button("MMMM") {} }
                    }
            },
            device: screen
        )
        let button = try frame(host, "toolbar/0/Button")
        let rendered = host.render(scale: 3)
        #expect(
            components(rendered.color(at: CGPoint(x: button.minX - 4, y: button.midY)))
                == [255, 255, 255])
        var bluest = 0
        for x in stride(from: button.minX, to: button.maxX, by: 0.33) {
            let pixel = components(rendered.color(at: CGPoint(x: x, y: button.midY)))
            bluest = max(bluest, pixel[2] - pixel[0])
        }
        #expect(bluest > 150)
    }

    // MARK: Back button

    @Test("The back button is a chevron on a 44-point circle 16 points from the edge")
    func backButton() throws {
        let host = ViewHost(Pushed(), device: screen)
        try host.tapButton(labeled: "Open")
        host.advanceTime(by: 1)
        #expect(
            bar(host).outline() == """
                NavigationBar titleDisplayMode=large
                ├─ Button label=Home
                │  └─ Image offset(x: -1.7, y: 0) systemName=chevron.backward
                ├─ ToolbarItemGroup placement=leading
                │  └─ Button
                │     └─ Image systemName=pencil
                └─ Text "Detail" font=largeTitle.bold
                """)
        let back = try frame(host, "/bar/back")
        #expect(back == CGRect(x: 16, y: 20, width: 44, height: 44))
        let chevron = try frame(host, "/bar/back/Image")
        #expect(abs(chevron.midX - (38 - 1.7)) < 0.01 && chevron.midY == 42)
        // Separate glass items are 12 points apart.
        #expect(try #require(bar(host).children[1].frame).minX == 72)
        // The chevron is near-black on a light circle.
        let rendered = host.render(scale: 3)
        let ink = (0..<30).map {
            components(rendered.color(at: CGPoint(x: 30 + Double($0) * 0.33, y: 42)))[0]
        }
        #expect(ink.min()! < 60)
        #expect(components(rendered.color(at: CGPoint(x: 50, y: 30)))[0] > 245)
    }

    @Test("The back button pops by label, by identifier, and by position")
    func backButtonTaps() throws {
        let host = ViewHost(Pushed(), device: screen)
        try host.tapButton(labeled: "Open")
        try host.tapButton(labeled: "Home")
        #expect(bar(host).children.contains { $0.text == "Home" })

        try host.tapButton(labeled: "Open")
        let back = try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix("/bar/back") })
        try host.tap(back.id)
        #expect(bar(host).children.contains { $0.text == "Home" })

        try host.tapButton(labeled: "Open")
        host.advanceTime(by: 1)
        try host.tap(at: CGPoint(x: 20, y: 25))
        #expect(bar(host).children.contains { $0.text == "Home" })
    }

    // MARK: Alerts

    private func alert(buttons: Int) throws -> ViewNode {
        let host = ViewHost(
            Text("Content").alert("Title", isPresented: .constant(true)) {
                if buttons > 0 { Button("Cancel", role: .cancel) {} }
                if buttons > 1 { Button("Delete", role: .destructive) {} }
                if buttons > 2 { Button("Archive") {} }
            } message: {
                Text("Message")
            },
            device: screen
        )
        return host.root.children[1]
    }

    @Test("An alert is 300 wide, with left-aligned text 22 points in")
    func alertLayout() throws {
        let alert = try alert(buttons: 2)
        let frame = try #require(alert.frame)
        // 22 + title 22 + 10 + message 22 + 24 + button 48 + 14.
        #expect(frame.size == CGSize(width: 300, height: 162))
        #expect(frame.midX == 150 && frame.midY == 200)
        let title = try #require(alert.children[0].frame)
        #expect(title.origin == CGPoint(x: frame.minX + 22, y: frame.minY + 22))
        let message = try #require(alert.children[1].frame)
        #expect(message.minX == frame.minX + 22 && message.minY == title.maxY + 10)
    }

    @Test("Two alert buttons sit side by side, cancel first")
    func twoButtons() throws {
        let alert = try alert(buttons: 2)
        let frame = try #require(alert.frame)
        let cancel = try #require(alert.children[2].frame)
        let delete = try #require(alert.children[3].frame)
        #expect(alert.children[2].attributes["role"] == "cancel")
        #expect(cancel == CGRect(x: frame.minX + 14, y: frame.maxY - 62, width: 132, height: 48))
        #expect(delete == CGRect(x: frame.minX + 154, y: frame.maxY - 62, width: 132, height: 48))
    }

    @Test("One alert button spans the alert; three stack, cancel last")
    func oneAndThreeButtons() throws {
        let one = try alert(buttons: 1)
        let oneFrame = try #require(one.frame)
        #expect(oneFrame.height == 162)
        #expect(
            one.children[2].frame
                == CGRect(x: oneFrame.minX + 14, y: oneFrame.maxY - 62, width: 272, height: 48))

        let three = try alert(buttons: 3)
        let frame = try #require(three.frame)
        // Three 48-point rows, 12 apart.
        #expect(abs(frame.height - (162 + 2 * 60)) < 0.01)
        let buttons = three.children.filter { $0.kind == "Button" }
        #expect(buttons.map(\.label) == ["Delete", "Archive", "Cancel"])
        let tops = buttons.compactMap { $0.frame?.minY }
        let expected = [frame.maxY - 182, frame.maxY - 122, frame.maxY - 62]
        #expect(zip(tops, expected).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(buttons.allSatisfy { $0.frame?.width == 272 })
    }

    @Test("Alert buttons are gray capsules, with a red label for a destructive one")
    func alertColors() throws {
        let host = ViewHost(
            Text("Content").alert("Title", isPresented: .constant(true)) {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            },
            device: screen
        )
        let rendered = host.render(scale: 2)
        let alert = host.root.children[1]
        let cancel = try #require(alert.children[1].frame)
        // The capsule darkens the glass a little.
        let capsule = components(rendered.color(at: CGPoint(x: cancel.minX + 10, y: cancel.midY)))
        let glass = components(
            rendered.color(at: CGPoint(x: try #require(alert.frame).midX, y: cancel.minY - 6)))
        #expect(capsule[0] < glass[0] - 8)
        let delete = try #require(alert.children[2].children[0].frame)
        var reddest = 0
        for x in stride(from: delete.minX, to: delete.maxX, by: 0.5) {
            let pixel = components(rendered.color(at: CGPoint(x: x, y: delete.midY)))
            reddest = max(reddest, pixel[0] - pixel[2])
        }
        #expect(reddest > 120)
        // The screen behind is dimmed blue-gray.
        #expect(components(rendered.color(at: CGPoint(x: 5, y: 395))) == [205, 205, 209])
    }

    // MARK: Sheets

    @Test("A sheet starts at the safe area's top with a 70-point toolbar")
    func sheetToolbar() throws {
        let host = ViewHost(
            Text("Content").sheet(isPresented: .constant(true)) {
                NavigationStack {
                    Text("Form")
                        .navigationTitle("New")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                        }
                }
            },
            device: screen
        )
        let sheet = host.root.children[1]
        #expect(sheet.frame == CGRect(x: 0, y: 20, width: 300, height: 380))
        let bar = sheet.children[0].children[0]
        #expect(bar.attributes["presentation"] == "sheet")
        #expect(bar.frame == CGRect(x: 0, y: 20, width: 300, height: 70))
        let cancel = try #require(bar.children[0].frame)
        #expect(cancel.origin == CGPoint(x: 16, y: 36) && cancel.height == 44)
        // No grabber with a single detent.
        let rendered = host.render(scale: 2)
        #expect(components(rendered.color(at: CGPoint(x: 150, y: 27))) == [255, 255, 255])
        // The screen behind is dimmed 20%, to 204, and not scaled; the
        // sheet's shadow reaches up a little.
        let behind = components(rendered.color(at: CGPoint(x: 5, y: 5)))[0]
        #expect(behind <= 204 && behind > 196)
    }

    @Test("A medium detent insets the sheet 8 points and shows a grabber")
    func mediumSheet() throws {
        let host = ViewHost(
            Text("Content").sheet(isPresented: .constant(true)) {
                Text("Half").presentationDetents([.medium, .large])
            },
            device: screen
        )
        let sheet = host.root.children[1]
        #expect(sheet.frame == CGRect(x: 8, y: 200, width: 284, height: 192))
        let rendered = host.render(scale: 2)
        #expect(components(rendered.color(at: CGPoint(x: 150, y: 207))) == [207, 207, 207])
        #expect(components(rendered.color(at: CGPoint(x: 150, y: 212)))[0] > 220)
    }

    @Test("presentationDragIndicator shows or hides the grabber")
    func dragIndicator() throws {
        func sheet(_ visibility: Visibility, detents: Set<PresentationDetent>) -> ViewHost {
            ViewHost(
                Text("Content").sheet(isPresented: .constant(true)) {
                    Text("Sheet")
                        .presentationDetents(detents)
                        .presentationDragIndicator(visibility)
                },
                device: screen
            )
        }
        let visible = sheet(.visible, detents: [.large])
        #expect(
            visible.root.children[1].outline() == """
                Sheet detents=large dragIndicator=visible
                └─ Text "Sheet"
                """)
        #expect(
            components(visible.render(scale: 2).color(at: CGPoint(x: 150, y: 27)))
                == [207, 207, 207])
        let hidden = sheet(.hidden, detents: [.medium, .large])
        #expect(
            components(hidden.render(scale: 2).color(at: CGPoint(x: 150, y: 207)))[0] > 220)
    }
}
