import Testing

@testable import ParhelionUI

// Keeps the example in README.md honest. If this test changes, update the
// README to match.

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
    }
}

@MainActor
@Test("The README example produces the documented output")
func readmeExample() throws {
    let host = ViewHost(Counter())
    try host.tapButton(labeled: "Increment")
    #expect(
        host.root.outline(includeIDs: true) == """
            Root
            └─ VStack  #Counter/VStack
               ├─ Text "Count: 1"  #Counter/VStack/0/Text
               └─ Button  #Counter/VStack/1/Button
                  └─ Text "Increment"  #Counter/VStack/1/Button/Text
            """
    )
}
