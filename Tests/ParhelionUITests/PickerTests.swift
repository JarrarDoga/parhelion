import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [Int] {
    [Int(color.red), Int(color.green), Int(color.blue)]
}

@MainActor
private func node(_ host: ViewHost, _ suffix: String) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix(suffix) })
}

@MainActor
private func center(_ host: ViewHost, _ suffix: String) throws -> CGPoint {
    let frame = try #require(try node(host, suffix).frame)
    return CGPoint(x: frame.midX, y: frame.midY)
}

private enum Flavor: String, CaseIterable, Identifiable {
    case chocolate, vanilla, strawberry

    var id: Self { self }
}

/// A picker of flavors in a style, in a form or not.
private struct Flavors: View {
    @State var flavor = Flavor.vanilla
    var style: BuiltInPickerStyle = .automatic
    var inForm = true

    var picker: some View {
        Picker("Flavor", selection: $flavor) {
            ForEach(Flavor.allCases) { flavor in
                Text(flavor.rawValue.capitalized)
            }
        }
        .environment(\.pickerStyle, style)
    }

    var body: some View {
        if inForm {
            NavigationStack {
                Form {
                    picker
                    Text("Chosen: \(flavor.rawValue)")
                }
            }
        } else {
            VStack {
                picker
                Text("Chosen: \(flavor.rawValue)")
            }
            .padding(16)
        }
    }
}

@MainActor
@Suite("Picker")
struct PickerTests {
    // MARK: Segmented

