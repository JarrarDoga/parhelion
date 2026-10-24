// Written the way an iOS app is written, against `import SwiftUI`, to check
// that the color scheme and Dynamic Type API compiles as it does with Apple's
// SDK.

import SwiftUI
import Testing

private struct ProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var avatarSide = 100.0
    @ScaledMetric(relativeTo: .caption) private var badgeSide: CGFloat = 24
    let prefersDark: Bool

    var body: some View {
        VStack {
            Color.blue.frame(width: avatarSide, height: badgeSide)
            Text(colorScheme == .dark ? "Dark" : "Light")
                .font(.custom("Avenir Next", size: 17))
            Text(dynamicTypeSize.isAccessibilitySize ? "Accessibility" : "Standard")
                .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
            Text("Fixed").font(.custom("Avenir Next", fixedSize: 13))
            Text("Clamped")
                .dynamicTypeSize(.small...)
                .dynamicTypeSize(...DynamicTypeSize.large)
            Text("Larger").dynamicTypeSize(.xLarge)
            Text("In dark").environment(\.colorScheme, .dark)
        }
        .preferredColorScheme(prefersDark ? .dark : nil)
    }
}

@MainActor
@Suite("Appearance source compatibility")
struct AppearanceSourceTests {
    @Test(
        "Color schemes, Dynamic Type, scaled metrics, and custom fonts compile under `import SwiftUI`"
    )
    func profileCard() {
        let host = ViewHost(ProfileCard(prefersDark: true), dynamicTypeSize: .accessibility1)
        #expect(host.root.attributes["colorScheme"] == "dark")
        let texts = host.root.allNodes.compactMap(\.text)
        #expect(texts == ["Dark", "Accessibility", "Fixed", "Clamped", "Larger", "In dark"])
        let clamped = host.root.allNodes.first { $0.text == "Clamped" }
        #expect(clamped?.attributes["dynamicTypeSize"] == "large")
        let light = ViewHost(ProfileCard(prefersDark: false))
        #expect(light.root.attributes["colorScheme"] == nil)
        #expect(light.root.allNodes.compactMap(\.text).first == "Light")
    }
}
