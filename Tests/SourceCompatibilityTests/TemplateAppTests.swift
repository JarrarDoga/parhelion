// This file is written the way an iOS app is written: it imports SwiftUI,
// not ParhelionUI. It compiles only because Parhelion provides that module on
// Linux. The view below is the `ContentView` that `xtool new` generates,
// copied without changes.

import SwiftUI
import Testing

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

@MainActor
@Suite("Source compatibility")
struct TemplateAppTests {
    @Test("The xtool template view compiles and resolves under `import SwiftUI`")
    func templateView() {
        let host = ViewHost(ContentView())
        #expect(
            host.root.outline() == """
                Root
                └─ VStack padding=all
                   ├─ Image foregroundStyle=tint imageScale=large systemName=globe
                   └─ Text "Hello, world!"
                """
        )
    }
}
