#if canImport(Foundation)
import Foundation
#endif

/// Every value in which Parhelion's layout assumes how SwiftUI behaves.
///
/// These numbers come from Apple's documentation, the Human Interface
/// Guidelines, and observation. None of them has been checked automatically
/// against SwiftUI yet. They are collected here so that the planned macOS
/// fidelity job can verify each one; see docs/roadmap.md.
enum LayoutDefaults {
    /// Assumed: the length `padding()` uses when no length is given, on iOS.
    static let padding: CGFloat = 16

    /// Assumed: the spacing between adjacent children of a stack when
    /// `spacing` is `nil`. SwiftUI varies this by the kinds of the two
    /// children; Parhelion uses one value for every pair.
    static let stackSpacing: CGFloat = 8

    /// Assumed: the minimum length of a `Spacer` when `minLength` is `nil`.
    static let spacerMinLength: CGFloat = 8

    /// Assumed: how far a press moves over a scroll view before it becomes a
    /// scroll and cancels any button press, in points.
    static let dragThreshold: CGFloat = 10

    /// Assumed: the fraction of scroll velocity kept per millisecond after
    /// a drag ends, `UIScrollView.DecelerationRate.normal` on iOS.
    static let scrollDecelerationRate = 0.998

    /// Assumed: the slowest release, in points per second, that keeps the
    /// content moving after a drag.
    static let minimumFlingSpeed: CGFloat = 50

    /// Assumed: the speed, in points per second, below which scroll momentum
    /// stops.
    static let momentumStopSpeed: CGFloat = 5

    /// The size, line height, and weight of a text style.
    struct TextStyleMetrics {
        var size: CGFloat
        var lineHeight: CGFloat
        var weight: Font.Weight
    }

    /// Assumed: the size, line height, and weight of each text style at the
    /// default ("Large") Dynamic Type size, on iOS. From the typography
    /// table of the Human Interface Guidelines, which the iOS 27 UI Kit's
    /// text styles repeat.
    static func textStyleMetrics(_ style: Font.TextStyle) -> TextStyleMetrics {
        switch style {
        case .largeTitle: TextStyleMetrics(size: 34, lineHeight: 41, weight: .regular)
        case .title: TextStyleMetrics(size: 28, lineHeight: 34, weight: .regular)
        case .title2: TextStyleMetrics(size: 22, lineHeight: 28, weight: .regular)
        case .title3: TextStyleMetrics(size: 20, lineHeight: 25, weight: .regular)
        case .headline: TextStyleMetrics(size: 17, lineHeight: 22, weight: .semibold)
        case .body: TextStyleMetrics(size: 17, lineHeight: 22, weight: .regular)
        case .callout: TextStyleMetrics(size: 16, lineHeight: 21, weight: .regular)
        case .subheadline: TextStyleMetrics(size: 15, lineHeight: 20, weight: .regular)
        case .footnote: TextStyleMetrics(size: 13, lineHeight: 18, weight: .regular)
        case .caption: TextStyleMetrics(size: 12, lineHeight: 16, weight: .regular)
        case .caption2: TextStyleMetrics(size: 11, lineHeight: 13, weight: .regular)
        }
    }

    /// Assumed: the line height of the system font at a fixed size, such as
    /// `.system(size: 13)`: San Francisco's own line height, about 1.2 times
    /// the size, rounded to a whole point. This gives the 16-point lines of
    /// 13-point list footers in the iOS 27 UI Kit.
    static func systemLineHeight(size: CGFloat) -> CGFloat {
        (size * 1.2).rounded()
    }

    /// The point size of the `body` text style.
    static var bodyFontSize: CGFloat { textStyleMetrics(.body).size }

    /// Assumed: the ideal size of a view that fills its proposal, such as
    /// `Color`, when the parent proposes no size.
    static let flexibleIdealSize: CGFloat = 10

