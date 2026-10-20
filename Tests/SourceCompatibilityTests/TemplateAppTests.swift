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
                └─ VStack padding(16)
                   ├─ Image foregroundStyle=tint imageScale=large systemName=globe
                   └─ Text "Hello, world!"
                """
        )
    }

    @Test("The template view's layout matches the README")
    func templateLayout() {
        let host = ViewHost(ContentView())
        #expect(
            host.root.outline(includeFrames: true) == """
                Root  [0, 0, 393 × 852]
                └─ VStack padding(16)  [146.21, 413.25, 100.57 × 50.5]
                   ├─ Image foregroundStyle=tint imageScale=large systemName=globe  [185.54, 413.25, 21.93 × 21.93]
                   └─ Text "Hello, world!"  [146.21, 443.18, 100.57 × 20.57]
                """
        )
    }
}
