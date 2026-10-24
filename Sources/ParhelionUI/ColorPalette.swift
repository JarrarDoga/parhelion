import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The colors Parhelion draws SwiftUI's named colors and styles with.
///
/// Assumed: these are iOS 27's system colors, from the swatches of Apple's
/// iOS 27 UI Kit. iOS 26 changed several of them from the values iOS 7
/// through 18 used, such as blue from 0,122,255. Like the constants in
/// `LayoutDefaults`, they have not been checked against SwiftUI
/// automatically yet. The constants below are the light appearance's;
/// ``dark`` holds the dark appearance's, and ``appearance(_:elevated:)``
/// picks one for a color scheme.
enum ColorPalette {
    /// The color for a style name recorded by `foregroundStyle` or `Color`,
    /// such as `"blue"`, `"tint"`, `"secondary"`, or `"rgba(1,0.5,0,1)"`, in
    /// the light appearance.
    static func color(named name: String) -> RGBA {
        color(named: name, in: .light)
    }

    /// The color for a style name in a color scheme. Every color a node
    /// names resolves here, so that it follows the node's scheme.
    static func color(named name: String, in scheme: ColorScheme) -> RGBA {
        // A color with reduced opacity is recorded as "name@opacity".
        if let separator = name.lastIndex(of: "@"),
            let opacity = Double(name[name.index(after: separator)...])
        {
            var color = color(named: String(name[..<separator]), in: scheme)
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            return color
        }
        if scheme == .dark, let color = darkColor(named: name) { return color }
        if let components = rgbaComponents(name) {
            return RGBA(
                fractionalRed: components[0],
                green: components[1],
                blue: components[2],
                opacity: components[3]
            )
        }
        switch name {
        case "red": return RGBA(red: 255, green: 56, blue: 60)
        case "orange": return RGBA(red: 255, green: 141, blue: 40)
        case "yellow": return RGBA(red: 255, green: 204, blue: 0)
        case "green": return RGBA(red: 52, green: 199, blue: 89)
        case "mint": return RGBA(red: 0, green: 200, blue: 179)
        case "teal": return RGBA(red: 0, green: 195, blue: 208)
        case "cyan": return RGBA(red: 0, green: 192, blue: 232)
        case "blue", "tint", "accentColor": return RGBA(red: 0, green: 136, blue: 255)
        case "indigo": return RGBA(red: 97, green: 85, blue: 245)
        case "purple": return RGBA(red: 203, green: 48, blue: 224)
        case "pink": return RGBA(red: 255, green: 45, blue: 85)
        case "brown": return RGBA(red: 172, green: 127, blue: 94)
        case "white": return .white
        case "gray": return RGBA(red: 142, green: 142, blue: 147)
        case "black", "primary": return .black
        case "secondary": return RGBA(red: 60, green: 60, blue: 67, alpha: 153)
        case "tertiary": return RGBA(red: 60, green: 60, blue: 67, alpha: 76)
        case "quaternary": return RGBA(red: 60, green: 60, blue: 67, alpha: 46)
        case "clear": return .clear
        case glassLabelStyle: return glassLabel
        case alertMessageStyle: return alertMessage
        case tertiaryFillStyle: return tertiaryFill
        default: return .black
        }
    }

    /// The background of a window.
    static let background = RGBA.white

    /// Assumed: the background of a grouped list, iOS's
    /// `systemGroupedBackground`.
    static let groupedBackground = RGBA(red: 242, green: 242, blue: 247)

    /// Assumed: the background of a grouped list's rows, iOS's
    /// `secondarySystemGroupedBackground`.
    static let groupedRowBackground = RGBA.white

    /// Assumed: the color of a list's row separators, black at 12% opacity,
    /// the iOS 27 UI Kit's light non-opaque separator.
    static let separator = RGBA(red: 0, green: 0, blue: 0, alpha: 31)

    /// Assumed: the background of a list row while it is pressed, iOS's
    /// `systemGray4`.
    static let rowHighlight = RGBA(red: 209, green: 209, blue: 214)

    /// Assumed: the color that dims the screen behind a sheet, black at 20%
    /// in the iOS 27 UI Kit's sheet overlay.
    static let sheetDim = RGBA(red: 0, green: 0, blue: 0, alpha: 51)

