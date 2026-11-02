import Foundation
import Testing
@testable import JGSettings

struct AppSettingsTests {
    @Test func presetsSetOnlyTheirOptions() {
        var settings = AppSettings()
        #expect(AppearancePreset.matching(settings) == .performance)
        settings.kindFilterStyle = .icons
        settings.crosshairMarks = true
        AppearancePreset.beauty.apply(to: &settings)
        #expect(settings.coverBackdrop && settings.swipeAnimation && settings.animatesGrid && settings.filmstripReveal == .automatic)
        // Options outside the presets stay as they were.
        #expect(settings.kindFilterStyle == .icons && settings.crosshairMarks)
        #expect(AppearancePreset.matching(settings) == .beauty)
        settings.swipeAnimation = false
        #expect(AppearancePreset.matching(settings) == nil)
        AppearancePreset.performance.apply(to: &settings)
        #expect(!settings.coverBackdrop && !settings.swipeAnimation && !settings.animatesGrid && settings.filmstripReveal == .button)
    }

    @Test func settingsDecodeMissingAndUnknownKeysToDefaults() throws {
        // A file from the Phase 10 build with modes: old keys are ignored, the look is asked again.
        let old = #"{"theme":"light","features":{"mode":"advanced","overrides":{}},"hasChosenMode":true,"filmstripReveal":"bogus"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.theme == .light)
        #expect(decoded.thumbnailCacheGigabytes == 2)
        #expect(!decoded.hasChosenAppearance)
        #expect(decoded.filmstripReveal == .button)
        var settings = AppSettings()
        AppearancePreset.beauty.apply(to: &settings)
        settings.kindFilterStyle = .icons
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
        #expect(AppSettings().theme == .dark)
    }

    @Test func theRemovedFullWaveformReadsAsNarrow() throws {
        let old = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"waveformStyle":"full","rulerTicks":false,"theme":"black"}"#.utf8)
        )
        #expect(old.waveformStyle == .narrow)
        #expect(old.theme == .black)
        #expect(old.accentColor == nil)
    }

    @Test func versionsParseStrictlyAndCompareByNumber() throws {
        #expect(AppVersion("v0.5.0")?.description == "0.5.0")
        for bad in ["", "1.2", "1.2.3.4", "1.2.x", "1..3", "../1.2.3", "1.2.3/../../x", "١.٢.٣", "1.2.3-beta"] {
            #expect(AppVersion(bad) == nil, Comment(rawValue: bad))
        }
        #expect(try #require(AppVersion("0.10.0")) > #require(AppVersion("0.9.9")))
    }

    @Test func theCheckRunsOnceADayAndSkipsWhatWasSkipped() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdatePolicy.isDue(lastCheck: nil, now: now))
        #expect(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-90000), now: now))
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
        let installed = try #require(AppVersion("0.5.0"))
        let newer = try #require(AppVersion("0.5.1"))
        #expect(UpdatePolicy.offer(latest: newer, installed: installed, skipped: nil, manual: false))
        #expect(!UpdatePolicy.offer(latest: installed, installed: installed, skipped: nil, manual: true))
        #expect(!UpdatePolicy.offer(latest: newer, installed: installed, skipped: "0.5.1", manual: false))
        #expect(UpdatePolicy.offer(latest: newer, installed: installed, skipped: "0.5.1", manual: true))
    }
}
