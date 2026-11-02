import Foundation
import JGModel

/// Saves and restores `LibraryViewState` in user defaults.
struct ViewStateStore {
    /// The main pane's state, and the split view's second pane (D-89).
    static let mainKey = "LibraryViewState"
    static let secondPaneKey = "LibraryViewState.secondPane"
    /// False for benchmark runs, so they do not overwrite the user's state.
    let isPersistent: Bool
    var key = Self.mainKey

    func load() -> LibraryViewState {
        guard isPersistent, let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(LibraryViewState.self, from: data)
        else { return LibraryViewState() }
        return state
    }

    func save(_ state: LibraryViewState) {
        guard isPersistent, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