    /// Assumed: the color that dims the screen behind an alert,
    /// rgba(41, 41, 58, 0.23) in the iOS 27 UI Kit. Over white it makes
    /// 205,205,209, as in the alert artwork of the Human Interface
    /// Guidelines.
    static let alertDim = RGBA(red: 41, green: 41, blue: 58, alpha: 59)

    /// Assumed: the color of the status bar's contents and the home
    /// indicator over the light appearance.
    static let systemBarForeground = RGBA.black

    /// Assumed: the color of labels on glass, such as toolbar buttons and
    /// the back button's chevron: the iOS 27 UI Kit's Liquid Glass primary
    /// label, 26,26,26, which an iOS 26 Simulator screenshot shows as
    /// 25,25,25 for the back button's chevron.
    static let glassLabel = RGBA(red: 26, green: 26, blue: 26)

    /// The style name of ``glassLabel``, for the renderer's inherited
    /// foreground style. Views cannot name it.
    static let glassLabelStyle = "system.glassLabel"

    /// Assumed: the color of an alert's message. The iOS 27 UI Kit draws it
    /// in a vibrant secondary gray; in the alert artwork of the Human
    /// Interface Guidelines its darkest pixels are 62,62,63.
    static let alertMessage = RGBA(red: 62, green: 62, blue: 64)

    /// The style name of ``alertMessage``.
    static let alertMessageStyle = "system.alertMessage"

    /// Assumed: the fill of a bordered button, and of an alert's buttons
    /// other than its preferred one: the iOS 27 UI Kit's tertiary fill,
    /// 118,118,128 at 12%.
    static let tertiaryFill = RGBA(red: 118, green: 118, blue: 128, alpha: 31)

    /// The style name of ``tertiaryFill``.
    static let tertiaryFillStyle = "system.tertiaryFill"

    /// Assumed: the color of a sheet's grabber: 207 gray, drawn plus-darker
    /// in the iOS 27 UI Kit, which is 207 gray over the white sheet.
    static let grabber = RGBA(red: 207, green: 207, blue: 207)

