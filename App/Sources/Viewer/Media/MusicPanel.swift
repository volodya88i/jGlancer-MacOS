import JGDesign
import JGModel
import SwiftUI

/// The audio player's key and tempo button (D-106, W-107): `Key · BPM`, then the song as it sounds now
/// (`B min · 144 · +2`). A click opens the panel and analyzes a song not known yet.
struct MusicButton: View {
    let model: MediaViewerModel
    @State private var isOpen = false

    var body: some View {
        Button {
            model.analyze()
            isOpen.toggle()
        } label: {
            // As wide as a long label whatever it says, so the popover's arrow, at its middle, stays put (D-111).
            ZStack {
                Text(verbatim: Self.widestLabel).hidden()
                if let label = model.musicLabel {
                    Text(verbatim: label)
                } else {
                    Text("Key · BPM", comment: "Audio player: button for the song's key and tempo")
                }
            }
            .jgTextStyle(.mono)
            .foregroundStyle(model.tuning.isTargeted ? JGColor.accentText : JGColor.textSecondary)
            .padding(.horizontal, JGSpacing.xxs)
            .frame(height: JGMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(Text("Key and Tempo", comment: "Audio player: tooltip of the key and tempo button"))
        .accessibilityLabel(Text("Key and Tempo", comment: "Audio player: tooltip of the key and tempo button"))
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            MusicPanel(model: model)
        }
    }

    /// A key and tempo as long as they usually get.
    private static let widestLabel = "Eb min · 188"
}

/// The panel: BPM, Key, Target Pitch, Target Tempo. Its rows never change: while a song is analyzed its BPM and key
/// show moving bars, when nothing was found a dash, so the panel keeps its size. Every row is one control high.
/// Target pitch and tempo are one speed, as on a tape, for the current song only.
struct MusicPanel: View {
    let model: MediaViewerModel
    @State private var pitchText = ""
    @State private var tempoText = ""
    @FocusState private var focus: Field?

    private enum Field {
        case pitch
        case tempo
    }

    private var tuning: PlaybackTuning {
        model.tuning
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: JGSpacing.s, verticalSpacing: JGSpacing.xxs) {
            GridRow {
                label(Text("BPM", comment: "Key and tempo panel: the song's tempo"))
                value(model.analysis?.bpmLabel).gridCellColumns(2)
            }
            GridRow {
                label(Text("Key", comment: "Key and tempo panel: the song's key"))
                value(keyText).gridCellColumns(2)
            }
            GridRow {
                label(Text("Target Pitch", comment: "Key and tempo panel: the pitch to play the song at"))
                field($pitchText, .pitch, name: Text("Target Pitch in Semitones", comment: "Key and tempo panel field"))
                HStack(spacing: JGSpacing.xxs) {
                    step("−", Text("A Semitone Lower", comment: "Key and tempo panel button")) { model.stepPitch(by: -1) }
                        .disabled(tuning.heardSemitones <= -Double(PlaybackTarget.limit) + 0.5)
                    step("+", Text("A Semitone Higher", comment: "Key and tempo panel button")) { model.stepPitch(by: 1) }
                        .disabled(tuning.heardSemitones >= Double(PlaybackTarget.limit) - 0.5)
                }
                .gridColumnAlignment(.trailing)
            }
            GridRow {
                label(Text("Target Tempo", comment: "Key and tempo panel: the tempo to play the song at"))
                field($tempoText, .tempo, name: Text("Target Tempo in BPM", comment: "Key and tempo panel field"))
                    .disabled(model.analysis?.bpm == nil)
                // As wide as − and + together, so the column's edges line up.
                step(resetTitle, Text("Reset", comment: "Key and tempo panel: back to the saved speed"), width: resetWidth) {
                    tuning.clearTarget()
                }
                .disabled(!tuning.isTargeted)
            }
        }
        .padding(JGSpacing.s)
        // As large as its rows, no larger (D-111).
        .fixedSize()
        .onAppear(perform: refresh)
        .onChange(of: tuning.heardSemitones) { refresh() }
        .onChange(of: model.analysis) { refresh() }
        .onChange(of: focus) { old, _ in commit(old) }
    }

    private var resetTitle: String {
        String(localized: "Reset", comment: "Key and tempo panel: back to the saved speed")
    }

