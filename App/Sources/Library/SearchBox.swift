import JGDesign
import SwiftUI

/// The top bar's search (docs/FEATURES.md §12): a magnifier that opens into a field (click or ⌘F). The field
/// searches file names in the folder or album shown; "Everywhere" widens it to the whole library. Esc clears it
/// and gives the keyboard back to the grid.
struct SearchBox: View {
    let model: LibraryModel
    @FocusState private var isFocused: Bool
    @State private var isOpen = false

    var body: some View {
        HStack(spacing: JGSpacing.xs) {
            if isOpen || model.isSearching {
                field
                Toggle(isOn: Binding(get: { model.searchEverywhere }, set: { model.setSearchEverywhere($0) })) {
                    Text("Everywhere", comment: "Search: the whole library instead of the folder shown")
                }
                .toggleStyle(.jgChip)
                .fixedSize()
                .help(Text("Search the whole library", comment: "Search scope tooltip"))
            } else {
                Button { open() } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: JGTextStyle.body.size, weight: .medium))
                        .foregroundStyle(JGColor.textSecondary)
                        .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Find", comment: "Menu: focuses the search field"))
                .accessibilityLabel(Text("Find", comment: "Menu: focuses the search field"))
            }
        }
        .onChange(of: model.searchFocusRequest) { open() }
    }

    private var field: some View {
        HStack(spacing: JGSpacing.xxs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
                .foregroundStyle(JGColor.textTertiary)
                .accessibilityHidden(true)
            TextField(
                text: Binding(get: { model.searchText }, set: { model.setSearch($0) }),
                prompt: Text("Search", comment: "Search field placeholder")
            ) {
                Text("Search", comment: "Search field placeholder")
            }
            .textFieldStyle(.plain)
            .jgTextStyle(.body)
            .focused($isFocused)
            .onExitCommand(perform: close)
            .onSubmit { model.focusGrid() }
            if model.isSearching {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: JGTextStyle.body.size))
                        .foregroundStyle(JGColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search", comment: "Search: clears the field"))
            }
        }
        .padding(.horizontal, JGSpacing.xs)
        .frame(minWidth: JGMetrics.searchFieldMinWidth, idealWidth: JGMetrics.searchFieldWidth, maxWidth: JGMetrics.searchFieldWidth)
        .frame(height: JGMetrics.controlHeightCompact)
        .background(JGColor.bgRaised, in: JGShape(.small))
        .onChange(of: isFocused) { _, focused in
            if !focused, !model.isSearching {
                isOpen = false
            }
        }
    }

    private func open() {
        isOpen = true
        Task { @MainActor in isFocused = true }
    }

    private func close() {
        isOpen = false
        isFocused = false
        model.endSearch()
    }
}