    /// Assumed: small glass, for toolbar buttons, the back button, and
    /// `.glass` buttons, from the iOS 27 UI Kit's 44-point toolbar button,
    /// tuned to a 3× iOS 26 Simulator screenshot of a back button over
    /// white:
    ///
    /// - The backdrop is blurred with a radius of 6 and saturation 2.
    /// - The kit's tint stack works out to about 0.45 × backdrop + 132,
    ///   which is 247 over white, but the screenshot shows 253. 252 gray at
    ///   60% gives 253 over white and 248 over the grouped background.
    /// - A bright line 1.5 pixels wide at 3× inside the top edge, fainter
    ///   inside the bottom edge.
    /// - The kit's 0.5-point ring of 219 gray, plus-darker, does not show in
    ///   the screenshot, where the edge is the bright line; Parhelion keeps
    ///   a faint one, 242 gray, so glass stays visible on white.
    /// - The kit's shadow, black 2% 8 points down with a blur of 15, is
    ///   fainter and tighter than the screenshot's, which is 244 just below
    ///   the edge, 250 just above it, and still 252 16 points to the side:
    ///   black 8%, 4 down, blur 24.
    static let smallGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 20), offset: 4, blur: 24),
        blurRadius: 6,
        saturation: 2,
        tint: [.init(color: RGBA(red: 252, green: 252, blue: 252, alpha: 153), blendMode: .normal)],
        highlightWidth: 0.5,
        highlightTop: 1,
        highlightBottom: 0.47,
        rim: RGBA(red: 242, green: 242, blue: 242),
        rimWidth: 0.5
    )

    /// Assumed: tinted glass, for prominent toolbar buttons and
    /// `.glassProminent` buttons: the tint color fills the shape under the
    /// small glass's shadow and a fainter bright line, without the darker
    /// ring, as in the iOS 27 UI Kit's prominent toolbar button and the
    /// Human Interface Guidelines' sheet artwork.
    static let prominentGlass = GlassMaterial(
        shadow: smallGlass.shadow,
        blurRadius: 0,
        saturation: 1,
        tint: [],
        highlightWidth: 0.5,
        highlightTop: 0.45,
        highlightBottom: 0.25,
        rim: .clear,
        rimWidth: 0
    )

    /// Assumed: large glass, for alerts, from the iOS 27 UI Kit's alert:
    ///
    /// - The backdrop is blurred with a radius of 30 and saturation 1.4.
    /// - White at 70%, lighten, then 191 gray at 10%, darken: about
    ///   0.27 × backdrop + 180, which makes the 235,235,236 of the Human
    ///   Interface Guidelines' alert artwork over its dimmed screen.
    /// - A 1.5-point white line inside the top and bottom edges, and a
    ///   darker ring outside, as in the same artwork.
    /// - A shadow of black 25%, 18 points down, with a blur of 46.
    static let largeGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 64), offset: 18, blur: 46),
        blurRadius: 30,
        saturation: 1.4,
        tint: [
            .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 179), blendMode: .lighten),
            .init(color: RGBA(red: 191, green: 191, blue: 191, alpha: 26), blendMode: .darken),
        ],
        highlightWidth: 1.5,
        highlightTop: 1,
        highlightBottom: 1,
        rim: RGBA(red: 200, green: 200, blue: 200),
        rimWidth: 0.5
    )

    /// Assumed: the glass of a sheet at a partial-height detent: large glass
    /// with a blur radius of 15, in the iOS 27 UI Kit's medium-detent sheet,
    /// and the sheet's shadow.
    static let partialSheetGlass: GlassMaterial = {
        var material = largeGlass
        material.blurRadius = 15
        material.shadow = sheetShadow
        return material
    }()

    /// Assumed: the shadow of a sheet, black 18%, 15 points down, with a
    /// blur of 50, in the iOS 27 UI Kit.
    static let sheetShadow = GlassMaterial.Shadow(
        color: RGBA(red: 0, green: 0, blue: 0, alpha: 46), offset: 15, blur: 50)

    /// Assumed: the opacity of a button's label while it is pressed, as with
    /// SwiftUI's default button style on iOS.
    static let pressedOpacity = 0.25

    /// The highlight behind the selected tab in the tab bar: 120,120,128 at
    /// 16%, a full capsule, in the iOS 27 UI Kit.
    static let tabBarSelection = RGBA(red: 120, green: 120, blue: 128, alpha: 41)

    private static func rgbaComponents(_ name: String) -> [Double]? {
        guard name.hasPrefix("rgba("), name.hasSuffix(")") else { return nil }
        let values = name.dropFirst(5).dropLast().split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        return values.count == 4 ? values : nil
    }
}

// MARK: - Controls

extension ColorPalette {
    /// The opacity of a control turned off with `disabled(_:)`, 50% in the
    /// iOS 27 UI Kit's disabled switches, sliders, and segmented controls.
    static let disabledOpacity = 0.5

    /// The track of a switch that is off, 60,60,67 at 30% in the iOS 27 UI
    /// Kit.
    static let switchOffTrack = RGBA(red: 60, green: 60, blue: 67, alpha: 77)

    /// The track of a switch that is on when no tint is set: the system
    /// green, as in the iOS 27 UI Kit.
    static let switchOnTrackStyle = "green"

    /// The knob of a switch or a slider, white in the iOS 27 UI Kit.
    static let knob = RGBA.white

    /// The track of a slider, 120 gray at 20% in the iOS 27 UI Kit. The part
    /// before the knob takes the tint color.
    static let sliderTrack = RGBA(red: 120, green: 120, blue: 120, alpha: 51)