    /// Assumed: the insets around a list row's content, from the iOS 27 UI
    /// Kit: a line of body text sits 15 points from the top and bottom of a
    /// 52-point row, and 16 points from its sides.
    static let listRowInsets = EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)

    /// Assumed: the minimum height of a list row, 52 points in the iOS 27 UI
    /// Kit.
    static let listRowMinHeight: CGFloat = 52

    /// Assumed: the space around the sections of an inset grouped list. In a
    /// real iOS 26 SwiftUI screenshot, a first section without a header
    /// starts right below a large title's bar, so there is no space above.
    static let listContentInsets = EdgeInsets(top: 0, leading: 16, bottom: 20, trailing: 16)

    /// Assumed: the space between the sections of a grouped list, from the
    /// bottom of one section's footer to the top of the next one's header,
    /// in the iOS 27 UI Kit.
    static let listSectionSpacing: CGFloat = 20

    /// Assumed: the corner radius of a section in an inset grouped list, in
    /// the iOS 27 UI Kit, with continuous corners.
    static let listCornerRadius: CGFloat = 26

    /// Assumed: the insets around a section header in a list: one line of
    /// header text makes a 42-point block in the iOS 27 UI Kit.
    static let listHeaderInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

    /// Assumed: the insets around a section footer in a list: one line of
    /// footer text makes a 30-point block, 8 points below the cells, in the
    /// iOS 27 UI Kit.
    static let listFooterInsets = EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16)

    /// Assumed: the font of a list's section headers, semibold 17 points on
    /// a 22-point line in the iOS 27 UI Kit, which is `headline`. Headers are
    /// in mixed case, not uppercase, since iOS 26.
    static let listHeaderFont = Font.headline

    /// Assumed: the font of a list's section footers, 13 points on a 16-point
    /// line in the iOS 27 UI Kit.
    static let listFooterFont = Font.system(size: 13)

    /// Assumed: the thickness of a list's row separators, one pixel on a 3×
    /// screen.
    static let listSeparatorThickness: CGFloat = 1.0 / 3

    /// Assumed: the space between a navigation link's label and the
    /// disclosure indicator at the trailing edge of its list row.
    static let disclosureIndicatorSpacing: CGFloat = 12

    /// Assumed: the size of the disclosure indicator, the chevron at the
    /// trailing edge of a navigation link's list row, measured from the iOS
    /// 27 UI Kit's semibold 17-point `chevron.right`.
    static let disclosureIndicatorSize = CGSize(width: 7.5, height: 12.5)

    /// Assumed: the stroke width of the disclosure indicator.
    static let disclosureIndicatorThickness: CGFloat = 1.75

    /// Assumed: the height of the navigation bar with an inline title: the
    /// 44-point row of buttons and the title, and 10 points below it. From
    /// the iOS 27 UI Kit's standard top toolbar with a title.
    static let navigationBarHeight: CGFloat = 54

    /// Assumed: the height of the row at the top of the navigation bar that
    /// holds its buttons and an inline title, centered vertically, in the
    /// iOS 27 UI Kit.
    static let navigationBarRowHeight: CGFloat = 44

    /// Assumed: the height of the navigation bar with a large title: the
    /// 44-point row, a 10-point gap, the title's 41-point line, and 10 points
    /// below it. From the iOS 27 UI Kit's standard top toolbar with a large
    /// title.
    static let largeTitleNavigationBarHeight: CGFloat = 105

    /// Assumed: the distance from the top of the navigation bar to the top
    /// of a large title's line, in the iOS 27 UI Kit.
    static let largeTitleTop: CGFloat = 54

    /// Assumed: the font of a large navigation title, bold `largeTitle`
    /// (34 points on a 41-point line) in the iOS 27 UI Kit.
    static let largeTitleFont = Font.largeTitle.bold()

    /// Assumed: the font of an inline navigation title, semibold 17 points
    /// on a 22-point line in the iOS 27 UI Kit, which is `headline`.
    static let inlineTitleFont = Font.headline

    /// Assumed: the space between the navigation bar's items and the edges
    /// of the screen.
    static let navigationBarMargin: CGFloat = 16

    /// Assumed: the side of a glass toolbar button: a 44-point circle for a
    /// symbol, or the height of a capsule for text, in the iOS 27 UI Kit's
    /// toolbar buttons.
    static let toolbarButtonSize: CGFloat = 44

    /// Assumed: the space between a text toolbar button's label and the
    /// ends of its capsule: "Label" makes a 67-point capsule in the iOS 27
    /// UI Kit.
    static let toolbarTextButtonPadding: CGFloat = 12

    /// Assumed: the width each symbol takes in a capsule that several
    /// toolbar items share. The kit's group of two symbols is 104 points
    /// wide and its group of three 160; Parhelion gives each symbol the same
    /// width, which makes three 156.
    static let toolbarGroupedSymbolWidth: CGFloat = 52

    /// Assumed: the space between separate glass items in the navigation
    /// bar, such as the back button and a leading item, in the iOS 27 UI
    /// Kit (buttons at x = 16 and x = 72).
    static let toolbarGroupSpacing: CGFloat = 12

    /// Assumed: the size of the back button's chevron, measured in an iOS 26
    /// Simulator screenshot of an iPhone 17 Pro: about 10.3 × 18 points.
    static let backChevronSize = CGSize(width: 10.33, height: 18)

    /// Assumed: the stroke width of the back button's chevron, about 2.3
    /// points in the same screenshot.
    static let backChevronThickness: CGFloat = 2.3

    /// Assumed: how far left of the button's center the back button's
    /// chevron sits, an optical offset of about 1.7 points in the same
    /// screenshot.
    static let backChevronOpticalOffset: CGFloat = 1.7

    /// Assumed: how far below the top of a sheet its toolbar's buttons sit:
    /// the iOS 27 UI Kit's sheet toolbar is 70 points tall, with 44-point
    /// buttons 16 points from the top.
    static let sheetToolbarTopInset: CGFloat = 16

    /// Assumed: the space between the top of the safe area and the top of a
    /// sheet at its large detent. In iOS 26 and 27, the sheet's top edge is
    /// at the top of the safe area, in the iOS 27 UI Kit and in an iOS 26
    /// Simulator screenshot.
    static let sheetTopInset: CGFloat = 0

    /// Assumed: the corner radius of a sheet's top corners at its large
    /// detent, continuous, in the iOS 27 UI Kit.
    static let sheetCornerRadius: CGFloat = 38

    /// Assumed: the space between a sheet at a partial-height detent, such
    /// as `.medium`, and the left, right, and bottom edges of the screen, in
    /// the iOS 27 UI Kit.
    static let partialSheetInset: CGFloat = 8

    /// Assumed: the corner radius of all four corners of a sheet at a
    /// partial-height detent, continuous, in the iOS 27 UI Kit.
    static let partialSheetCornerRadius: CGFloat = 34

    /// Assumed: the size of a sheet's grabber, 60 × 4 points with fully
    /// rounded ends in the iOS 27 UI Kit, whose change log widens it for
    /// iOS 27.
    static let grabberSize = CGSize(width: 60, height: 4)

    /// Assumed: the space between the top of a sheet and its grabber, in the
    /// iOS 27 UI Kit.
    static let grabberTop: CGFloat = 5

    /// Assumed: how far a sheet must be dragged down to dismiss it when
    /// released, in points.
    static let sheetDismissDistance: CGFloat = 100

    /// Assumed: the width of an alert, 300 points in the iOS 27 UI Kit.
    static let alertWidth: CGFloat = 300

    /// Assumed: the corner radius of an alert, continuous, in the iOS 27 UI
    /// Kit.
    static let alertCornerRadius: CGFloat = 34

    /// Assumed: the space around an alert's title and message, in the iOS
    /// 27 UI Kit: 22 points from the top and sides (the kit's 14-point
    /// group inset plus 8), and 24 points from the message to the buttons.
    static let alertContentInsets = EdgeInsets(top: 22, leading: 22, bottom: 24, trailing: 22)

    /// Assumed: the space between an alert's title and message, and between
    /// its other content, in the iOS 27 UI Kit.
    static let alertContentSpacing: CGFloat = 10

    /// Assumed: the height of each of an alert's capsule buttons, in the
    /// iOS 27 UI Kit.
    static let alertButtonHeight: CGFloat = 48

    /// Assumed: the space between an alert's buttons and its sides and
    /// bottom, in the iOS 27 UI Kit.
    static let alertButtonInset: CGFloat = 14

    /// Assumed: the space between two alert buttons side by side, in the
    /// iOS 27 UI Kit.
    static let alertButtonSpacing: CGFloat = 8

    /// Assumed: the space between alert buttons stacked vertically, which
    /// three or more buttons are, in the iOS 27 UI Kit.
    static let alertStackedButtonSpacing: CGFloat = 12

    /// The height, horizontal padding, and font size of a button with a
    /// bordered or glass style at one control size.
    struct ControlMetrics: Equatable {
        var height: CGFloat
        var padding: CGFloat
        var fontSize: CGFloat
    }

    /// Assumed: the size of a button with a bordered or glass style, from
    /// the iOS 27 UI Kit's small, medium, and large buttons. Matching the
    /// kit's sizes to SwiftUI's control sizes is a guess from their names;
    /// `.mini` draws as `.small`, and `.extraLarge` as `.large`. Glass
    /// buttons are 46 points tall at the large size instead of 50.
    static func controlMetrics(_ size: ControlSize, glass: Bool) -> ControlMetrics {
        switch size {
        case .mini, .small: ControlMetrics(height: 28, padding: 10, fontSize: 15)
        case .regular: ControlMetrics(height: 34, padding: 12, fontSize: 17)
        case .large, .extraLarge:
            ControlMetrics(height: glass ? 46 : 50, padding: 20, fontSize: 17)
        }
    }

    /// Assumed: the duration of a timing-curve animation, such as
    /// `.easeInOut`, when none is given.
    static let animationDuration = 0.35

    /// Assumed: the response of the spring that `Animation.default` uses.
    static let defaultSpringResponse = 0.5

    /// Assumed: the animation of a push or pop in a navigation stack, and of
    /// a sheet or alert appearing and disappearing.
    static let presentationAnimation = Animation.spring(response: 0.4, dampingFraction: 1)

    /// Assumed: the fraction of the stack's width that the screen beneath a
    /// pushed screen moves toward the leading edge.
    static let navigationParallax: CGFloat = 0.3

    /// Assumed: the side of a symbol image in the body font, for each image
    /// scale. Every symbol is a square of this size, scaled by its font's
    /// size.
    static func symbolSide(for scale: Image.Scale) -> CGFloat {
        switch scale {
        case .small: bodyFontSize * 0.78
        case .medium: bodyFontSize
        case .large: bodyFontSize * 1.29
        }
    }

    /// The height of the tab bar: a 62-point glass capsule in the iOS 27 UI
    /// Kit's iPhone tab bar.
    static let tabBarHeight: CGFloat = 62

    /// The space between the tab bar and the sides of the screen, 21 points
    /// in the iOS 27 UI Kit.
    static let tabBarMargin: CGFloat = 21

    /// The space between the bottom of the tab bar and the bottom of the
    /// screen: 21 points in the iOS 27 UI Kit, so the bar floats above the
    /// home indicator, 13 points below the safe area.
    static let tabBarBottomMargin: CGFloat = 21

    /// The space between the tab bar's capsule and the tabs in it: tabs are
    /// 54 points tall, 4 points from the top and bottom and 8 from the ends,
    /// and share the width equally, in the iOS 27 UI Kit.
    static let tabBarItemInsets = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

    /// How far the selected tab's highlight reaches past the tab at each
    /// end: 4 points in the iOS 27 UI Kit, so it is 4 points from the ends
    /// of the capsule.
    static let tabBarSelectionOutset: CGFloat = 4

    /// The space between the tabs' capsule and the search tab's circle, 8
    /// points in the iOS 27 UI Kit. The circle is as tall as the bar.
    static let tabBarSearchSpacing: CGFloat = 8

    /// The distance from the top of a tab to the middle of its symbol: the
    /// kit's symbol is on a 28-point line 7 points from the top of the tab.
    /// Assumed: the symbol is centered on that line.
    static let tabBarSymbolCenter: CGFloat = 21

    /// The distance from the top of a tab to the top of its title, 36 points
    /// in the iOS 27 UI Kit.
    static let tabBarTitleTop: CGFloat = 36

    /// The font of a tab's symbol, semibold 18 points in the iOS 27 UI Kit.
    static let tabBarSymbolFont = Font.system(size: 18, weight: .semibold)

    /// The font of the search tab's symbol, semibold 17 points in the iOS 27
    /// UI Kit.
    static let tabBarSearchSymbolFont = Font.system(size: 17, weight: .semibold)

    /// The font of a tab's title, semibold 10 points in the iOS 27 UI Kit.
    static let tabBarTitleFont = Font.system(size: 10, weight: .semibold)
}

