import CoreGraphics
import JGThumbs

/// The thumbnail that stands in while the photo decodes (D-82).
extension PhotoViewerModel {
    /// How long a photo that is not decoded yet shows nothing before the grid's thumbnail stands in (WIN-061): most
    /// decode sooner, so they open sharp instead of turning sharp in front of the user.
    static let standInDelay: Duration = .milliseconds(150)

    /// The stand-in for `entry`, after `standInDelay`, if its decode has not arrived by then.
    func scheduleStandIn(for entry: Entry?) {
        standInTask?.cancel()
        guard let entry else { return }
        standInTask = Task { [weak self] in
            try? await Task.sleep(for: Self.standInDelay)
            guard let self, !Task.isCancelled, picture == nil, entries.indices.contains(index), entries[index] == entry else {
                return
            }
            if let ready = placeholder(for: entry) {
                standIn(ready)
            } else {
                loadPlaceholder(for: entry)
            }
        }
    }

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
                return placeholderPicture(image, of: photo)
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
            standIn(placeholderPicture(image, of: photo))
        }
    }

    /// A thumbnail standing in for the photo: at the photo's own size when the library knows it, so it shows as the
    /// photo will (a small photo is not first stretched to the window, D-113); else sized like a screen-size decode.
    private func placeholderPicture(_ image: CGImage, of photo: ViewerPhoto) -> Picture {
        if let size = photo.pixelSize, size.width > 0, size.height > 0 {
            return Picture(image: image, fullSize: size, isFullResolution: false, isPlaceholder: true)
        }
        let longest = CGFloat(max(image.width, image.height, 1))
        let scale = CGFloat(screenPixels) / longest
        return Picture(
            image: image, fullSize: CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale),
            isFullResolution: false, isPlaceholder: true
        )
    }
}