    /// The shadows under a slider's knob, black at 12% 6 points down with a
    /// blur of 13 and half a point down with a blur of 4, in the iOS 27 UI Kit.
    static let sliderKnobShadows = [
        GlassMaterial.Shadow(
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 31), offset: 6, blur: 13),
        GlassMaterial.Shadow(
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 31), offset: 0.5, blur: 4),
    ]

    /// The fill of a stepper and a segmented control: the tertiary fill,
    /// 118,118,128 at 12%, in the iOS 27 UI Kit.
    static let controlFill = tertiaryFill

    /// The line between a stepper's halves, 60,60,67 at 30% in the iOS 27 UI
    /// Kit.
    static let stepperSeparator = RGBA(red: 60, green: 60, blue: 67, alpha: 77)

    /// The color a pressed half of a stepper adds, black at 8%, drawn
    /// plus-darker in the iOS 27 UI Kit.
    static let stepperPressed = RGBA(red: 0, green: 0, blue: 0, alpha: 20)

    /// The shadow of a segmented control's selected segment, black at 6%, 2
    /// points down with a blur of 20, in the iOS 27 UI Kit. The segment is
    /// white.
    static let segmentShadow = GlassMaterial.Shadow(
        color: RGBA(red: 0, green: 0, blue: 0, alpha: 15), offset: 2, blur: 20)
    static let selectedSegment = RGBA.white

    /// The glass of a menu, from the iOS 27 UI Kit's iPhone menu: large
    /// glass with the backdrop blurred with a radius of 15, and a tint of 204
    /// gray at 70%, lighten, under 191 gray at 10%, darken.
    static let menuGlass: GlassMaterial = {
        var material = largeGlass
        material.blurRadius = 15
        material.tint = [
            .init(color: RGBA(red: 204, green: 204, blue: 204, alpha: 179), blendMode: .lighten),
            .init(color: RGBA(red: 191, green: 191, blue: 191, alpha: 26), blendMode: .darken),
        ]
        return material
    }()

    /// The highlight of a pressed menu item, 237 gray drawn plus-darker in the
    /// iOS 27 UI Kit.
    static let menuHighlight = RGBA(red: 237, green: 237, blue: 237)
}

// MARK: - Appearances

extension ColorPalette {
    /// The colors and materials of one appearance that differ between light
    /// and dark. Named colors resolve through ``color(named:in:)`` instead.
    struct Appearance {
        var background: RGBA
        var groupedBackground: RGBA
        var groupedRowBackground: RGBA
        var separator: RGBA
        var rowHighlight: RGBA
        var sheetDim: RGBA
        var alertDim: RGBA
        var systemBarForeground: RGBA
        var glassLabel: RGBA
        var alertMessage: RGBA
        /// The fill of a bordered button.
        var borderedFill: RGBA
        /// The fill of an alert's buttons.
        var alertButtonFill: RGBA
        var grabber: RGBA
        var smallGlass: GlassMaterial
        var prominentGlass: GlassMaterial
        var largeGlass: GlassMaterial
        var partialSheetGlass: GlassMaterial
        var menuGlass: GlassMaterial
        var tabBarSelection: RGBA
        var switchOffTrack: RGBA
        var sliderTrack: RGBA
        var stepperFill: RGBA
        var segmentedFill: RGBA
        var stepperSeparator: RGBA
        var segmentShadow: GlassMaterial.Shadow?
        var selectedSegment: RGBA
        /// The highlight of a pressed menu item, and how it blends with the
        /// menu's glass.
        var menuHighlight: RGBA
        var menuHighlightBlendMode: Canvas.BlendMode
        /// The tertiary label color, for a list row's disclosure indicator.
        var tertiaryLabel: RGBA
    }

    /// The appearance of a color scheme. Content in a sheet is `elevated`:
    /// its dark backgrounds are lighter, as iOS's elevated system
    /// backgrounds are. Light content looks the same either way.
    static func appearance(_ scheme: ColorScheme, elevated: Bool = false) -> Appearance {
        switch scheme {
        case .light: light
        case .dark: elevated ? elevatedDark : dark
        }
    }

    /// The light appearance: the constants above.
    static let light = Appearance(
        background: background,
        groupedBackground: groupedBackground,
        groupedRowBackground: groupedRowBackground,
        separator: separator,
        rowHighlight: rowHighlight,
        sheetDim: sheetDim,
        alertDim: alertDim,
        systemBarForeground: systemBarForeground,
        glassLabel: glassLabel,
        alertMessage: alertMessage,
        borderedFill: tertiaryFill,
        alertButtonFill: tertiaryFill,
        grabber: grabber,
        smallGlass: smallGlass,
        prominentGlass: prominentGlass,
        largeGlass: largeGlass,
        partialSheetGlass: partialSheetGlass,
        menuGlass: menuGlass,
        tabBarSelection: tabBarSelection,
        switchOffTrack: switchOffTrack,
        sliderTrack: sliderTrack,
        stepperFill: controlFill,
        segmentedFill: controlFill,
        stepperSeparator: stepperSeparator,
        segmentShadow: segmentShadow,
        selectedSegment: selectedSegment,
        menuHighlight: menuHighlight,
        menuHighlightBlendMode: .plusDarker,
        tertiaryLabel: color(named: "tertiary")
    )

