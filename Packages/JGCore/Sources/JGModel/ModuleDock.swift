/// The library window's two places for side modules (D-127): right of the files, or under them.
public enum ModuleSlot: String, Codable, CaseIterable, Sendable {
    case right, bottom

    public var other: ModuleSlot {
        self == .right ? .bottom : .right
    }
}

/// The side modules: the selection's preview and the size map.
public enum LibraryModule: CaseIterable, Sendable {
    case preview, sizeMap
}

/// The rules of the two places (D-127): a module shown where the other one is takes the free place instead; moving a
/// module to the place of the other one swaps them.
public extension LibraryViewState {
    /// Where `module` is, nil while it is hidden.
    func slot(of module: LibraryModule) -> ModuleSlot? {
        switch module {
        case .preview: previewVisible ? previewSlot : nil
        case .sizeMap: sizeMapVisible ? sizeMapSlot : nil
        }
    }

    /// The module shown in `slot`, if any.
    func module(in slot: ModuleSlot) -> LibraryModule? {
        LibraryModule.allCases.first { self.slot(of: $0) == slot }
    }

    /// Shows or hides `module`; shown where the other one is, it takes the free place.
    mutating func setVisible(_ module: LibraryModule, _ isVisible: Bool) {
        switch module {
        case .preview:
            previewVisible = isVisible
            if isVisible, sizeMapVisible, sizeMapSlot == previewSlot {
                previewSlot = sizeMapSlot.other
            }
        case .sizeMap:
            sizeMapVisible = isVisible
            if isVisible, previewVisible, previewSlot == sizeMapSlot {
                sizeMapSlot = previewSlot.other
            }
        }
    }

    /// Moves `module` to the other place; the module there, if any, takes its place.
    mutating func move(_ module: LibraryModule) {
        switch module {
        case .preview:
            let target = previewSlot.other
            if sizeMapVisible, sizeMapSlot == target {
                sizeMapSlot = previewSlot
            }
            previewSlot = target
        case .sizeMap:
            let target = sizeMapSlot.other
            if previewVisible, previewSlot == target {
                previewSlot = sizeMapSlot
            }
            sizeMapSlot = target
        }
    }
}
