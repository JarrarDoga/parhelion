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
    /// the iOS 27 UI Kit. The kit's corners are continuous; Parhelion draws
    /// circular ones.
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

    /// Assumed: the side of a symbol image relative to the font size, for
    /// each image scale. Parhelion has no SF Symbols, so every symbol is a
    /// square of this size.
    static func symbolSide(for scale: Image.Scale) -> CGFloat {
        switch scale {
        case .small: bodyFontSize * 0.78
        case .medium: bodyFontSize
        case .large: bodyFontSize * 1.29
        }
    }
}