    /// The dark appearance, from the dark swatches, layer styles, and
    /// components of the iOS 27 UI Kit. Like light, colors that the kit
    /// blends with glass are drawn as the color they make over the dark
    /// glass, about 26 gray.
    static let dark = Appearance(
        // Backgrounds/Dark - Base/Primary, the screen of the Lists page's
        // Examples/Lists/Dark/Grouped.
        background: RGBA(red: 0, green: 0, blue: 0),
        groupedBackground: RGBA(red: 0, green: 0, blue: 0),
        // Backgrounds Grouped/Dark - Base/Secondary, Lists/Dark/Rows/Default.
        groupedRowBackground: RGBA(red: 28, green: 28, blue: 30),
        // Separators/Dark/Non-Opaque, white at 12%.
        separator: RGBA(red: 255, green: 255, blue: 255, alpha: 31),
        // Assumed: systemGray4 in dark (Grays/Dark/Gray 4); the kit has no
        // pressed row.
        rowHighlight: RGBA(red: 58, green: 58, blue: 60),
        // Sheets/􀻃/Overlay/Dark, black at 48%.
        sheetDim: RGBA(red: 0, green: 0, blue: 0, alpha: 122),
        // Alerts/Dark/Overlay/Overlay, 18,18,18 at 56%.
        alertDim: RGBA(red: 18, green: 18, blue: 18, alpha: 143),
        // The Dark Background status bar's contents and the Portrait - Dark
        // home indicator on the System page are white.
        systemBarForeground: .white,
        // Labels - Liquid Glass/Dark/1 Primary, 237 drawn plus-lighter: white
        // over the dark glass.
        glassLabel: .white,
        // Assumed: Labels/Dark - Vibrant/2 Secondary, 153 drawn plus-lighter
        // in Alerts/Dark/Default, is about 179 over the dark alert's glass.
        alertMessage: RGBA(red: 179, green: 179, blue: 179),
        // Buttons/Dark/Medium/Bordered/Text/1 - Idle: 235,235,245 at 30%,
        // the Labels/Dark/3 Tertiary swatch.
        borderedFill: RGBA(red: 235, green: 235, blue: 245, alpha: 77),
        // Alerts/􀻃/Dark/2 Secondary: Fills/Dark/3 Tertiary, 118,118,128 at
        // 24%, drawn plus-lighter, which makes 54,54,57 over the dark glass.
        alertButtonFill: RGBA(red: 54, green: 54, blue: 57),
        // Toolbars/Dark/iPhone/Top - Sheet/Title/Grabber: 51 drawn
        // plus-lighter, about 79 over a sheet's 28,28,30.
        grabber: RGBA(red: 79, green: 79, blue: 81),
        smallGlass: darkSmallGlass,
        prominentGlass: darkProminentGlass,
        largeGlass: darkLargeGlass,
        partialSheetGlass: darkPartialSheetGlass,
        menuGlass: darkMediumGlass,
        // Tab Bars/􀻃/Dark/iPhone/Tab - Default/Selected/Selection:
        // Fills/Dark/2 Secondary, 120,120,128 at 32%.
        tabBarSelection: RGBA(red: 120, green: 120, blue: 128, alpha: 82),
        // Toggles/Dark/Off/1 - Idle: Labels/Dark/3 Tertiary, 235,235,245 at
        // 30%.
        switchOffTrack: RGBA(red: 235, green: 235, blue: 245, alpha: 77),
        // Sliders/􀻃/Track/Dark/Track: Fills/Dark/1 Primary, 120,120,128 at
        // 36%.
        sliderTrack: RGBA(red: 120, green: 120, blue: 128, alpha: 92),
        // Stepper/Dark/􀻃/Increment/1 - Idle: Fills/Dark/4 Quaternary,
        // 118,118,128 at 18%.
        stepperFill: RGBA(red: 118, green: 118, blue: 128, alpha: 46),
        // Segmented Controls/Dark/Small/1 - Enabled: Fills/Dark/3 Tertiary,
        // 118,118,128 at 24%.
        segmentedFill: RGBA(red: 118, green: 118, blue: 128, alpha: 61),
        // Assumed: Labels/Dark/3 Tertiary. The kit's Stepper/Dark/Separator
        // keeps the light swatch, which would not show on dark.
        stepperSeparator: RGBA(red: 235, green: 235, blue: 245, alpha: 77),
        // Segmented Controls/􀻃/Dark/5 - Selected: white at 27%, without the
        // light segment's shadow.
        segmentShadow: nil,
        selectedSegment: RGBA(red: 255, green: 255, blue: 255, alpha: 69),
        // Menus/􀻃/Dark/BG Selection/Show/BG: Selection: Fills/Dark - Vibrant/3
        // Tertiary, 18 drawn plus-lighter.
        menuHighlight: RGBA(red: 18, green: 18, blue: 18),
        menuHighlightBlendMode: .plusLighter,
        // Lists/􀻃/Dark/Rows/Accessories - Trailing: the disclosure chevron is
        // Labels/Dark/3 Tertiary.
        tertiaryLabel: RGBA(red: 235, green: 235, blue: 245, alpha: 76)
    )