// MARK: - Controls

extension LayoutDefaults {
    /// Assumed: the space between a control's label at the leading edge and
    /// the control at the trailing edge, at the least.
    static let controlLabelSpacing: CGFloat = 16

    /// The size of a switch, 64 × 28 points in the iOS 27 UI Kit, with fully
    /// rounded ends.
    static let switchSize = CGSize(width: 64, height: 28)

    /// The size of a switch's knob, a 38 × 24 capsule 2 points inside the
    /// track, in the iOS 27 UI Kit.
    static let switchKnobSize = CGSize(width: 38, height: 24)

    /// The space between a switch's knob and the ends of its track, in the
    /// iOS 27 UI Kit.
    static let switchKnobInset: CGFloat = 2

    /// The size of the glass lens a switch's knob becomes while the switch is
    /// pressed, 58 × 38 around the knob's center in the iOS 27 UI Kit.
    static let switchPressedKnobSize = CGSize(width: 58, height: 38)

    /// Assumed: the animation of a switch's knob when its value changes.
    static let switchAnimation = Animation.snappy(duration: 0.3)

    /// The vertical insets of a list row that holds a control taller than a
    /// line of text, so that the row stays 52 points tall: in the iOS 27 UI
    /// Kit, a switch sits 12 points from the top and bottom, and a stepper
    /// 10.
    static func controlRowVerticalInset(controlHeight: CGFloat) -> CGFloat {
        max((listRowMinHeight - controlHeight) / 2, 0)
    }

