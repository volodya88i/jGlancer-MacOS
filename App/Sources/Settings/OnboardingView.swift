import JGDesign
import JGSettings
import SwiftUI

/// First launch (docs/FEATURES.md §12, DESIGN §8): the two appearance presets as large cards, one word and one line
/// each; Skip keeps the defaults (Performance). Shown once; Settings → Appearance changes it any time.
struct OnboardingView: View {
    let store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.l) {
            Spacer()
            JGSectionHeader(Text("Choose a Look", comment: "First launch: section label; shown in capitals"))
            PresetCards(selected: nil, isLarge: true) { preset in
                choose(preset)
            }
            HStack {
                Text("You can change it any time.", comment: "First launch: under the mode cards")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
                Spacer()
                Button { choose(.performance) } label: {
                    Text("Skip", comment: "First launch: keep the default look")
                }
                .buttonStyle(.jg(.tertiary))
                .keyboardShortcut(.cancelAction)
            }
            Spacer()
        }
        .frame(maxWidth: JGMetrics.readableTextWidth * 2)
        .padding(JGSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JGColor.bgBase)
    }

    private func choose(_ preset: AppearancePreset) {
        store.update {
            preset.apply(to: &$0)
            $0.hasChosenAppearance = true
        }
    }
}
