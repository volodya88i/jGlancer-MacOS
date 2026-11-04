import Foundation
import JGModel
import Testing
@testable import JGPlayback

struct AudioAnalysisTests {
    private static let rate = AudioAnalyzer.sampleRate

    /// Short 1 kHz clicks every `60 / bpm` seconds.
    private static func clicks(bpm: Double, seconds: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        let period = 60 / bpm * rate
        var beat = 0.0
        while Int(beat) + 400 < samples.count {
            for index in 0 ..< 400 {
                let time = Double(index) / rate
                samples[Int(beat) + index] += Float(sin(2 * .pi * 1000 * time) * exp(-time * 60) * 0.8)
            }
            beat += period
        }
        return samples
    }

    /// A minor: the tonic triad most of the time, then D minor and E major, as notes with a few harmonics.
    private static func song(transposedBy semitones: Int) -> [Float] {
        let chords: [[Int]] = [[57, 60, 64], [57, 60, 64], [62, 65, 69], [57, 60, 64], [64, 68, 71], [57, 60, 64]]
        var samples: [Float] = []
        for chord in chords {
            let length = Int(2 * rate)
            var block = [Float](repeating: 0, count: length)
            for note in chord + [chord[0] - 12] {
                let hertz = 440 * pow(2, Double(note + semitones - 69) / 12)
                for harmonic in 1 ... 3 {
                    for index in 0 ..< length {
                        let phase = 2 * Double.pi * hertz * Double(harmonic) * Double(index) / rate
                        block[index] += Float(sin(phase) * 0.08 / Double(harmonic))
                    }
                }
            }
            samples += block
        }
        return samples
    }

    @Test func tempoOfASteadyBeat() throws {
        for bpm in [90.0, 120.0, 128.0, 174.0] {
            let found = try #require(TempoDetector.detect(Self.clicks(bpm: bpm, seconds: 30), sampleRate: Self.rate))
            // Half or double may be found for fast tempos; the beat itself must be right.
            let ratio = found / bpm
            let nearest = [0.5, 1, 2].min { abs(ratio - $0) < abs(ratio - $1) } ?? 1
            #expect(abs(found - bpm * nearest) < 1, "\(bpm) BPM found as \(found)")
        }
    }

    @Test func keyFollowsATransposition() throws {
        let own = try #require(KeyDetector.detect(Self.song(transposedBy: 0), sampleRate: Self.rate))
        #expect(own == MusicKey(tonic: 9, isMinor: true), "found \(own.label)")
        for shift in [2, -3, 5] {
            let moved = try #require(KeyDetector.detect(Self.song(transposedBy: shift), sampleRate: Self.rate))
            #expect(moved == own.shifted(by: shift), "\(shift): found \(moved.label)")
        }
    }

    @Test func silenceHasNoTempoOrKey() {
        let silence = [Float](repeating: 0, count: Int(20 * Self.rate))
        #expect(KeyDetector.detect(silence, sampleRate: Self.rate) == nil)
        #expect(TempoDetector.detect([Float](repeating: 0, count: 100), sampleRate: Self.rate) == nil)
    }
}