    /// Assumed: the thickness of a `Divider`, one pixel on a 3× screen, like
    /// a list's separators.
    static let dividerThickness: CGFloat = 1.0 / 3

    /// The height of a slider, the iOS 27 UI Kit's 22-point track symbol.
    /// The 24-point knob reaches a point beyond it at the top and bottom, so a
    /// slider row is 52 points tall with the usual insets.
    static let sliderHeight: CGFloat = 22

    /// The thickness of a slider's track, with fully rounded ends, in the iOS
    /// 27 UI Kit.
    static let sliderTrackThickness: CGFloat = 6

    /// The size of a slider's knob, a 37 × 24 capsule, in the iOS 27 UI Kit.
    static let sliderKnobSize = CGSize(width: 37, height: 24)

    /// The size of the glass lens a slider's knob becomes while it is
    /// dragged, 57 × 38 around the knob's center in the iOS 27 UI Kit.
    static let sliderPressedKnobSize = CGSize(width: 57, height: 38)

    /// The space between a slider's track and its minimum and maximum value
    /// labels, in the iOS 27 UI Kit.
    static let sliderValueLabelSpacing: CGFloat = 12

    /// Assumed: the width of a slider's track when the slider is offered no
    /// width.
    static let sliderIdealTrackWidth: CGFloat = 100

