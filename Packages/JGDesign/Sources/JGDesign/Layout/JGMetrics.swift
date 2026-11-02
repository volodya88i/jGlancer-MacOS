import CoreGraphics

/// Sizes, borders and shape (docs/DESIGN.md §5, §8).
public enum JGMetrics {
    /// Corner radii (continuous curves). Window corners are the system's.
    /// Small: thumbnails, chips, badges. Medium: buttons, fields, segmented controls, menus.
    /// Large: panels, floating windows, toasts.
    public static let radiusSmall: CGFloat = 6
    public static let radiusMedium: CGFloat = 8
    public static let radiusLarge: CGFloat = 12

    /// Compact control height.
    public static let controlHeightCompact: CGFloat = 28
    /// The key cap of a shortcut in Settings → Shortcuts.
    public static let shortcutCapWidth: CGFloat = 96
    /// Pause in typing before the search runs, and the width of the open search field.
    public static let searchDelayMilliseconds = 150
    public static let searchFieldWidth: CGFloat = 180
    public static let searchFieldMinWidth: CGFloat = 100
    /// The batch rename sheet and its list of names.
    public static let batchRenameWidth: CGFloat = 560
    public static let batchRenameListHeight: CGFloat = 220
    /// Default control height.
    public static let controlHeight: CGFloat = 32
    /// Top bar and section header rows.
    public static let barHeight: CGFloat = 44
    /// Status bar.
    public static let statusBarHeight: CGFloat = 24

    /// Library sidebar width.
    public static let sidebarWidth: CGFloat = 220
    /// The sidebar's width can be dragged within this range (D-78).
    public static let sidebarMinWidth: CGFloat = 180
    public static let sidebarMaxWidth: CGFloat = 440
    /// Preview pane width range.
    public static let previewPaneMinWidth: CGFloat = 320
    public static let previewPaneMaxWidth: CGFloat = 480
    /// The pane's mini player: waveform height and cover side.
    public static let miniWaveformHeight: CGFloat = 56
    public static let miniCoverSide: CGFloat = 160
    /// Grab area for resizing a pane by its edge.
    public static let resizeHandleWidth: CGFloat = 6
    /// The top bar's breadcrumb never gets narrower than this; the bar's controls give way first (D-89).
    public static let breadcrumbMinWidth: CGFloat = 140
    /// The track of a slider and a plain scrubber (W-98).
    public static let sliderThickness: CGFloat = 4
    /// The app's own switch and check box (macOS's take the system accent, not the app's; D-102).
    public static let switchWidth: CGFloat = 32
    public static let switchHeight: CGFloat = 18
    public static let switchKnobInset: CGFloat = 2
    public static let checkboxSide: CGFloat = 16
    /// A color in Settings → Appearance → Accent Color.
    public static let accentSwatchSide: CGFloat = 20
    /// Find Duplicates: the window's default size and a copy's thumbnail.
    public static let duplicatesWidth: CGFloat = 720
    public static let duplicatesHeight: CGFloat = 560
    public static let duplicateThumbnailSide: CGFloat = 44
    /// Toasts: the soft shadow of light mode and how long a finished toast stays.
    public static let toastShadowOpacity: Double = 0.12
    public static let toastShadowRadius: CGFloat = 12
    /// The window's mini player bar (D-88): its height and the width of its title column.
    public static let miniPlayerHeight: CGFloat = 56
    public static let miniPlayerTextWidth: CGFloat = 200
    public static let miniPlayerTextMinWidth: CGFloat = 110
    public static let miniPlayerScrubberMinWidth: CGFloat = 160
    /// The card listing folders being added (D-85).
    public static let addingCardWidth: CGFloat = 360
    public static let toastSeconds: Double = 6
    /// The Settings window.
    public static let settingsWidth: CGFloat = 760
    public static let settingsHeight: CGFloat = 540
    public static let settingsSidebarWidth: CGFloat = 180
    /// Column of the preset names in the appearance cards (Settings, first launch).
    public static let presetNameWidth: CGFloat = 240
    public static let presetNameWidthLarge: CGFloat = 440
    /// Quick Preview's first size (then remembered).
    public static let quickPreviewWidth: CGFloat = 720
    public static let quickPreviewHeight: CGFloat = 540
    /// Maximum width of running body text.
    public static let readableTextWidth: CGFloat = 560

    /// Main window size limits and default.
    public static let windowMinWidth: CGFloat = 960
    public static let windowMinHeight: CGFloat = 600
    public static let windowDefaultWidth: CGFloat = 1280
    public static let windowDefaultHeight: CGFloat = 800

    /// Strong outline (secondary buttons, hover) width.
    public static let outlineWidth: CGFloat = 1
    /// Selection edge width (inset).
    public static let selectionEdgeWidth: CGFloat = 2
    /// Side of a decorative "+" crosshair mark.
    public static let crosshairSize: CGFloat = 8
    /// SF Symbol size in chrome.
    public static let iconSize: CGFloat = 16

