import SwiftUI

/// A developer gallery of every token and component, dark and light side by side.
///
/// Strings here are token identifiers and type specimens, not product UI, so they are not localized.
public struct JGDesignGallery: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            JGTokenSheet()
                .environment(\.colorScheme, .dark)
            JGHairline(.vertical)
            JGTokenSheet()
                .environment(\.colorScheme, .light)
        }
    }
}

/// All tokens rendered in the environment's appearance.
struct JGTokenSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var increasedContrast: Bool {
        colorSchemeContrast == .increased
    }

    private static let specimen: AttributedString = (try? AttributedString(markdown: "One **glance**.")) ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JGSpacing.xl) {
                Text(verbatim: isDark ? "Dark" : "Light")
                    .jgTextStyle(.heading)
                    .foregroundStyle(JGColor.textPrimary)
                section("Controls") { controls }
                section("Surfaces") { surfaces }
                section("Type") { typeSpecimens }
                section("Color") { colors }
                section("Contrast") { contrast }
            }
            .padding(JGSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(JGColor.bgBase)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            JGSectionHeader(Text(verbatim: title))
            content()
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: JGSpacing.m) {
            HStack(spacing: JGSpacing.xs) {
                button("Add Folder", fill: JGColor.textPrimary, text: JGColor.bgBase, outline: nil)
                button("Reveal in Finder", fill: JGColor.bgPanel, text: JGColor.textPrimary, outline: JGColor.lineStrong)
                button("Move to Trash", fill: JGColor.bgPanel, text: JGColor.danger, outline: JGColor.lineStrong)
            }
            HStack(spacing: JGSpacing.xs) {
                chip("Photo", isOn: true)
                chip("Video", isOn: true)
                chip("Audio", isOn: false)
            }
            segmented(["Name", "Date", "Size", "Kind"], selected: 1)
            scrubbers
        }
    }

    /// The ruler (video) and waveform (audio) scrubbers on `bg.media`, a third of the way in.
    private var scrubbers: some View {
        VStack(spacing: JGSpacing.s) {
            JGScrubber(time: 100, duration: 300, accessibilityLabel: "Position") { _, _ in }
                .frame(height: JGMetrics.controlHeightCompact)
            JGScrubber(time: 100, duration: 300, waveform: Self.samplePeaks, accessibilityLabel: "Position") { _, _ in }
                .frame(height: JGMetrics.waveformHeight)
        }
        .padding(JGSpacing.s)
        .frame(maxWidth: JGMetrics.readableTextWidth)
        .background(JGColor.bgMedia, in: JGShape(.medium))
    }

    /// A made-up waveform: a tone whose loudness swells and fades.
    private static let samplePeaks: JGWaveformPeaks = {
        let amplitudes: [Float] = (0 ..< 512).map { index in
            let swell = 0.25 + 0.7 * abs(sin(Double(index) / 60))
            return Float(abs(sin(Double(index) / 3)) * swell)
        }
        return JGWaveformPeaks(lows: amplitudes.map { -$0 }, highs: amplitudes)
    }()

    private func button(_ title: String, fill: JGColorToken, text: JGColorToken, outline: JGColorToken?) -> some View {
        Text(verbatim: title)
            .jgTextStyle(.button)
            .foregroundStyle(text)
            .padding(.horizontal, JGSpacing.m)
            .frame(height: JGMetrics.controlHeight)
            .background(fill, in: JGShape(.medium))
            .overlay {
                if let outline {
                    JGShape(.medium).strokeBorder(outline, lineWidth: JGMetrics.outlineWidth)
                }
            }
    }

    private func chip(_ title: String, isOn: Bool) -> some View {
        Text(verbatim: title)
            .jgTextStyle(.label)
            .foregroundStyle(isOn ? JGColor.bgBase : JGColor.textTertiary)
            .padding(.horizontal, JGSpacing.s)
            .frame(height: JGMetrics.controlHeightCompact)
            .background(isOn ? JGColor.textPrimary : JGColor.bgRaised, in: JGShape(.small))
    }

    private func segmented(_ titles: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(verbatim: title)
                    .jgTextStyle(.button)
                    .foregroundStyle(index == selected ? JGColor.textPrimary : JGColor.textSecondary)
                    .padding(.horizontal, JGSpacing.s)
                    .frame(height: JGMetrics.controlHeightCompact - JGSpacing.xxs)
                    .background(index == selected ? JGColor.bgPanel : JGColor.bgRaised, in: JGShape(.small))
            }
        }
        .padding(JGSpacing.xxs / 2)
        .background(JGColor.bgRaised, in: JGShape(.medium))
        .fixedSize()
    }

    // MARK: Surfaces

    private var surfaces: some View {
        HStack(alignment: .top, spacing: JGSpacing.m) {
            panel(JGColor.bgPanel, "bg.panel")
            panel(JGColor.bgRaised, "bg.raised")
            panel(JGColor.bgMedia, "bg.media")
            selectedTile
        }
    }

    private func panel(_ fill: JGColorToken, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.xxs) {
            Text(verbatim: "IMG_0042.HEIC").jgTextStyle(.body).foregroundStyle(JGColor.textPrimary)
            Text(verbatim: "Secondary").jgTextStyle(.body).foregroundStyle(JGColor.textSecondary)
            Text(verbatim: "4.2 MB · 4032×3024").jgTextStyle(.mono).foregroundStyle(JGColor.textTertiary)
            Text(verbatim: name).jgTextStyle(.label).foregroundStyle(JGColor.textTertiary)
        }
        .padding(JGSpacing.s)
        .background(fill, in: JGShape(.large))
        .overlay(JGShape(.large).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
    }

    private var selectedTile: some View {
        JGShape(.small)
            .fill(JGColor.accentDim)
            .overlay(JGShape(.small).strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth))
            .overlay(alignment: .topLeading) {
                Text(verbatim: "0:42")
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textPrimary)
                    .padding(JGSpacing.xs)
            }
            .frame(width: JGSpacing.xxl * 1.5, height: JGSpacing.xxl * 1.5)
    }

    // MARK: Type

    private var typeSpecimens: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: JGSpacing.m, verticalSpacing: JGSpacing.s) {
            ForEach(JGTextStyle.allCases, id: \.self) { style in
                GridRow {
                    Text(verbatim: "\(style) \(Int(style.size))")
                        .jgTextStyle(.mono)
                        .foregroundStyle(JGColor.textTertiary)
                    specimen(for: style)
                }
            }
        }
    }

    @ViewBuilder
    private func specimen(for style: JGTextStyle) -> some View {
        switch style {
        case .display, .heading:
            JGAccentText(attributed: Self.specimen)
                .jgTextStyle(style)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
        case .body:
            Text(verbatim: "Body text in SF Pro. Кириллица выглядит так же.")
                .jgTextStyle(style)
                .foregroundStyle(JGColor.textSecondary)
        case .button:
            Text(verbatim: "Open With… · Открыть с помощью")
                .jgTextStyle(style)
                .foregroundStyle(JGColor.textPrimary)
        case .label:
            Text(verbatim: "Folders · Папки")
                .jgTextStyle(style)
                .foregroundStyle(JGColor.textTertiary)
        case .mono:
            Text(verbatim: "1,248 items · 412 MB · 01:23:45")
                .jgTextStyle(style)
                .foregroundStyle(JGColor.textSecondary)
        }
    }

    // MARK: Color

    private var colors: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: JGMetrics.sidebarWidth * 0.75), spacing: JGSpacing.m, alignment: .leading)],
            alignment: .leading,
            spacing: JGSpacing.s
        ) {
            ForEach(JGColor.all, id: \.name) { token in
                HStack(spacing: JGSpacing.s) {
                    JGShape(.small)
                        .fill(token)
                        .overlay(JGShape(.small).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
                        .frame(width: JGSpacing.xl, height: JGSpacing.xl)
                    VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                        Text(verbatim: token.name)
                            .jgTextStyle(.button)
                            .foregroundStyle(JGColor.textPrimary)
                        Text(verbatim: token.value(isDark: isDark, increasedContrast: increasedContrast).hexString)
                            .jgTextStyle(.mono)
                            .foregroundStyle(JGColor.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Contrast

    private var contrast: some View {
        Grid(alignment: .leading, horizontalSpacing: JGSpacing.m, verticalSpacing: JGSpacing.xxs) {
            ForEach(Array(JGContrastRequirements.all.enumerated()), id: \.offset) { _, requirement in
                let enforced = !requirement.increasedContrastOnly || increasedContrast
                let ratio = requirement.ratio(isDark: isDark, increasedContrast: increasedContrast)
                let passes = ratio >= requirement.minimumRatio
                GridRow {
                    Text(verbatim: "\(requirement.foreground.name) / \(requirement.background.name)")
                    Text(verbatim: String(format: "%.2f", ratio))
                    Text(verbatim: enforced ? (passes ? "pass" : "fail") : "decor")
                        .foregroundStyle(enforced ? (passes ? JGColor.success : JGColor.danger) : JGColor.textTertiary)
                }
            }
        }
        .jgTextStyle(.mono)
        .foregroundStyle(JGColor.textSecondary)
    }
}

#Preview("Design gallery") {
    JGDesignGallery()
        .frame(width: JGMetrics.windowDefaultWidth, height: JGMetrics.windowDefaultHeight)
}
