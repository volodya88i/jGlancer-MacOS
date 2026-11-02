import AppKit
import JGDesign
import JGModel

/// Collection-view layout backed by `GridGeometry`: O(visible) work per query, so 100k items lay out instantly.
final class GridLayout: NSCollectionViewLayout {
    var targetTileSide: CGFloat = JGMetrics.tileSideDefault {
        didSet {
            if oldValue != targetTileSide {
                invalidateLayout()
            }
        }
    }

    /// Set while the tile size is being changed (D-93): tiles are the target size times this (so the drag starts
    /// from the size shown), not stretched, rows centered. Nil: tiles fill the rows.
    var liveScale: CGFloat? {
        didSet {
            if oldValue != liveScale {
                invalidateLayout()
            }
        }
    }

    var showsCaptions = true {
        didSet {
            if oldValue != showsCaptions {
                invalidateLayout()
            }
        }
    }

    private(set) var geometry = GridGeometry(
        itemCount: 0, width: 0, targetTileSide: JGMetrics.tileSideDefault,
        gutter: JGMetrics.gridGutter, inset: JGMetrics.gridInset, captionHeight: 0
    )

    /// Whether names fit under the current tiles.
    var captionsVisible: Bool {
        showsCaptions && targetTileSide >= JGMetrics.tileCaptionMinimumSide
    }

    override func prepare() {
        super.prepare()
        geometry = currentGeometry()
    }

    /// Geometry for the collection view's current width and item count (valid even before the next layout pass).
    func currentGeometry() -> GridGeometry {
        guard let collectionView else { return geometry }
        let width = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
        return GridGeometry(
            itemCount: collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0,
            width: width,
            targetTileSide: targetTileSide * (liveScale ?? 1),
            gutter: JGMetrics.gridGutter,
            inset: JGMetrics.gridInset,
            captionHeight: captionsVisible ? JGMetrics.tileCaptionHeight : 0,
            fillsRow: liveScale == nil
        )
    }

    override var collectionViewContentSize: NSSize {
        let visibleHeight = collectionView?.enclosingScrollView?.contentSize.height ?? 0
        return NSSize(width: geometry.width, height: max(geometry.contentHeight, visibleHeight))
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        geometry.indices(in: rect).map(attributes(at:))
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        indexPath.item < geometry.itemCount ? attributes(at: indexPath.item) : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != geometry.width
    }

    private func attributes(at index: Int) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attributes.frame = geometry.frame(at: index)
        return attributes
    }
}
