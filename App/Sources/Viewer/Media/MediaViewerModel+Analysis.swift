import JGModel
import JGPlayback

/// Tempo, key and the target pitch or tempo of the audio player (D-106).
extension MediaViewerModel {
    /// Another song: a target belonged to the last one; what is known of the new one shows at once.
    func loadAnalysis(for item: PlaybackItem) async {
        analysisTask?.cancel()
        analysisTask = nil
        analysis = nil
        isAnalyzing = false
        foundNothing = false
        tuning.clearTarget()
        guard item.kind == .audio, let analyses else { return }
        let known = await analyses.known(item.url)
        guard !Task.isCancelled, current == item else { return }
        analysis = known
    }

    /// Analyzes the current song when nothing is known of it yet (the panel opened).
    func analyze() {
        guard analysis == nil, !isAnalyzing, !foundNothing, let item = current, item.kind == .audio, let analyses else { return }
        isAnalyzing = true
        analysisTask = Task { [weak self] in
            let found = await analyses.analyze(item.url)
            guard let self, !Task.isCancelled, current == item else { return }
            analysis = found
            foundNothing = found == nil
            isAnalyzing = false
        }
    }

    /// The tempo sounding now.
    var heardBPM: Double? {
        analysis?.bpm.map { $0 * Double(playback.rate) }
    }

    /// Goes to a pitch `semitones` from the song's own.
    func setTargetPitch(_ semitones: Double) {
        tuning.setTargetRate(PlaybackTarget.rate(semitones: semitones), for: kind)
    }

    /// Goes to a tempo; nothing without the song's own.
    func setTargetTempo(_ bpm: Double) {
        guard let own = analysis?.bpm else { return }
        tuning.setTargetRate(PlaybackTarget.rate(targetBPM: bpm, songBPM: own), for: kind)
    }

    /// A whole semitone up or down from the pitch sounding now, rounded.
    func stepPitch(by semitones: Int) {
        setTargetPitch(tuning.heardSemitones.rounded() + Double(semitones))
    }

    /// What the button says: `B min · 144`, as the song sounds now (the key names the shift; D-111); the shift itself
    /// (`+2`) only without a key; nil (`Key · BPM`) before anything is known.
    var musicLabel: String? {
        if isAnalyzing {
            return "…"
        }
        let heard = tuning.heardSemitones
        let pitch = abs(heard) < 0.02 ? nil : PlaybackTarget.label(heard)
        guard let analysis else { return pitch }
        let key = Self.keyAsHeard(analysis.key, heard: heard)
        let bpm = heardBPM.map { String(Int($0.rounded())) }
        let parts = [key, bpm, key == nil ? pitch : nil]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    /// The key sounding now: named when the pitch moved by whole semitones, else marked with the distance.
    static func keyAsHeard(_ key: MusicKey?, heard: Double) -> String? {
        guard let key else { return nil }
        return PlaybackTarget.isWhole(heard)
            ? key.shifted(by: Int(heard.rounded())).label
            : "\(key.label) \(PlaybackTarget.label(heard))"
    }
}
