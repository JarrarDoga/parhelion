import SwiftUI

@main
struct LibraryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increase") { count += 1 }
        }
        .padding()
    }
}
