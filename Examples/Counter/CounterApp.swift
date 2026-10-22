import SwiftUI

@main
struct CounterApp: App {
    var body: some Scene {
        WindowGroup {
            CounterView()
        }
    }
}

struct CounterView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Count: \(count)")
            HStack(spacing: 12) {
                Button("Decrease") { count -= 1 }
                    .buttonStyle(.bordered)
                Button("Increase") { count += 1 }
                    .buttonStyle(.borderedProminent)
            }
            Button("Reset") { count = 0 }
        }
        .padding()
    }
}
