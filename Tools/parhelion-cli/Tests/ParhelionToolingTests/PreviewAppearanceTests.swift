import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("The simulated device's appearance")
struct PreviewAppearanceTests {
    @Test("Light and dark toggle, and text sizes step and stop at the ends")
    func changes() throws {
        let start = PreviewAppearance()
        #expect(start.colorScheme == "light")
        #expect(start.dynamicTypeSize == "large")
        let dark = try #require(start.applying(.toggleColorScheme))
        #expect(dark.colorScheme == "dark")
        #expect(dark.applying(.toggleColorScheme)?.colorScheme == "light")
        #expect(start.applying(.textSize(steps: 1))?.dynamicTypeSize == "xLarge")
        #expect(start.applying(.textSize(steps: -2))?.dynamicTypeSize == "small")
        #expect(start.applying(.textSize(steps: 100))?.dynamicTypeSize == "accessibility5")
        #expect(start.applying(.textSize(steps: -100))?.dynamicTypeSize == "xSmall")
    }

    @Test("Setting by name keeps what it leaves out and refuses unknown names")
    func setByName() throws {
        let set = try #require(
            PreviewAppearance().applying(.set(colorScheme: "dark", dynamicTypeSize: nil)))
        #expect(set.dynamicTypeSize == "large")
        let both = try #require(
            set.applying(.set(colorScheme: nil, dynamicTypeSize: "accessibility2")))
        #expect(both.colorScheme == "dark")
        #expect(both.dynamicTypeSize == "accessibility2")
        #expect(
            PreviewAppearance().applying(.set(colorScheme: "sepia", dynamicTypeSize: nil)) == nil)
        #expect(
            PreviewAppearance().applying(.set(colorScheme: nil, dynamicTypeSize: "huge")) == nil)
    }

    @Test("A launch gets the setting as environment variables, and the app a command")
    func launchAndCommand() throws {
        let appearance = try #require(
            PreviewAppearance().applying(.set(colorScheme: "dark", dynamicTypeSize: "xxxLarge")))
        #expect(
            appearance.environment == [
                previewColorSchemeEnvironmentKey: "dark",
                previewDynamicTypeSizeEnvironmentKey: "xxxLarge",
            ])
        #expect(
            appearance.command == .setAppearance(colorScheme: "dark", dynamicTypeSize: "xxxLarge"))
        #expect(appearance.summary == "Dark, xxxLarge")
        #expect(PreviewAppearance().summary == "")
    }

    @Test("Only an app that lists the capability takes appearance commands")
    func support() {
        var hello = PreviewHello(appName: "App", screenWidth: 393, screenHeight: 852, scale: 2)
        #expect(!PreviewAppearance.isSupported(by: hello))
        hello.capabilities = PreviewCapability.all
        #expect(PreviewAppearance.isSupported(by: hello))
    }
}
