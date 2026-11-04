/// How the viewers' filmstrip comes and goes.
public enum FilmstripReveal: String, Codable, CaseIterable, Sendable {
    /// A chevron above the strip hides and shows it by hand.
    case button
    /// The strip appears while the pointer is near the bottom and hides shortly after it leaves.
    case automatic
}

/// How the media-kind filters of the top bar look.
public enum KindFilterStyle: String, Codable, CaseIterable, Sendable {
    /// "VIDEO", "PHOTO", "AUDIO" chips.
    case labels
    /// Small icons joined in one group, split by hairlines.
    case icons
}

/// How audio players draw their scrubber (D-79, W-100); a saved `full` from before reads as the default.
public enum WaveformStyle: String, Codable, CaseIterable, Sendable {
    /// The waveform at half the scrubber's height (the default).
    case narrow
    /// The plain slider, no waveform (and no finer peaks when zoomed).
    case timeline
}

/// The two looks offered on first launch and in Settings → Appearance: lighter on the Mac, or richer. Only the
/// options assigned to it belong to a preset; the others are set on their own.
public enum AppearancePreset: String, Codable, CaseIterable, Sendable {
    case performance
    case beauty

    /// Sets the preset's options in `settings`.
    public func apply(to settings: inout AppSettings) {
        let isBeauty = self == .beauty
        settings.coverBackdrop = isBeauty
        settings.filmstripReveal = isBeauty ? .automatic : .button
        settings.swipeAnimation = isBeauty
        settings.animatesGrid = isBeauty
        settings.frostedGlass = true
    }

    /// The preset whose options `settings` match, or nil when they were mixed by hand.
    public static func matching(_ settings: AppSettings) -> AppearancePreset? {
        allCases.first { preset in
            var copy = settings
            preset.apply(to: &copy)
            return copy == settings
        }
    }
}
