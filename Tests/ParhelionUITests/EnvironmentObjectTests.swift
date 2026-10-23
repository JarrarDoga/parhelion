import Foundation
import Observation
import Testing

@testable import ParhelionUI

@Observable
private final class Account {
    var name = "Ada"
}

@Observable
private final class Theme {
    var accent = "blue"
}

private struct AccountLabel: View {
    @Environment(Account.self) private var account
    @Environment(Theme.self) private var theme: Theme?

    var body: some View {
        Text("\(account.name) \(theme?.accent ?? "none")")
    }
}

private struct SystemValues: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.locale) private var locale

    var body: some View {
        VStack {
            Text("\(colorScheme)")
            Text("\(dynamicTypeSize)")
            Text("\(horizontalSizeClass.map { "\($0)" } ?? "none")")
            Text("\(verticalSizeClass.map { "\($0)" } ?? "none")")
            Text(locale.identifier)
        }
    }
}

@MainActor
@Suite("Environment objects and values")
struct EnvironmentObjectTests {
    @Test("environment(_:) places an object that @Environment reads by type")
    func object() {
        let account = Account()
        let host = ViewHost(AccountLabel().environment(account))
        #expect(
            host.root.outline() == """
                Root
                └─ Text "Ada none"
                """
        )
    }

    @Test("An optional @Environment object is nil until a view above sets one")
    func optionalObject() {
        let host = ViewHost(AccountLabel().environment(Theme()).environment(Account()))
        #expect(host.nodes(withText: "Ada blue").count == 1)
    }

    @Test("A view that reads an environment object updates when the object changes")
    func observedObject() {
        let account = Account()
        let host = ViewHost(AccountLabel().environment(account))
        account.name = "Grace"
        #expect(host.needsUpdate)
        host.update()
        #expect(host.nodes(withText: "Grace none").count == 1)
    }

    @Test("The inner environment(_:) wins, and nil removes an object")
    func innerWins() {
        let inner = Account()
        inner.name = "Inner"
        let host = ViewHost(
            VStack {
                AccountLabel().environment(inner)
                AccountLabel().environment(Theme?.none)
            }
            .environment(Account())
            .environment(Theme())
        )
        #expect(host.nodes(withText: "Inner blue").count == 1)
        #expect(host.nodes(withText: "Ada none").count == 1)
    }

    @Test("Common environment values describe an iPhone in portrait")
    func systemValues() {
        let host = ViewHost(SystemValues())
        let texts = host.root.allNodes.compactMap(\.text)
        #expect(texts == ["light", "large", "compact", "regular", "en_US"])
        #expect(DynamicTypeSize.accessibility1.isAccessibilitySize)
        #expect(!DynamicTypeSize.xxxLarge.isAccessibilitySize)
    }

    @Test("environment(_:_:) changes common values for the content")
    func setSystemValues() {
        let host = ViewHost(
            SystemValues()
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .xLarge)
                .environment(\.horizontalSizeClass, nil)
        )
        let texts = host.root.allNodes.compactMap(\.text)
        #expect(texts.prefix(3) == ["dark", "xLarge", "none"])
    }
}