    /// The size of each half of a stepper, 46 × 32 points, making a 92 × 32
    /// capsule in the iOS 27 UI Kit.
    static let stepperButtonSize = CGSize(width: 46, height: 32)

    /// The size of the line between a stepper's halves, in the iOS 27 UI Kit.
    static let stepperSeparatorSize = CGSize(width: 1, height: 24)

    /// Assumed: the width and stroke of a stepper's minus and plus, measured
    /// from the iOS 27 UI Kit's semibold 17-point `minus` and `plus`.
    static let stepperSymbolSize: CGFloat = 13.5
    static let stepperSymbolThickness: CGFloat = 2

    /// The height of a segmented control, the iOS 27 UI Kit's small
    /// segmented control, which `UISegmentedControl` matches.
    static let segmentedControlHeight: CGFloat = 32

    /// The space between a segmented control's edge and its segments, and
    /// between segments, in the iOS 27 UI Kit.
    static let segmentInset: CGFloat = 2
    static let segmentSpacing: CGFloat = 4

    /// The font of a segment's label, medium 13.33 points in the iOS 27 UI
    /// Kit, and semibold for the selected segment.
    static let segmentFont = Font.system(size: 13.33, weight: .medium)

    /// Assumed: the space between a segment's label and its ends, for the
    /// width of a segmented control that is offered no width. Segments share
    /// the width equally, as `UISegmentedControl`'s do.
    static let segmentPadding: CGFloat = 12

