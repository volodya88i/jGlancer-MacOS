import AppKit
import JGDesign
import JGModel

/// One row of the list (D-125), an object as `NSOutlineView` wants it; equal rows are equal items, so expansion and
/// selection survive a reload.
final class ListItem: NSObject {
    let row: ListOutline.Row

    init(_ row: ListOutline.Row) {
        self.row = row
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ListItem)?.row == row
    }

    override var hash: Int {
        row.hashValue
    }

    var assetID: Int64? {
        if case let .asset(id) = row {
            id
        } else {
            nil
        }
    }

    var folderID: Int64? {
        if case let .folder(id) = row {
            id
        } else {
            nil
        }
    }
}

/// The list's columns.
enum ListColumn: String, CaseIterable {
    case name, date, size, kind

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("list." + rawValue)
    }

    /// The query's sort for a click on the column's header.
    var sort: AssetQuery.Sort {
        switch self {
        case .name: .name
        case .date: .dateModified
        case .size: .size
        case .kind: .kind
        }
    }

    init?(sort: AssetQuery.Sort) {
        guard let column = Self.allCases.first(where: { $0.sort == sort }) else { return nil }
        self = column
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name", comment: "Sort key")
        case .date: String(localized: "Date Modified", comment: "Sort key")
        case .size: String(localized: "Size", comment: "Sort key")
        case .kind: String(localized: "Kind", comment: "Sort key")
        }
    }
}

/// The name column: a small thumbnail (or a glyph), the name, and the flag star (D-125).
final class ListNameCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("list.nameCell")

    let thumbnail = CALayer()
    let label = NSTextField(labelWithString: "")
    let star = NSImageView()
    /// The asset shown, to match late thumbnails; nil for a folder.
    var assetID: Int64?
    var thumbnailTask: Task<Void, Never>?
    private var image: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        thumbnail.contentsGravity = .resizeAspect
        thumbnail.actions = ThumbnailTileView.quietActions
        layer?.addSublayer(thumbnail)
        label.font = NSFont.systemFont(ofSize: JGTextStyle.body.size)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.drawsBackground = false
        label.isBordered = false
        label.focusRingType = .none
        textField = label
        addSubview(label)
        addSubview(star)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        assetID = nil
        setImage(nil, glyph: nil)
        star.image = nil
    }

    /// The thumbnail, or a glyph (folder, kind, cloud) while there is none.
    func setImage(_ newImage: CGImage?, glyph: CGImage?) {
        image = newImage ?? glyph
        thumbnail.contents = image
        thumbnail.contentsGravity = newImage == nil ? .center : .resizeAspect
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset = JGMetrics.listThumbnailInset
        let side = max(bounds.height - 2 * inset, 0)
        thumbnail.contentsScale = window?.backingScaleFactor ?? 2
        thumbnail.frame = CGRect(x: 0, y: inset, width: side, height: side)
        let starSide = star.image == nil ? 0 : JGMetrics.flagStarSize + inset
        let labelX = side + 2 * inset
        let labelHeight = label.intrinsicContentSize.height
        label.frame = CGRect(
            x: labelX, y: (bounds.height - labelHeight) / 2, width: max(bounds.width - labelX - starSide, 0), height: labelHeight
        )
        star.frame = CGRect(x: bounds.width - starSide, y: (bounds.height - JGMetrics.flagStarSize) / 2,
                            width: JGMetrics.flagStarSize, height: JGMetrics.flagStarSize)
    }
}

/// The date, size and kind columns: one line of text.
final class ListTextCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("list.textCell")

    let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false
        label.isBordered = false
        textField = label
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    }
}

/// A row's selection: the accent's dim wash in a soft rectangle (the grid's selection fill, docs/DESIGN.md §3), the
/// same whether or not the list has the keyboard.
final class ListRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in _: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            JGColor.accentDim.nsColor.setFill()
            let rect = bounds.insetBy(dx: JGSpacing.xxs, dy: 0)
            NSBezierPath(roundedRect: rect, xRadius: JGMetrics.radiusSmall, yRadius: JGMetrics.radiusSmall).fill()
        }
    }
}
