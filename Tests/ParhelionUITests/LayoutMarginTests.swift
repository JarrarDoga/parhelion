import Foundation
import Testing

@testable import ParhelionUI

@MainActor
@Suite("Layout margins")
struct LayoutMarginTests {
    @Test("The system margin is 16 points on narrower phones and 20 on wider ones")
    func marginPerDevice() {
        let narrow: [Device] = [.iPhone16, .iPhone16e, .iPhone16Pro, .iPhone17, .iPhone18Pro]
        let wide: [Device] = [.iPhone16Plus, .iPhone16ProMax, .iPhoneAir, .iPhone18ProMax]
        for device in narrow { #expect(device.layoutMargin == 16, "\(device.name)") }
        for device in wide { #expect(device.layoutMargin == 20, "\(device.name)") }
    }

    @Test(
        "Lists, their headers and footers, and large titles are inset by the device's margin",
        arguments: [(Device.iPhone16, CGFloat(16)), (Device.iPhone18ProMax, CGFloat(20))])
    func listAndTitle(device: Device, margin: CGFloat) throws {
        let host = ViewHost(
            NavigationStack {
                List {
                    Section {
                        Text("Plain row")
                        NavigationLink("Link") { Text("Detail") }
                    } header: {
                        Text("Header")
                    } footer: {
                        Text("Footer")
                    }
                    ForEach(1..<3) { Text("Row \($0)") }
                }
                .navigationTitle("List")
            },
            device: device
        )
        let width = device.screenSize.width
        let rows = host.root.allNodes.compactMap(\.listRowFrame)
        #expect(rows.count == 4)
        for cell in rows {
            // The card spans the screen less the margin on each side.
            #expect(cell.minX == margin)
            #expect(cell.maxX == width - margin)
        }
        // Row text, the header, and the footer start the margin inside the
        // card, as do the rows of a list built from a range.
        for text in ["Plain row", "Link", "Header", "Footer", "Row 1", "Row 2"] {
            let node = try #require(host.root.allNodes.first { $0.text == text })
            #expect(try #require(node.frame).minX == 2 * margin, "\(text)")
        }
        let title = try #require(host.root.allNodes.first { $0.text == "List" })
        #expect(try #require(title.frame).minX == margin)
    }

    @Test(
        "Navigation bar buttons are the device's margin from the edges",
        arguments: [(Device.iPhone16, CGFloat(16)), (Device.iPhone18ProMax, CGFloat(20))])
    func navigationBarButtons(device: Device, margin: CGFloat) throws {
        let host = ViewHost(
            NavigationStack(path: .constant([1])) {
                Text("Root")
                    .navigationDestination(for: Int.self) { _ in
                        Text("Detail")
                            .navigationTitle("Detail")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} }
                            }
                    }
            },
            device: device
        )
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" })
        let back = try #require(bar.children.first { $0.kind == "Button" }?.frame)
        #expect(back.minX == margin)
        let edit = try #require(
            bar.children.first { $0.allNodes.contains { $0.text == "Edit" } }?.frame)
        #expect(edit.maxX == device.screenSize.width - margin)
    }

    @Test("padding() is not a layout margin and stays 16 points on a wide phone")
    func defaultPaddingStays16() throws {
        let host = ViewHost(
            Text("Padded").padding().frame(maxWidth: .infinity, alignment: .leading),
            device: .iPhone18ProMax)
        let text = try #require(host.root.allNodes.first { $0.text == "Padded" }?.frame)
        #expect(text.minX == Device.iPhone18ProMax.safeArea.minX + 16)
    }
}
