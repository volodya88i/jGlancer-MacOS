import SwiftUI
import UniformTypeIdentifiers

/// Files dropped from Finder on a viewer open like files opened from Finder (W-89): a library file with its folder,
/// another file with its folder's files of its kind; several dropped, the first opens. A folder joins the library.
/// The app's own tiles dragged out and back are ignored.
struct ViewerFileDrop: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !InternalDrag.isActive else { return false }
            Task {
                let urls = await FolderPicker.urls(from: providers)
                if !urls.isEmpty {
                    await appModel.open(urls)
                }
            }
            return true
        }
    }
}
