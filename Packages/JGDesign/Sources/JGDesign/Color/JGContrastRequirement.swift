/// A foreground/background token pair that must meet a WCAG contrast minimum.
public struct JGContrastRequirement: Sendable {
    /// What the foreground is, which sets the minimum ratio.
    public enum Role: Sendable {
        /// Text: at least 4.5:1.
        case text
        /// Icons, selection edges, meaningful lines: at least 3:1.
        case graphic
    }

    public let foreground: JGColorToken
    public let background: JGColorToken
    public let role: Role
    /// The pair is decorative at normal contrast and only enforced with Increase Contrast.
    public let increasedContrastOnly: Bool

    /// The minimum WCAG ratio for this pair.
    public var minimumRatio: Double {
        switch role {
        case .text: 4.5
        case .graphic: 3.0
        }
    }

    /// The pair's actual ratio in a given appearance.
    public func ratio(isDark: Bool, increasedContrast: Bool) -> Double {
        foreground.value(isDark: isDark, increasedContrast: increasedContrast)
            .contrastRatio(with: background.value(isDark: isDark, increasedContrast: increasedContrast))
    }
}

/// Every token pair the design uses that has a contrast obligation (docs/DESIGN.md §3).
public enum JGContrastRequirements {
    public static let all: [JGContrastRequirement] = {
        var pairs: [JGContrastRequirement] = []
        func add(
            _ foreground: JGColorToken,
            on backgrounds: [JGColorToken],
            _ role: JGContrastRequirement.Role,
            increasedContrastOnly: Bool = false
        ) {
            for background in backgrounds {
                pairs.append(JGContrastRequirement(
                    foreground: foreground,
                    background: background,
                    role: role,
                    increasedContrastOnly: increasedContrastOnly
                ))
            }
        }
        let surfaces = [JGColor.bgBase, JGColor.bgPanel, JGColor.bgRaised]
        add(JGColor.textPrimary, on: surfaces + [JGColor.bgMedia, JGColor.accentDim], .text)
        add(JGColor.textSecondary, on: surfaces, .text)
        add(JGColor.textTertiary, on: surfaces, .text)
        // Primary button: background-colored label on a text.primary block.
        add(JGColor.bgBase, on: [JGColor.textPrimary], .text)
        for status in [JGColor.accentText, JGColor.danger, JGColor.success, JGColor.warning] {
            add(status, on: [JGColor.bgBase, JGColor.bgPanel], .text)
        }
        // The accent itself is exactly the color chosen (D-98, D-105); accent.text carries the obligation.
        add(JGColor.accentText, on: surfaces + [JGColor.bgMedia], .graphic)
        add(JGColor.accentOn, on: [JGColor.accent], .text)
        // Players: artist and album under the title, unplayed waveform.
        add(JGColor.textSecondary, on: [JGColor.bgMedia], .text)
        add(JGColor.textTertiary, on: [JGColor.bgMedia], .graphic)
        add(JGColor.lineHair, on: surfaces, .graphic, increasedContrastOnly: true)
        add(JGColor.lineStrong, on: surfaces, .graphic, increasedContrastOnly: true)
        return pairs
    }()
}
