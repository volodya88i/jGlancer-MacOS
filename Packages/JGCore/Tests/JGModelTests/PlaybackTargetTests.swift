import Foundation
import Testing
@testable import JGModel

struct PlaybackTargetTests {
    @Test func ratesFollowSemitonesAndTempo() {
        #expect(abs(PlaybackTarget.rate(semitones: 12) - 2) < 1e-9)
        #expect(abs(PlaybackTarget.rate(semitones: 2) - 1.122_462) < 1e-6)
        #expect(PlaybackTarget.rate(semitones: -30) == 0.5)
        #expect(abs(PlaybackTarget.rate(targetBPM: 132, songBPM: 120) - 1.1) < 1e-9)
        #expect(PlaybackTarget.rate(targetBPM: 500, songBPM: 120) == 2)
        #expect(abs(PlaybackTarget.semitones(rate: PlaybackTarget.rate(semitones: -3)) + 3) < 1e-9)
        #expect(PlaybackTarget.isWhole(2.01))
        #expect(!PlaybackTarget.isWhole(1.6))
    }

    @Test func typedValuesAreReadOrRefused() {
        #expect(PlaybackTarget.parseSemitones("5") == 5)
        #expect(PlaybackTarget.parseSemitones("+5") == 5)
        #expect(PlaybackTarget.parseSemitones("−3") == -3)
        #expect(PlaybackTarget.parseSemitones(" 1,5 ") == 1.5)
        #expect(PlaybackTarget.parseSemitones("40") == 12)
        #expect(PlaybackTarget.parseSemitones("abc") == nil)
        #expect(PlaybackTarget.parseSemitones("") == nil)
        #expect(PlaybackTarget.parseBPM("128") == 128)
        #expect(PlaybackTarget.parseBPM("-128") == nil)
        #expect(PlaybackTarget.parseBPM("0") == nil)
    }

    @Test func labelsAndKeys() {
        #expect(PlaybackTarget.label(2) == "+2")
        #expect(PlaybackTarget.label(-3) == "-3")
        #expect(PlaybackTarget.label(1.64) == "+1.6")
        #expect(PlaybackTarget.label(-0.01) == "0")
        #expect(MusicKey(tonic: 9, isMinor: true).label == "A min")
        #expect(MusicKey(tonic: 9, isMinor: true).shifted(by: 2).label == "B min")
        #expect(MusicKey(tonic: 3, isMinor: false).shifted(by: -15).label == "C maj")
        #expect(AudioAnalysis(bpm: 127.6, key: nil).bpmLabel == "128")
    }
}
