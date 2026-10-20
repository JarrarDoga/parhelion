import SwiftUI

@main
struct ScrollingApp: App {
    var body: some Scene {
        WindowGroup {
            RowsView()
        }
    }
}

struct RowsView: View {
    @State private var selection = "none"

    var body: some View {
        ScrollView {
            Text("Selected: \(selection)")
                .padding()
            ForEach(1..<41) { row in
                Button(action: { selection = "Row \(row)" }) {
                    Text("Row \(row)")
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                        .background(row % 2 == 0 ? .white : .gray)
                }
            }
        }
    }
}