    /// Library grid: gutter between tiles, outer padding, tile side range and step, caption band.
    public static let gridGutter: CGFloat = 8
    public static let gridInset: CGFloat = 16
    public static let tileSideRange: ClosedRange<Double> = 80 ... 320
    public static let tileSideStep: Double = 20
    public static let tileSideDefault: Double = 160
    /// Height reserved under a tile for its name.
    public static let tileCaptionHeight: CGFloat = 22
    /// Below this tile side names are hidden (too narrow to read).
    public static let tileCaptionMinimumSide: CGFloat = 96
    /// Inset of badges inside a tile.
    public static let badgeInset: CGFloat = 4
    /// The flag star of a tile and the square badge around it.
    public static let flagStarSize: CGFloat = 11
    public static let flagBadgeSide: CGFloat = 20
    /// Point size of kind glyphs on tiles without a thumbnail.
    public static let tileGlyphSize: CGFloat = 28

    /// Room for the window's close / minimize / zoom buttons at the top-left of full-window views.
    public static let windowControlsInset: CGFloat = 80
    /// Seconds without pointer movement before the viewer's HUD fades.
    public static let hudIdleSeconds: Double = 2.5
    /// Fade duration of overlays (docs/DESIGN.md §9).
    public static let fadeDuration: Double = 0.18

    /// Height of the audio player's waveform scrubber.
    public static let waveformHeight: CGFloat = 96
    /// The unplayed part of a waveform: `text.primary` at this opacity (D-79).
    public static let waveformUnplayedOpacity: Double = 0.35
    /// Segment brackets on the scrubber (D-73): the horizontal ends of `[` `]`, the tint between, and how near an
    /// end a click has to be to drag it.
    public static let segmentBracketSerif: CGFloat = 6
    public static let segmentTintOpacity: Double = 0.16
    public static let segmentEdgeReach: CGFloat = 6
    /// How much the timeline outside a segment is dimmed (background color over it at this opacity).
    public static let segmentOutsideOpacity: Double = 0.65
    /// Zooming and scrolling a scrubber: points per wheel line, and zoom per point scrolled (e^(points × this)).
    public static let wheelLinePoints: CGFloat = 10
    public static let zoomPerPoint: Double = 0.01
    /// Width of the players' volume ruler.
    public static let volumeSliderWidth: CGFloat = 80
    /// Longest side of the audio player's cover art.
    public static let coverArtSide: CGFloat = 280
    /// Picture area of a filmstrip tile (16:9).
    public static let filmstripTileWidth: CGFloat = 90
    public static let filmstripTileHeight: CGFloat = 50
    /// The whole strip: tile, name line and padding.
    public static let filmstripHeight: CGFloat = 84
    /// Automatic filmstrip: how far above the strip the pointer already brings it, and how long it stays after the
    /// pointer moves up.
    public static let filmstripRevealMargin: CGFloat = 24
    public static let filmstripHideDelay: Double = 0.5
    /// How long a released swipe takes to finish its page or spring back.
    public static let swipeSettleDuration: Double = 0.25
    /// The chevron that hides and shows the filmstrip.
    public static let filmstripToggleWidth: CGFloat = 36
    public static let filmstripToggleHeight: CGFloat = 16
    /// The photo viewer's round ‹ › buttons.
    public static let pageButtonSide: CGFloat = 44
    /// The viewers' glass panels: strength of the frosted material (below 1 softens the blur) and of the scrim
    /// tint over it (between the old filmstrip, 0.35, and the solid controls scrim, 1).
    public static let glassBlurOpacity: Double = 0.6
    public static let glassTintOpacity: Double = 0.65
    /// The filmstrip's lighter scrim (D-78, Windows `FilmstripScrimOpacity`).
    public static let filmstripScrimOpacity: Double = 0.5
    /// The badge behind a tile's flag star: `bg.base` at this opacity, so every flag color (and the accent) keeps
    /// ≥ 3:1 over any thumbnail.
    public static let flagBadgeOpacity: Double = 0.85
    /// Strength of the `bg.base` wash over the blurred cover behind audio files.
    public static let backdropScrimOpacity: Double = 0.78
    /// The blurred backdrop cross-fades from one cover to the next over this many seconds (D-79).
    public static let backdropCrossfade: Double = 0.8
    /// Readable width of the audio player's waveform and controls.
    public static let playerMaxWidth: CGFloat = 880

    /// Opacity of a placeholder tile (a file that vanished, kept in its albums).
    public static let placeholderOpacity: CGFloat = 0.35

    /// Opacity of a pressed control.
    public static let pressedOpacity: Double = 0.75
    /// Opacity of the marquee fill (`accent.dim`).
    public static let marqueeFillOpacity: Double = 0.5

    /// A hairline is one device pixel: `1 / displayScale` points.
    public static func hairline(displayScale: CGFloat) -> CGFloat {
        1 / max(displayScale, 1)
    }
}
