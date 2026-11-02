import AppKit
import JGDesign
import JGSettings
import JGThumbs
import Observation
import SwiftUI

/// The app's settings (docs/FEATURES.md §14), saved in user defaults (not in benchmark runs) and applied as they
/// change: theme, language (after a relaunch), thumbnail cache cap. Views read them from the environment.
@MainActor
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    @ObservationIgnored private let isPersistent: Bool
    @ObservationIgnored var thumbnailCache: ThumbnailDiskCache?
    /// Called after every change (the app model pushes settings into its parts).
    @ObservationIgnored var onChange: ((AppSettings) -> Void)?
    private static let key = "AppSettings"

    init(isPersistent: Bool) {
        self.isPersistent = isPersistent
        var loaded = (isPersistent ? UserDefaults.standard.data(forKey: Self.key) : nil)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        if !isPersistent {
            // Benchmark and check runs never stop at the first-launch cards.
            loaded.hasChosenAppearance = true
        }
        settings = loaded
        // Before the first view draws.
        Self.configureTokens(for: loaded)
    }

    private static func configureTokens(for settings: AppSettings) {
        JGTheme.set(isBlack: settings.theme == .black, accent: JGAccent.parse(settings.accentColor))
    }

    func update(_ change: (inout AppSettings) -> Void) {
        let old = settings
        change(&settings)
        guard settings != old else { return }
        if isPersistent, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        if settings.theme != old.theme || settings.accentColor != old.accentColor {
            applyTheme()
        }
        if settings.language != old.language {
            applyLanguage()
        }
        if settings.thumbnailCacheGigabytes != old.thumbnailCacheGigabytes {
            applyCacheLimit()
        }
        onChange?(settings)
    }

    /// Applies everything once at launch.
    func applyAll() {
        applyTheme()
        applyCacheLimit()
    }

    func applyTheme() {
        let changed = JGTheme.set(isBlack: settings.theme == .black, accent: JGAccent.parse(settings.accentColor))
        NSApp.appearance = switch settings.theme {
        case .system: nil
        case .dark, .black: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
        if changed {
            // The appearance alone says nothing about Black or the accent: AppKit-drawn views take their colors again.
            for window in NSApp.windows {
                window.contentView.map(Self.refreshColors)
            }
        }
    }

    private static func refreshColors(in view: NSView) {
        view.viewDidChangeEffectiveAppearance()
        view.needsDisplay = true
        view.subviews.forEach(refreshColors)
    }

    /// Takes effect at the next launch (macOS reads the app's languages when it starts).
    private func applyLanguage() {
        guard isPersistent else { return }
        switch settings.language {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .russian: UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        }
    }

    private func applyCacheLimit() {
        let bytes = Int64(settings.thumbnailCacheGigabytes) * 1024 * 1024 * 1024
        guard let cache = thumbnailCache else { return }
        Task { try? await cache.setLimit(bytes: bytes) }
    }
}

extension EnvironmentValues {
    /// The settings that views follow (Appearance, Decor).
    @Entry var appSettings = AppSettings()

    /// The store itself, for the few views that change a setting in place (the preview pane's details button).
    @Entry var settingsStore: SettingsStore?

    /// Settings → Reduce motion, on top of the system setting.
    @Entry var reduceMotionOverride: Bool = false
}

extension View {
    /// The settings that views read from the environment; they follow every change, also in AppKit-hosted roots.
    func appSettings(_ store: SettingsStore) -> some View {
        modifier(AppSettingsEnvironment(store: store))
    }
}

/// Reads the store inside a view body, so the environment is updated when a setting changes.
private struct AppSettingsEnvironment: ViewModifier {
    let store: SettingsStore

    func body(content: Content) -> some View {
        content
            .environment(\.appSettings, store.settings)
            .environment(\.settingsStore, store)
            .environment(\.reduceMotionOverride, store.settings.reduceMotion)
            .environment(\.jgThemeRevision, JGTheme.current.revision)
    }
}
