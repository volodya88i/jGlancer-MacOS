import Foundation

/// The app's preferences (docs/FEATURES.md §14), saved as one value. Decoding tolerates missing keys so new
/// settings never reset the others.
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Language: String, Codable, CaseIterable, Sendable {
        case system
        case english
        case russian
    }

    public enum Theme: String, Codable, CaseIterable, Sendable {
        case system
        case dark
        /// A variant of dark: black surfaces, gray only for what is raised (W-97).
        case black
        case light
    }

    /// False until the first-launch choice of a look was answered or skipped.
    public var hasChosenAppearance = false
    public var language: Language = .system
    /// Dark by default (DECISIONS D-20).
    public var theme: Theme = .dark
    /// Settings → Appearance → Accent Color: `#RRGGBB`, nil = the default (W-93).
    public var accentColor: String?
    /// Cap of the thumbnail cache on disk, in gigabytes.
    public var thumbnailCacheGigabytes = 2
    /// Quick Preview starts video and audio by itself.
    public var autoplayInPreview = true
    /// Exported audio segments of WAV, AIFF and FLAC files keep that format; off: always M4A (D-74).
    public var segmentKeepsAudioFormat = true
    /// Video segments are cut exactly at the brackets, encoded again as H.264 MP4; off: copied from the keyframe
    /// before the start (D-108, W-106).
    public var segmentCutsExactly = true
    /// Selecting a segment, the mouse wheel alone zooms the timeline; off: ⌘ + wheel (D-78, W-63).
    public var wheelZoomsTimeline = true
    /// Decor: "+" marks at the corners of selected tiles.
    public var crosshairMarks = false
    /// Fades and slides off even when the system setting is on.
    public var reduceMotion = false
    /// Appearance → Effects: frosted glass behind toasts and progress panels (D-109); on in both presets.
    public var frostedGlass = true
    /// Appearance → Effects: the photo viewer shows what lies behind the window, blurred, instead of its dark
    /// background (D-114). Off by default.
    public var translucentPhotoViewer = false
    /// Appearance (defaults = the Performance preset): a heavily blurred cover art behind audio files.
    public var coverBackdrop = false
    public var filmstripReveal: FilmstripReveal = .button
    /// Swiping between photos or songs drags the neighbor in from the edge.
    public var swipeAnimation = false
    /// Tiles glide to their new places when the tile size, names or sort change (D-83, W-69).
    public var animatesGrid = false
    /// Settings → Library → Image Sequences: numbered frames fold into one tile (D-84).
    public var foldsSequences = true
    public var kindFilterStyle: KindFilterStyle = .labels
    /// Settings → Appearance → Decor → Audio waveform.
    public var waveformStyle: WaveformStyle = .narrow
    /// The video player's scrubber: the plain timeline by default, or the waveform of the video's sound (D-110, W-110).
    public var videoWaveformStyle: WaveformStyle = .timeline
    /// View → Show Status Bar: the counts under the files (D-110).
    public var showsStatusBar = true
    /// Settings → Library → Hide files smaller than, in kilobytes (WIN-061); 0 is off.
    public var minFileKilobytes = 0
    /// Quick Preview's pin (WIN-069): above every window, also while another app is active; off, an ordinary window.
    public var quickPreviewOnTop = true
    /// The preview pane also lists camera, exposure, codecs and rates (always in Get Info).
    public var previewDetails = false

    /// Settings → General → Updates: ask GitHub for a newer version at most once a day (D-104).
    public var checksForUpdates = true
    public var lastUpdateCheck: Date?
    /// The version whose offer was answered with Skip This Version.
    public var skippedVersion: String?

    /// Choices offered for the thumbnail cache cap.
    public static let cacheChoices = [1, 2, 4, 8]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        hasChosenAppearance = try container.decodeIfPresent(Bool.self, forKey: .hasChosenAppearance) ?? defaults.hasChosenAppearance
        language = (try? container.decodeIfPresent(Language.self, forKey: .language)) ?? defaults.language
        theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? defaults.theme
        accentColor = try? container.decodeIfPresent(String.self, forKey: .accentColor)
        thumbnailCacheGigabytes = try container.decodeIfPresent(Int.self, forKey: .thumbnailCacheGigabytes)
            ?? defaults.thumbnailCacheGigabytes
        autoplayInPreview = try container.decodeIfPresent(Bool.self, forKey: .autoplayInPreview) ?? defaults.autoplayInPreview
        wheelZoomsTimeline = try container.decodeIfPresent(Bool.self, forKey: .wheelZoomsTimeline) ?? defaults.wheelZoomsTimeline
        segmentKeepsAudioFormat = try container.decodeIfPresent(Bool.self, forKey: .segmentKeepsAudioFormat)
            ?? defaults.segmentKeepsAudioFormat
        segmentCutsExactly = try container.decodeIfPresent(Bool.self, forKey: .segmentCutsExactly) ?? defaults.segmentCutsExactly
        crosshairMarks = try container.decodeIfPresent(Bool.self, forKey: .crosshairMarks) ?? defaults.crosshairMarks
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? defaults.reduceMotion
        coverBackdrop = try container.decodeIfPresent(Bool.self, forKey: .coverBackdrop) ?? defaults.coverBackdrop
        frostedGlass = try container.decodeIfPresent(Bool.self, forKey: .frostedGlass) ?? defaults.frostedGlass
        translucentPhotoViewer = try container.decodeIfPresent(Bool.self, forKey: .translucentPhotoViewer)
            ?? defaults.translucentPhotoViewer
        filmstripReveal = (try? container.decodeIfPresent(FilmstripReveal.self, forKey: .filmstripReveal)) ?? defaults.filmstripReveal
        swipeAnimation = try container.decodeIfPresent(Bool.self, forKey: .swipeAnimation) ?? defaults.swipeAnimation
        animatesGrid = try container.decodeIfPresent(Bool.self, forKey: .animatesGrid) ?? defaults.animatesGrid
        foldsSequences = try container.decodeIfPresent(Bool.self, forKey: .foldsSequences) ?? defaults.foldsSequences
        kindFilterStyle = (try? container.decodeIfPresent(KindFilterStyle.self, forKey: .kindFilterStyle)) ?? defaults.kindFilterStyle
        waveformStyle = (try? container.decodeIfPresent(WaveformStyle.self, forKey: .waveformStyle)) ?? defaults.waveformStyle
        videoWaveformStyle = (try? container.decodeIfPresent(WaveformStyle.self, forKey: .videoWaveformStyle))
            ?? defaults.videoWaveformStyle
        showsStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showsStatusBar) ?? defaults.showsStatusBar
        minFileKilobytes = try container.decodeIfPresent(Int.self, forKey: .minFileKilobytes) ?? defaults.minFileKilobytes
        quickPreviewOnTop = try container.decodeIfPresent(Bool.self, forKey: .quickPreviewOnTop) ?? defaults.quickPreviewOnTop
        previewDetails = try container.decodeIfPresent(Bool.self, forKey: .previewDetails) ?? defaults.previewDetails
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? defaults.checksForUpdates
        lastUpdateCheck = try? container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        skippedVersion = try? container.decodeIfPresent(String.self, forKey: .skippedVersion)
    }
}
