import CoreGraphics
import JGThumbs

/// The thumbnail that stands in while the photo decodes (D-82).
extension PhotoViewerModel {
    /// The grid's cached thumbnail, shown (scaled up) until the screen-size decode arrives.
    func placeholder(for entry: Entry?) -> Picture? {
        guard let entry, let photo = photo(for: entry), let assetID = photo.assetID, let modifiedAt = photo.modifiedAt,
              let thumbnails
        else { return nil }
        for bucket in [ThumbnailBucket.large, .medium, .small] {
            let request = ThumbnailRequest(
                assetID: assetID, url: photo.url, kind: .photo, typeIdentifier: photo.typeIdentifier,
                modifiedAt: modifiedAt, duration: nil, bucket: bucket
            )
            if let cached = thumbnails.cachedThumbnail(for: request), let image = cached {
                return placeholderPicture(image)
            }
        }
        return nil
    }

    /// No thumbnail in memory (opened from Finder before the grid drew it): the cached one from disk, which arrives
    /// long before the screen-size decode (D-82). Never replaces a decoded picture.
    func loadPlaceholder(for entry: Entry) {
        guard let photo = photo(for: entry), let assetID = photo.assetID, let modifiedAt = photo.modifiedAt, let thumbnails
        else { return }
        let requests = [ThumbnailBucket.large, .medium, .small].map { bucket in
            ThumbnailRequest(
                assetID: assetID, url: photo.url, kind: .photo, typeIdentifier: photo.typeIdentifier,
                modifiedAt: modifiedAt, duration: nil, bucket: bucket
            )
        }
        Task { [weak self] in
            var found: CGImage?
            for request in requests where found == nil {
                found = await thumbnails.storedThumbnail(for: request)
            }
            guard let self, let image = found, picture == nil, entries.indices.contains(index), entries[index] == entry
            else { return }
            standIn(placeholderPicture(image))
        }
    }

    /// A thumbnail standing in for the photo: sized like a screen-size decode (same aspect), so it fills the view
    /// as the photo will instead of showing at its own small size.
    private func placeholderPicture(_ image: CGImage) -> Picture {
        let longest = CGFloat(max(image.width, image.height, 1))
        let scale = CGFloat(screenPixels) / longest
        return Picture(
            image: image, fullSize: CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale),
            isFullResolution: false, isPlaceholder: true
        )
    }
}