    /// The dark appearance of content in a sheet. A sheet at its large
    /// detent is 28,28,30 (Sheets/Dark/iPhone/Large Detent/Stack), the value
    /// of Backgrounds/Dark - Elevated/Primary. Assumed: a grouped list in a
    /// sheet uses the elevated grouped backgrounds, 28,28,30 behind cells of
    /// 44,44,46 (Backgrounds Grouped/Dark - Elevated/Primary and Secondary).
    static let elevatedDark: Appearance = {
        var appearance = dark
        appearance.background = RGBA(red: 28, green: 28, blue: 30)
        appearance.groupedBackground = RGBA(red: 28, green: 28, blue: 30)
        appearance.groupedRowBackground = RGBA(red: 44, green: 44, blue: 46)
        return appearance
    }()

    /// Small glass in the dark appearance, from the layer style Liquid
    /// Glass/Dark/Regular - Small (Toolbars/Dark/Buttons/44pt/Active/Symbol
    /// 1, the dark tab bar):
    ///
    /// - The backdrop is blurred with a radius of 6, without saturation.
    /// - Black at 100%, screen, which changes nothing, then 153 gray at 17%:
    ///   0.83 × backdrop + 26, which is 26 over black.
    /// - The kit's shadow, black 4%, 8 points down, with a blur of 15.
    /// - A 0.5-point ring of 191 gray, plus-darker.
    /// - Assumed: until a dark screenshot exists to tune it as light was
    ///   tuned, the bright line is 40% at the top and 20% at the bottom,
    ///   which adds about the kit's 102 to the glass at the top, with the
    ///   light line's ratio from top to bottom.
    static let darkSmallGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 10), offset: 8, blur: 15),
        blurRadius: 6,
        saturation: 1,
        tint: [.init(color: RGBA(red: 153, green: 153, blue: 153, alpha: 43), blendMode: .normal)],
        highlightWidth: 0.5,
        highlightTop: 0.4,
        highlightBottom: 0.2,
        rim: RGBA(red: 191, green: 191, blue: 191),
        rimWidth: 0.5
    )

    /// Tinted glass in the dark appearance: the light recipe with the dark
    /// small glass's shadow. The tint color is the dark blue, through
    /// ``color(named:in:)`` (Toolbars/Dark/Buttons/44pt/Active/Symbol 1 -
    /// Prominent/Tint Color is System Colors/Dark/8 Blue).
    static let darkProminentGlass: GlassMaterial = {
        var material = prominentGlass
        material.shadow = darkSmallGlass.shadow
        return material
    }()

    /// Large glass in the dark appearance, for alerts, from the layer style
    /// Liquid Glass/Dark/Regular - Large (Alerts/Dark/Default):
    ///
    /// - The backdrop is blurred with a radius of 30 and saturation 1.2.
    /// - 26 gray at 50%, normal; at 90%, luminosity; and at 100%, lighten:
    ///   26 over the dimmed dark screen.
    /// - A shadow of black 45%, 18 points down, with a blur of 48.
    /// - Assumed: a 1.5-point bright line of 45% at the top and 25% at the
    ///   bottom, for the kit's white 20% top line and its 64 gray edge
    ///   lighting, and a ring of black 50%, the kit's outer ring, drawn
    ///   plus-darker.
    static let darkLargeGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 115), offset: 18, blur: 48),
        blurRadius: 30,
        saturation: 1.2,
        tint: [
            .init(color: RGBA(red: 26, green: 26, blue: 26, alpha: 128), blendMode: .normal),
            .init(color: RGBA(red: 26, green: 26, blue: 26, alpha: 230), blendMode: .luminosity),
            .init(color: RGBA(red: 26, green: 26, blue: 26), blendMode: .lighten),
        ],
        highlightWidth: 1.5,
        highlightTop: 0.45,
        highlightBottom: 0.25,
        rim: RGBA(red: 0, green: 0, blue: 0, alpha: 128),
        rimWidth: 0.5
    )

    /// Medium glass in the dark appearance, for menus, from the layer style
    /// Liquid Glass/Dark/Regular - Medium (Menus/Dark/iPhone): dark large
    /// glass with a tint of 26 gray at 30%, normal, and at 30%, luminosity,
    /// under 26 gray, lighten, and a ring of 166 gray, plus-darker.
    static let darkMediumGlass: GlassMaterial = {
        var material = darkLargeGlass
        material.tint = [
            .init(color: RGBA(red: 26, green: 26, blue: 26, alpha: 77), blendMode: .normal),
            .init(color: RGBA(red: 26, green: 26, blue: 26, alpha: 77), blendMode: .luminosity),
            .init(color: RGBA(red: 26, green: 26, blue: 26), blendMode: .lighten),
        ]
        material.rim = RGBA(red: 166, green: 166, blue: 166)
        return material
    }()

    /// The glass of a sheet at a partial-height detent in the dark
    /// appearance: dark medium glass (Sheets/Dark/iPhone/Medium
    /// Detent/Stack), with the sheet's shadow, as in light.
    static let darkPartialSheetGlass: GlassMaterial = {
        var material = darkMediumGlass
        material.shadow = sheetShadow
        return material
    }()

    /// The dark value of a named color, or `nil` when it is the same in both
    /// appearances. System colors are the System Colors/Dark and Grays/Dark
    /// swatches, and labels the Labels/Dark swatches.
    private static func darkColor(named name: String) -> RGBA? {
        switch name {
        case "red": RGBA(red: 255, green: 66, blue: 69)
        case "orange": RGBA(red: 255, green: 146, blue: 48)
        case "yellow": RGBA(red: 255, green: 214, blue: 0)
        case "green": RGBA(red: 48, green: 209, blue: 88)
        case "mint": RGBA(red: 0, green: 218, blue: 195)
        case "teal": RGBA(red: 0, green: 210, blue: 224)
        case "cyan": RGBA(red: 60, green: 211, blue: 254)
        case "blue", "tint", "accentColor": RGBA(red: 0, green: 145, blue: 255)
        case "indigo": RGBA(red: 109, green: 124, blue: 255)
        case "purple": RGBA(red: 219, green: 52, blue: 242)
        case "pink": RGBA(red: 255, green: 55, blue: 95)
        case "brown": RGBA(red: 183, green: 138, blue: 102)
        case "primary": .white
        case "secondary": RGBA(red: 235, green: 235, blue: 245, alpha: 153)
        case "tertiary": RGBA(red: 235, green: 235, blue: 245, alpha: 76)
        case "quaternary": RGBA(red: 235, green: 235, blue: 245, alpha: 41)
        case glassLabelStyle: dark.glassLabel
        case alertMessageStyle: dark.alertMessage
        case tertiaryFillStyle: dark.borderedFill
        default: nil
        }
    }
}