    /// How far the glass lens of a pressed segment reaches past the segment:
    /// an 80 × 28 segment's lens is 100 × 42 in the iOS 27 UI Kit.
    static let pressedSegmentOutset = CGSize(width: 10, height: 7)

    /// Assumed: the animation of the selected segment's capsule when the
    /// selection changes.
    static let segmentAnimation = Animation.snappy(duration: 0.3)

    /// The size of the `chevron.up.chevron.down` symbol of a menu picker's
    /// button, a 12 × 22 regular 17-point glyph, and its space from the
    /// value, in the iOS 27 UI Kit's pop-up button.
    static let menuIndicatorSize = CGSize(width: 12, height: 22)
    static let menuIndicatorSpacing: CGFloat = 10

    /// Assumed: the size of each chevron of the `chevron.up.chevron.down`
    /// symbol, its stroke, and the space between the two.
    static let menuIndicatorChevronSize = CGSize(width: 8, height: 4.5)
    static let menuIndicatorChevronThickness: CGFloat = 1.6
    static let menuIndicatorChevronGap: CGFloat = 3

    /// The width of a menu on iPhone, 250 points in the iOS 27 UI Kit.
    static let menuWidth: CGFloat = 250

    /// The corner radius of a menu, continuous, in the iOS 27 UI Kit.
    static let menuCornerRadius: CGFloat = 32

    /// The space between a menu's edge and its items, in the iOS 27 UI Kit.
    static let menuPadding: CGFloat = 10

    /// The height of a menu item with one line of text, in the iOS 27 UI Kit.
    static let menuItemHeight: CGFloat = 42

    /// The insets of a menu item's text in its 230-point cell: 40 points from
    /// the leading edge, after the checkmark's column, in the iOS 27 UI Kit,
    /// and 10 above and below, which centers a 22-point line of body text in
    /// the kit's 42-point item, as the kit centers its 20-point line.
    /// Assumed: 16 from the trailing edge.
    static let menuItemInsets = EdgeInsets(top: 10, leading: 40, bottom: 10, trailing: 16)

    /// The space between a menu item's cell and its checkmark's 14-point
    /// column, in the iOS 27 UI Kit.
    static let menuCheckmarkInset: CGFloat = 16
    static let menuCheckmarkColumn = CGSize(width: 14, height: 20)

    /// The corner radius of a pressed menu item's highlight, in the iOS 27 UI
    /// Kit.
    static let menuHighlightCornerRadius: CGFloat = 20

    /// The space between a menu and the edges of the screen, 16 points in the
    /// iOS 27 UI Kit's example.
    static let menuMargin: CGFloat = 16

    /// The column at the trailing edge of a list row that holds a
    /// checkmark, the iOS 27 UI Kit's 22-point glyph box, and its space from
    /// the row's content. Assumed: the space.
    static let listCheckmarkColumn = CGSize(width: 22, height: 22)
    static let listCheckmarkSpacing: CGFloat = 12

    /// Assumed: the size and stroke of a checkmark, measured from the iOS 27
    /// UI Kit's semibold `checkmark`: 17 points in lists and 15 in menus.
    static let listCheckmarkSize = CGSize(width: 15, height: 14)
    static let listCheckmarkThickness: CGFloat = 2.2
    static let menuCheckmarkSize = CGSize(width: 13, height: 12)
    static let menuCheckmarkThickness: CGFloat = 2
}
