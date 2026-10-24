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
            // The badge comes from this target's Assets.xcassets, which
            // SwiftPM puts in the target's resource bundle.
            Image("Badge", bundle: .module)
            Text("Count: \(count)")
            Button("Increase") { count += 1 }
        }
        .padding()
    }
}
