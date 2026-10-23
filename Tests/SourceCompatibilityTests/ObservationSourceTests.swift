// Written the way an iOS 17 app is: it imports only SwiftUI, which makes
// @Observable available, as Apple's SwiftUI does.

import SwiftUI
import Testing

@Observable
final class Pantry {
    var title = "Pantry"
    var items: [PantryItem] = []
    var isStocked = false

    @MainActor
    func stock() async {
        await Task.yield()
        items = [PantryItem(id: 1, name: "Rice"), PantryItem(id: 2, name: "Beans")]
        isStocked = true
    }
}

struct PantryItem: Identifiable {
    var id: Int
    var name: String
}

struct PantryView: View {
    @Environment(Pantry.self) private var pantry

    var body: some View {
        @Bindable var pantry = pantry
        VStack {
            TextField("Title", text: $pantry.title)
            ForEach($pantry.items) { $item in
                TextField("Name", text: $item.name)
            }
            Group {
                if pantry.isStocked {
                    Text("Stocked")
                } else {
                    AnyView(Text("Empty"))
                }
            }
        }
        .task {
            await pantry.stock()
        }
        .onChange(of: pantry.isStocked) { oldValue, newValue in
            _ = (oldValue, newValue)
        }
    }
}

struct PantryEditor: View {
    @Bindable var pantry: Pantry

    var body: some View {
        TextField("Title", text: $pantry.title)
            .onAppear {}
            .onDisappear {}
    }
}

@MainActor
@Suite("Observation source compatibility")
struct ObservationSourceTests {
    @Test("@Observable, @Bindable, ForEach($items), and task compile under `import SwiftUI`")
    func observation() async {
        let pantry = Pantry()
        let host = ViewHost(PantryView().environment(pantry))
        #expect(host.nodes(withText: "Empty").count == 1)
        await host.waitForTasks()
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ TextField placeholder=Title value=Pantry
                   ├─ TextField placeholder=Name value=Rice
                   ├─ TextField placeholder=Name value=Beans
                   └─ Text "Stocked"
                """
        )
        _ = ViewHost(PantryEditor(pantry: pantry))
    }
}
