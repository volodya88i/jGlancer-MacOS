/// The color palette (docs/DESIGN.md §3). The only place in the project where hex values live.
///
/// Warm graphite and paper neutrals with one cool accent (DECISIONS D-28). Every pair the design
/// uses is checked for WCAG contrast by `ContrastTests`.
public enum JGColor {
    /// Window background.
    public static let bgBase = JGColorToken("bg.base", dark: 0x121113, light: 0xF4F1EB, black: 0x000000)
    /// Sidebar, panes, bars, panels.
    public static let bgPanel = JGColorToken("bg.panel", dark: 0x1A181A, light: 0xFFFDF9, black: 0x000000)
    /// Hover, selected rows, menus, floating panels, segmented-control tracks.
    public static let bgRaised = JGColorToken("bg.raised", dark: 0x242124, light: 0xEBE6DD, black: 0x1F1F1F)
    /// Behind photos and video in the viewer.
    public static let bgMedia = JGColorToken("bg.media", dark: 0x0A090A, light: 0xE5E0D7, black: 0x000000)
    /// The window's mini player: as `bg.raised`, black in the Black theme (W-97).
    public static let bgPopup = JGColorToken("bg.popup", dark: 0x242124, light: 0xEBE6DD, black: 0x000000)

    /// 1-pixel dividers. Quiet at normal contrast; ≥ 3:1 with Increase Contrast.
    public static let lineHair = JGColorToken(
        "line.hair", dark: 0x2B282B, light: 0xE0D9CE,
        darkIncreasedContrast: 0x77717A, lightIncreasedContrast: 0x8A8378, black: 0x1A1A1A
    )
    /// Outlines of secondary buttons and fields, hover borders. ≥ 3:1 with Increase Contrast.
    public static let lineStrong = JGColorToken(
        "line.strong", dark: 0x3D393D, light: 0xC8C0B3,
        darkIncreasedContrast: 0x8F8890, lightIncreasedContrast: 0x6F685E, black: 0x3D3D3D
    )

    /// Titles, names, key labels.
    public static let textPrimary = JGColorToken("text.primary", dark: 0xF3EEE7, light: 0x1C1917)
    /// Body text and captions.
    public static let textSecondary = JGColorToken("text.secondary", dark: 0xAAA399, light: 0x57504A)
    /// Section labels, hints. Becomes `text.secondary` with Increase Contrast.
    public static let textTertiary = JGColorToken(
        "text.tertiary", dark: 0x8F887E, light: 0x685F57,
        darkIncreasedContrast: 0xAAA399, lightIncreasedContrast: 0x57504A
    )

    /// The single accent: selection edges, progress, switches. Never a large fill. Lavender by default (it went
    /// back to it, D-102); a chosen color is exact in every theme.
    public static let accent = JGColorToken("accent", dark: 0xA396F4, light: 0x5B4FCF)
    /// The accent for text and thin glyphs: a chosen color moves only in lightness, so it reads on each theme's surfaces.
    public static let accentText = JGColorToken("accent.text", dark: 0xA396F4, light: 0x5B4FCF)
    /// What sits on an accent fill: a switch's knob, a tick, the chosen segment's word.
    public static let accentOn = JGColorToken("accent.on", dark: 0x000000, light: 0xFFFFFF)
    /// Selection fill.
    public static let accentDim = JGColorToken("accent.dim", dark: 0x372F5A, light: 0xE6E0F8)

    /// Destructive actions.
    public static let danger = JGColorToken("danger", dark: 0xFF6B6B, light: 0xC23737)
    /// Confirmations.
    public static let success = JGColorToken("success", dark: 0x4FD19A, light: 0x177851)
    /// Cautions.
    public static let warning = JGColorToken("warning", dark: 0xF0B04A, light: 0x866207)

    /// Flag stars (DECISIONS D-57), on a tile's badge (`bg.base` at `JGMetrics.flagBadgeOpacity`) or beside a name;
    /// ≥ 3:1 over any media.
    public static let flagRed = JGColorToken("flag.red", dark: 0xFF8080, light: 0x9E1C12)
    public static let flagOrange = JGColorToken("flag.orange", dark: 0xFF9F43, light: 0x8A3C00)
    public static let flagYellow = JGColorToken("flag.yellow", dark: 0xF5D547, light: 0x664C00)
    public static let flagGreen = JGColorToken("flag.green", dark: 0x4FD19A, light: 0x0F5E3A)
    public static let flagBlue = JGColorToken("flag.blue", dark: 0x6BB3FF, light: 0x1A4FA3)
    public static let flagPurple = JGColorToken("flag.purple", dark: 0xCC99FF, light: 0x6A2DB0)

    /// Background of overlays on media (filmstrip, HUD); combine with a blur.
    public static let overlayScrim = JGColorToken("overlay.scrim", dark: 0x121113, light: 0xF4F1EB, black: 0x000000, alpha: 0.72)

    /// Every token, in documentation order.
    public static let all: [JGColorToken] = [
        bgBase, bgPanel, bgRaised, bgMedia, bgPopup,
        lineHair, lineStrong,
        textPrimary, textSecondary, textTertiary,
        accent, accentText, accentOn, accentDim,
        danger, success, warning,
        flagRed, flagOrange, flagYellow, flagGreen, flagBlue, flagPurple,
        overlayScrim,
    ]
}
