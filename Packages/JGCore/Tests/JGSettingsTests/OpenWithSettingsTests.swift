import Foundation
import JGModel
import Testing
@testable import JGSettings

struct OpenWithSettingsTests {
    let rxEditor = ExternalApp(bundleID: "com.izotope.rxEditor", path: "/Applications/RX.app", name: "RX Audio Editor")
    let audacity = ExternalApp(bundleID: "org.audacityteam.audacity", path: "/Applications/Audacity.app", name: "Audacity")

    @Test func firstAddedIsPrimaryAndListsPrimaryFirst() {
        var settings = OpenWithSettings()
        settings.add(rxEditor, for: .audio)
        settings.add(audacity, for: .audio)
        #expect(settings.primary(for: .audio) == rxEditor)
        settings.setPrimary(bundleID: audacity.bundleID, for: .audio)
        #expect(settings.apps(for: .audio) == [audacity, rxEditor])
        #expect(settings.kindsWithPrimary == [.audio])
        #expect(settings.apps(for: .photo).isEmpty)
    }

    @Test func removingThePrimaryPromotesTheNext() {
        var settings = OpenWithSettings()
        settings.add(rxEditor, for: .audio)
        settings.add(audacity, for: .audio)
        settings.remove(bundleID: rxEditor.bundleID, for: .audio)
        #expect(settings.primary(for: .audio) == audacity)
        settings.remove(bundleID: audacity.bundleID, for: .audio)
        #expect(settings.primary(for: .audio) == nil)
    }

    @Test func addingAgainUpdatesInPlaceAndUnknownPrimaryIsIgnored() {
        var settings = OpenWithSettings()
        settings.add(rxEditor, for: .audio)
        settings.add(audacity, for: .audio)
        let moved = ExternalApp(bundleID: rxEditor.bundleID, path: "/Applications/Audio/RX.app", name: "RX Audio Editor")
        settings.add(moved, for: .audio)
        #expect(settings.apps(for: .audio) == [moved, audacity])
        settings.setPrimary(bundleID: "com.example.missing", for: .audio)
        #expect(settings.primary(for: .audio) == moved)
    }

    @Test func survivesEncoding() throws {
        var settings = OpenWithSettings()
        settings.add(rxEditor, for: .audio)
        let decoded = try JSONDecoder().decode(OpenWithSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}
