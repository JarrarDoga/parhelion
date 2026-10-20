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
                Button(action: { count -= 1 }) {
                    Text("Decrease")
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(.red)
                }
                Button(action: { count += 1 }) {
                    Text("Increase")
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(.blue)
                }
            }
            Button("Reset") { count = 0 }
        }
        .padding()
    }
}
