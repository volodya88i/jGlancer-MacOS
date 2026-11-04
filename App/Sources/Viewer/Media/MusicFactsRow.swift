import JGDesign
import JGModel
import SwiftUI

extension EnvironmentValues {
    /// Tempo and key of songs, for the rows that show them (D-120).
    @Entry var audioAnalyses: AudioAnalyses?
}

extension Notification.Name {
    /// A song's tempo and key were found; the object is its file URL.
    static let audioAnalysisFound = Notification.Name("jGlancer.audioAnalysisFound")
}

/// Key and tempo of a song in one line (`A min · 128`) for Get Info and the preview pane (D-120): what the audio player
/// found before, or a quiet `detect` in mono that finds them on a click.
struct MusicFactsRow: View {
    let url: URL
    @Environment(\.audioAnalyses) private var analyses
    @State private var found: AudioAnalysis?
    @State private var state = Lookup.unknown

    private enum Lookup {
        case unknown, analyzing, nothing, known
    }

    var body: some View {
        Group {
            switch state {
            case .known:
                Text(verbatim: Self.label(found))
                    .foregroundStyle(JGColor.textPrimary)
                    .textSelection(.enabled)
            case .analyzing:
                Text(verbatim: "…").foregroundStyle(JGColor.textTertiary)
            case .nothing:
                Text(verbatim: "—")
                    .foregroundStyle(JGColor.textTertiary)
                    .help(Text("Couldn't find the tempo or key of this file.", comment: "Key and tempo panel: nothing found"))
            case .unknown:
                Button(action: detect) {
                    Text("detect", comment: "Get Info and preview: finds the song's key and tempo; shown in mono, lower case")
                        .foregroundStyle(JGColor.accentText)
                }
                .buttonStyle(.plain)
                .help(Text("Find the key and tempo", comment: "Tooltip of the detect button in Get Info and the preview"))
            }
        }
        .jgTextStyle(.mono)
        .task(id: url) { await loadKnown() }
        .onReceive(NotificationCenter.default.publisher(for: .audioAnalysisFound)) { note in
            if (note.object as? URL)?.standardizedFileURL == url.standardizedFileURL {
                Task { await loadKnown() }
            }
        }
    }

    /// `A min · 128`, whichever part is known.
    static func label(_ analysis: AudioAnalysis?) -> String {
        [analysis?.key?.label, analysis?.bpmLabel].compactMap(\.self).joined(separator: " · ")
    }

    private func loadKnown() async {
        let known = await analyses?.known(url)
        found = known
        state = known.map { $0.isEmpty ? .nothing : .known } ?? .unknown
    }

    private func detect() {
        guard let analyses else { return }
        state = .analyzing
        Task {
            let result = await analyses.analyze(url)
            found = result
            state = result == nil ? .nothing : .known
        }
    }
}
