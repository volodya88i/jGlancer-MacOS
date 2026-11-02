import JGDesign
import JGSettings
import SwiftUI

/// Settings → General: the app's language and the default viewer.
struct GeneralSettings: View {
    let store: SettingsStore
    let updates: UpdateService

    var body: some View {
        SettingsGroup(title: Text("Language", comment: "Settings group; shown in capitals")) {
            JGSegmented(
                selection: Binding(get: { store.settings.language }, set: { language in store.update { $0.language = language } }),
                options: [
                    (.system, Text("System", comment: "Settings: follow the system")),
                    (.english, Text(verbatim: "English")),
                    (.russian, Text(verbatim: "Русский")),
                ]
            )
            Text("Applies the next time jGlancer opens.", comment: "Settings: language change note")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
        }
        UpdateSettings(updates: updates, store: store)
        DefaultViewerSettings()
    }
}