    private var resetWidth: CGFloat {
        2 * JGMetrics.musicStepWidth + JGSpacing.xxs
    }

    private var keyText: String? {
        guard let key = model.analysis?.key else { return nil }
        let heard = tuning.heardSemitones
        let asHeard = MediaViewerModel.keyAsHeard(key, heard: heard) ?? key.label
        return asHeard == key.label || !PlaybackTarget.isWhole(heard) ? asHeard : "\(key.label) → \(asHeard)"
    }

    private func label(_ text: Text) -> some View {
        text
            .jgTextStyle(.body)
            .foregroundStyle(JGColor.textSecondary)
            .frame(height: JGMetrics.controlHeightCompact)
    }

    /// A found value; moving bars while analyzing; a dash when nothing was found.
    private func value(_ text: String?) -> some View {
        Group {
            if model.isAnalyzing {
                JGWorkingBar().frame(width: JGMetrics.musicFieldWidth)
            } else if let text {
                Text(verbatim: text).foregroundStyle(JGColor.textPrimary)
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(JGColor.textTertiary)
                    .help(model.foundNothing
                        ? Text("Couldn't find the tempo or key of this file.", comment: "Key and tempo panel: nothing found")
                        : Text(verbatim: ""))
            }
        }
        .jgTextStyle(.body)
        .frame(height: JGMetrics.controlHeightCompact)
    }

    private func field(_ text: Binding<String>, _ field: Field, name: Text) -> some View {
        TextField(text: text, prompt: nil) { name }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .jgTextStyle(.body)
            .frame(width: JGMetrics.musicFieldWidth)
            .focused($focus, equals: field)
            .onSubmit { commit(field) }
            .help(name)
            .accessibilityLabel(name)
    }

    private func step(_ title: String, _ name: Text, width: CGFloat = JGMetrics.musicStepWidth, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .frame(width: width, height: JGMetrics.controlHeightCompact)
                .contentShape(JGShape(.small))
        }
        .buttonStyle(MusicStepStyle())
        .help(name)
        .accessibilityLabel(name)
    }

    /// The fields show what sounds now, except while one is being typed in.
    private func refresh() {
        if focus != .pitch {
            pitchText = PlaybackTarget.label(tuning.heardSemitones)
        }
        if focus != .tempo {
            tempoText = model.heardBPM.map { String(Int($0.rounded())) } ?? ""
        }
    }

    /// Goes to the typed pitch or tempo; anything unreadable goes back. Text left as it was changes nothing.
    private func commit(_ field: Field?) {
        switch field {
        case .pitch:
            if pitchText != PlaybackTarget.label(tuning.heardSemitones), let semitones = PlaybackTarget.parseSemitones(pitchText) {
                model.setTargetPitch(semitones)
            }
        case .tempo:
            let now = model.heardBPM.map { String(Int($0.rounded())) }
            if tempoText != now, let bpm = PlaybackTarget.parseBPM(tempoText) {
                model.setTargetTempo(bpm)
            }
        case nil:
            break
        }
        focus = nil
        refresh()
    }
}

/// The panel's small outlined buttons, one compact control high.
private struct MusicStepStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .jgTextStyle(.body)
            .foregroundStyle(isEnabled ? JGColor.textPrimary : JGColor.textTertiary)
            .background(JGColor.bgRaised, in: JGShape(.small))
            .overlay { JGShape(.small).strokeBorder(JGColor.lineStrong, lineWidth: JGMetrics.outlineWidth) }
            .opacity(configuration.isPressed ? JGMetrics.pressedOpacity : 1)
    }
}

/// A thin accent bar sweeping across, for work of unknown length; still with Reduce Motion.
struct JGWorkingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(JGColor.lineHair)
                Capsule()
                    .fill(JGColor.accent)
                    .frame(width: width / 3)
                    .offset(x: reduceMotion ? width / 3 : (phase ? width : -width / 3))
            }
            .clipShape(Capsule())
        }
        .frame(height: JGMetrics.selectionEdgeWidth)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { phase = true }
        }
        .accessibilityLabel(Text("Analyzing…", comment: "Key and tempo panel: the song is being analyzed"))
    }
}
