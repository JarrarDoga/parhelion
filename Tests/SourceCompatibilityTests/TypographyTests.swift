// Written the way an iOS app is written, against `import SwiftUI`, to check
// that the font and navigation title API compiles as it does with Apple's
// SDK.

import SwiftUI
import Testing

private struct Article: View {
    @Environment(\.font) private var font

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("Headline").font(.headline)
                Text("Title").font(.system(.title, design: .rounded, weight: .bold))
                Text("Caption").font(.caption.weight(.medium))
                Text("Small").font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("Bold").bold()
                Text("Heavy").fontWeight(.heavy)
                VStack {
                    Text("Footnote")
                    Text("Callout").font(.callout)
                }
                .font(.footnote)
                .fontWeight(.light)
                Text("Inherited").bold(font == nil)
            }
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
        }
        .font(.body)
    }
}

@MainActor
@Suite("Typography source compatibility")
struct TypographyTests {
    @Test("Fonts, weights, and title display modes compile under `import SwiftUI`")
    func article() {
        let host = ViewHost(Article())
        let fonts = host.root.allNodes.filter { $0.kind == "Text" }.map {
            "\($0.label): \($0.attributes["font"] ?? "-")"
        }
        #expect(
            fonts == [
                "Article: headline",
                "Headline: headline",
                "Title: title.bold",
                "Caption: caption.medium",
                "Small: system(11).semibold",
                "Bold: body.bold",
                "Heavy: body.heavy",
                "Footnote: footnote.light",
                "Callout: callout.light",
                "Inherited: body.bold",
            ])
    }
}
