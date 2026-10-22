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

    /// Assumed: the insets around a list row's content, on iOS.
    static let listRowInsets = EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20)

    /// Assumed: the minimum height of a list row, iOS's minimum tap target.
    static let listRowMinHeight: CGFloat = 44

    /// Assumed: the space around the sections of an inset grouped list.
    static let listContentInsets = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)

    /// Assumed: the space between the sections of a grouped list.
    static let listSectionSpacing: CGFloat = 35

    /// Assumed: the corner radius of a section in an inset grouped list.
    static let listCornerRadius: CGFloat = 10

    /// Assumed: the insets around a section header in a list.
    static let listHeaderInsets = EdgeInsets(top: 0, leading: 20, bottom: 7, trailing: 20)

    /// Assumed: the insets around a section footer in a list.
    static let listFooterInsets = EdgeInsets(top: 7, leading: 20, bottom: 0, trailing: 20)

    /// Assumed: the thickness of a list's row separators, one pixel on a 3×
    /// screen.
    static let listSeparatorThickness: CGFloat = 1.0 / 3

    /// Assumed: the space between a navigation link's label and the
    /// disclosure indicator at the trailing edge of its list row.
    static let disclosureIndicatorSpacing: CGFloat = 12

    /// Assumed: the size of the disclosure indicator, the chevron at the
    /// trailing edge of a navigation link's list row.
    static let disclosureIndicatorSize = CGSize(width: 7, height: 12)

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

    /// Assumed: the space between the back button and the leading edge of
    /// the screen.
    static let backButtonMargin: CGFloat = 8

    /// Assumed: the space between the back button's chevron and its title.
    static let backButtonSpacing: CGFloat = 3

    /// Assumed: the space between items in a group of toolbar items.
    static let toolbarItemSpacing: CGFloat = 16

    /// Assumed: the space between the top of the safe area and the top of a
    /// sheet at its large detent.
    static let sheetTopInset: CGFloat = 10

    /// Assumed: the corner radius of a sheet's top corners.
    static let sheetCornerRadius: CGFloat = 10

    /// Assumed: how far a sheet must be dragged down to dismiss it when
    /// released, in points.
    static let sheetDismissDistance: CGFloat = 100

    /// Assumed: the width of an alert.
    static let alertWidth: CGFloat = 270

    /// Assumed: the corner radius of an alert.
    static let alertCornerRadius: CGFloat = 14

    /// Assumed: the space around an alert's title and message.
    static let alertContentInsets = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)

    /// Assumed: the space between an alert's title and message.
    static let alertContentSpacing: CGFloat = 4

    /// Assumed: the height of each button in an alert.
    static let alertButtonHeight: CGFloat = 44

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
