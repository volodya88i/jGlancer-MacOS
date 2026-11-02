import SwiftUI

/// Text styles (docs/DESIGN.md §4). System fonts only: SF Pro (expanded for display) and SF Mono.
///
/// Few sizes on purpose: one display size, one heading, one text size, one small size.
public enum JGTextStyle: CaseIterable, Sendable {
    /// Empty states, onboarding, about: 32 pt heavy expanded, tight tracking. One per screen at most.
    case display
    /// Pane and dialog titles: 17 pt semibold expanded.
    case heading
    /// Content text: 13 pt regular.
    case body
    /// Button and menu titles: 13 pt medium, normal case.
    case button
    /// Section labels and kind chips: 11 pt semibold, uppercase, wide tracking.
    case label
    /// Technical data (sizes, counts, time codes, extensions): 11 pt SF Mono with even digits.
    case mono

    /// No text style may be smaller than this (docs/DECISIONS.md D-18).
    public static let minimumSize: CGFloat = 11

    /// Point size.
    public var size: CGFloat {
        switch self {
        case .display: 32
        case .heading: 17
        case .body, .button: 13
        case .label, .mono: 11
        }
    }

    /// Letter spacing in points (proportional to size: −3 % display, +8 % label).
    public var tracking: CGFloat {
        switch self {
        case .display: -0.03 * size
        case .heading: -0.01 * size
        case .body, .button, .mono: 0
        case .label: 0.08 * size
        }
    }

    /// Whether the style renders in capitals. Applied as a display transform so localized strings stay correct.
    public var isUppercase: Bool {
        self == .label
    }

    /// The font for this style.
    public var font: Font {
        switch self {
        case .display: .system(size: size, weight: .heavy).width(.expanded)
        case .heading: .system(size: size, weight: .semibold).width(.expanded)
        case .body: .system(size: size, weight: .regular)
        case .button: .system(size: size, weight: .medium)
        case .label: .system(size: size, weight: .semibold)
        case .mono: .system(size: size, weight: .regular, design: .monospaced).monospacedDigit()
        }
    }
}

public extension View {
    /// Applies a design-system text style: font, tracking and letter case.
    func jgTextStyle(_ style: JGTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}