    @Test("A segmented picker is a capsule of options with the selection's capsule")
    func segmentedOutline() {
        let host = ViewHost(
            Picker("Size", selection: .constant(2)) {
                Text("S").tag(1)
                Text("M").tag(2)
            }
            .pickerStyle(.segmented))
        #expect(
            host.root.outline() == """
                Root
                └─ Picker label=Size pickerStyle=segmented selection=2
                   ├─ SegmentIndicator
                   ├─ PickerOption
                   │  └─ Text "S" font=system(13.33).medium tag=1
                   └─ PickerOption selected=true
                      └─ Text "M" font=system(13.33).semibold tag=2
                """)
    }

    @Test("Segments share the width; tapping one selects it and slides the capsule")
    func segmentedInteraction() throws {
        let host = ViewHost(Flavors(style: .segmented, inForm: false), device: screen)
        let picker = try #require(try node(host, "Picker").frame)
        #expect(picker.width == 268)
        #expect(picker.height == 32)
        let segments = host.root.allNodes.filter { $0.kind == "PickerOption" }.compactMap(\.frame)
        #expect(segments.map(\.width) == Array(repeating: 256 / 3, count: 3))
        #expect(segments[0].minX == picker.minX + 2)
        #expect(segments[1].minX == segments[0].maxX + 4)
        #expect(try node(host, "Picker/indicator").frame == segments[1])

        try host.tapButton(labeled: "Strawberry")
        #expect(host.nodes(withText: "Chosen: strawberry").count == 1)
        #expect(try node(host, "Picker/indicator").frame == segments[2])
        // The capsule slides; the label weights change at once.
        let presented = host.presentedRoot.allNodes.first { $0.id.rawValue.hasSuffix("indicator") }
        #expect(try #require(presented?.frame).minX < segments[2].minX)
        host.advanceTime(by: 2)
        #expect(!host.isAnimating)

        try host.tap(at: CGPoint(x: segments[0].midX, y: segments[0].midY))
        #expect(host.nodes(withText: "Chosen: chocolate").count == 1)
    }

    @Test("The selected segment is white on the gray capsule")
    func segmentedDrawing() throws {
        let host = ViewHost(Flavors(style: .segmented, inForm: false), device: screen)
        let segments = host.root.allNodes.filter { $0.kind == "PickerOption" }.compactMap(\.frame)
        let image = host.render(scale: 2)
        #expect(
            components(image.color(at: CGPoint(x: segments[1].minX + 6, y: segments[1].midY)))
                == [255, 255, 255])
        #expect(
            components(image.color(at: CGPoint(x: segments[0].minX + 6, y: segments[0].midY)))
                == [238, 238, 240])
    }

    // MARK: Menu

    @Test("In a form, a menu picker is a row with its value and chevrons at the trailing edge")
    func menuOutline() throws {
        let host = ViewHost(Flavors(), device: screen)
        let picker = try #require(
            host.root.allNodes.first { $0.kind == "Picker" }?.outline())
        #expect(
            picker == """
                Picker listRow pickerStyle=menu selection=vanilla
                ├─ Text "Flavor"
                └─ PopUpButton
                   ├─ Text "Vanilla" foregroundStyle=secondary
                   └─ MenuIndicator foregroundStyle=tertiary
                """)
        let cell = try #require(try node(host, "Picker").listRowFrame)
        let button = try #require(try node(host, "Picker/button").frame)
        let indicator = try #require(try node(host, "button/indicator").frame)
        #expect(cell.height == 52)
        #expect(indicator.maxX == cell.maxX - 16)
        #expect(indicator.size == CGSize(width: 12, height: 22))
        #expect(button.maxX == indicator.maxX)
    }

    @Test("Outside a list, a menu picker is its button in the tint color")
    func menuOutsideList() throws {
        let host = ViewHost(Flavors(inForm: false), device: screen)
        #expect(
            try node(host, "Picker").outline() == """
                Picker label=Flavor pickerStyle=menu selection=vanilla
                └─ PopUpButton
                   ├─ Text "Vanilla"
                   └─ MenuIndicator
                """)
        let text = try #require(host.nodes(withText: "Vanilla").first?.frame)
        let image = host.render(scale: 2)
        var found = false
        for x in stride(from: text.minX, to: text.maxX, by: 0.5) {
            if components(image.color(at: CGPoint(x: x, y: text.midY))) == [0, 136, 255] {
                found = true
            }
        }
        #expect(found)
    }

    @Test("The button opens a glass menu of the options; choosing one selects it and closes")
    func menuInteraction() throws {
        let host = ViewHost(Flavors(), device: screen)
        try host.tapButton(labeled: "Vanilla")
        let menu = try #require(host.root.children.last)
        #expect(menu.kind == "Menu")
        #expect(host.interactiveRoot.id == menu.id)
        #expect(
            menu.outline() == """
                Menu anchor=\((try node(host, "Picker/button")).id) label=Dismiss Menu
                ├─ PickerOption
                │  └─ Text "Chocolate"
                ├─ PickerOption selected=true
                │  └─ Text "Vanilla"
                └─ PickerOption
                   └─ Text "Strawberry"
                """)
        // The menu is 250 points wide, its top level with the button's, and
        // inside the screen's margins; each item is a 42-point cell.
        let panel = try #require(menu.menuPanel)
        let button = try #require(try node(host, "Picker/button").frame)
        #expect(panel.width == 250)
        #expect(panel.minY == button.minY)
        #expect(panel.maxX <= 300 - 16)
        #expect(menu.children.compactMap(\.frame).map(\.height) == [42, 42, 42])

        // Only the menu takes input while it is open.
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Flavor") }
        try host.tapButton(labeled: "Strawberry")
        #expect(host.nodes(withText: "Chosen: strawberry").count == 1)
        #expect(!host.root.children.contains { $0.kind == "Menu" })
        #expect(host.nodes(withText: "Strawberry").count == 1)
    }

    @Test("A tap outside the menu's items closes it, and the menu fades")
    func menuDismissal() throws {
        let host = ViewHost(Flavors(), device: screen)
        let button = try center(host, "Picker/button")
        host.pointerDown(at: button)
        #expect(host.pointerUp(at: button) != nil)
        #expect(host.root.children.last?.kind == "Menu")
        #expect(host.isAnimating)
        host.advanceTime(by: 2)

        // A press on an item highlights it without dimming its text.
        let item = try center(host, "menu/option[chocolate]")
        host.pointerDown(at: item)
        #expect(host.pressedNodeID == (try node(host, "menu/option[chocolate]")).id)
        host.pointerMoved(to: CGPoint(x: 20, y: 380))
        host.pointerUp(at: CGPoint(x: 20, y: 380))
        #expect(host.root.children.last?.kind == "Menu")

        try host.tap(at: CGPoint(x: 20, y: 380))
        #expect(host.root.children.last?.kind != "Menu")
        #expect(host.nodes(withText: "Chosen: vanilla").count == 1)
        // The menu fades out.
        #expect(host.presentedRoot.children.contains { $0.kind == "Menu" })
        host.advanceTime(by: 2)
        #expect(!host.presentedRoot.children.contains { $0.kind == "Menu" })
    }

    @Test("A menu above the bottom of the screen opens upward")
    func menuNearBottom() throws {
        let host = ViewHost(
            VStack {
                Spacer()
                Picker("Flavor", selection: .constant(Flavor.vanilla)) {
                    ForEach(Flavor.allCases) { Text($0.rawValue) }
                }
            }, device: screen)
        try host.tap(try node(host, "Picker/button").id)
        let panel = try #require(host.root.children.last?.menuPanel)
        #expect(abs(panel.maxY - (400 - 20 - 16)) < 0.01)
    }

    // MARK: Inline

    @Test("In a form, an inline picker is a section of options under its label")
    func inlineOutline() throws {
        let host = ViewHost(Flavors(style: .inline), device: screen)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(
            list.children[0].outline() == """
                Section pickerStyle=inline selection=vanilla
                ├─ SectionHeader
                │  └─ Text "Flavor" font=headline
                ├─ PickerOption listRow
                │  └─ Text "Chocolate"
                ├─ PickerOption listRow selected=true
                │  └─ Text "Vanilla"
                └─ PickerOption listRow
                   └─ Text "Strawberry"
                """)
        #expect(list.children[1].children.first?.text == "Chosen: vanilla")
    }

    @Test("Tapping an inline option selects it, and its row shows the checkmark")
    func inlineInteraction() throws {
        let host = ViewHost(Flavors(style: .inline), device: screen)
        let row = try #require(try node(host, "Picker/option[chocolate]").listRowFrame)
        // The whole row responds, and the checkmark sits 16 points from the
        // trailing edge.
        try host.tap(at: CGPoint(x: row.maxX - 30, y: row.midY))
        #expect(host.nodes(withText: "Chosen: chocolate").count == 1)
        let image = host.render(scale: 2)
        var dark = 0
        for x in stride(from: row.maxX - 38, to: row.maxX - 16, by: 0.5) {
            if components(image.color(at: CGPoint(x: x, y: row.midY + 3))).allSatisfy({ $0 < 80 }) {
                dark += 1
            }
        }
        #expect(dark > 0)
        let other = try #require(try node(host, "Picker/option[vanilla]").listRowFrame)
        #expect(
            components(image.color(at: CGPoint(x: other.maxX - 27, y: other.midY + 3)))
                == [255, 255, 255])
    }

    @Test("An inline picker inside a section adds its options to the section")
    func inlineInSection() throws {
        let host = ViewHost(
            List {
                Section("Ice cream") {
                    Picker("Flavor", selection: .constant(Flavor.vanilla)) {
                        ForEach(Flavor.allCases) { Text($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                }
            })
        let section = try #require(host.root.allNodes.first { $0.kind == "Section" })
        #expect(
            section.children.map(\.kind) == [
                "SectionHeader", "PickerOption", "PickerOption", "PickerOption",
            ])
    }

    // MARK: Navigation link

    @Test("A navigation-link picker pushes its options; choosing one goes back")
    func navigationLinkInteraction() throws {
        let host = ViewHost(Flavors(style: .navigationLink), device: screen)
        let link = try #require(host.root.allNodes.first { $0.kind == "NavigationLink" })
        #expect(
            link.outline() == """
                NavigationLink listRow pickerStyle=navigationLink selection=vanilla
                └─ LabeledContent
                   ├─ Text "Flavor"
                   └─ Text "Vanilla" foregroundStyle=secondary
                """)
        try host.tap(link.id)
        host.advanceTime(by: 2)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" })
        #expect(bar.children.contains { $0.text == "Flavor" })
        #expect(host.nodes(withText: "Strawberry").count == 1)

        try host.tapButton(labeled: "Strawberry")
        host.advanceTime(by: 2)
        #expect(host.nodes(withText: "Chosen: strawberry").count == 1)
        #expect(
            host.root.allNodes.first { $0.kind == "NavigationLink" }?.label == "Flavor Strawberry")
    }

    // MARK: Tags and selection

    @Test("Options match an optional selection; untagged options cannot be chosen")
    func tagsAndSelection() throws {
        struct Optional: View {
            @State var flavor: Flavor?
            var body: some View {
                Picker("Flavor", selection: $flavor) {
                    Text("None").tag(Flavor?.none)
                    Text("Vanilla").tag(Flavor.vanilla)
                    Text("Untagged")
                }
                .pickerStyle(.segmented)
            }
        }
        let host = ViewHost(Optional())
        #expect(try node(host, "Picker").attributes["selection"] == "nil")
        try host.tapButton(labeled: "Vanilla")
        #expect(try node(host, "Picker").attributes["selection"] == "vanilla")
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Untagged") }
        try host.tapButton(labeled: "None")
        #expect(try node(host, "Picker").attributes["selection"] == "nil")
    }

    @Test("A disabled picker records it and takes no taps")
    func disabledPicker() throws {
        let host = ViewHost(Flavors(style: .segmented).disabled(true), device: screen)
        #expect(try node(host, "Picker").isDisabled)
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Chocolate") }

        let menu = ViewHost(Flavors().disabled(true), device: screen)
        #expect(throws: InteractionError.self) { try menu.tapButton(labeled: "Vanilla") }
        #expect(!menu.root.children.contains { $0.kind == "Menu" })
    }
}
