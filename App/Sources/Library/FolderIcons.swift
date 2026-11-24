import AppKit
import ImageIO
import JGDesign
import JGModel
import JGThumbs
import SwiftUI
import UniformTypeIdentifiers

/// A library folder's own icon ready to draw (D-129): a picture is decoded once, off the main thread.
enum FolderIconImage {
    case symbol(String)
    case emoji(String)
    case picture(CGImage)
}

/// A sidebar icon in its box (`JGMetrics.sidebarIconBox`): the folder's own symbol, emoji or picture, else `fallback`.
struct FolderIconView: View {
    let icon: FolderIconImage?
    let fallback: String
    var isSelected = false
    var side = JGMetrics.sidebarIconBox

    var body: some View {
        Group {
            switch icon {
            case let .symbol(name):
                symbol(name)
            case let .emoji(text):
                Text(verbatim: text)
                    .font(.system(size: glyphSize + 1))
            case let .picture(image):
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(JGShape(.small))
            case nil:
                symbol(fallback)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The body size in the sidebar's box, larger in a larger one (the icon picker's header).
    private var glyphSize: CGFloat {
        JGTextStyle.body.size * side / JGMetrics.sidebarIconBox
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: glyphSize))
            .foregroundStyle(isSelected ? JGColor.textPrimary : JGColor.textSecondary)
    }
}

/// Square pictures for folder icons: the middle of a photo, `FolderIcon.pictureSide` pixels, as JPEG.
enum FolderIconPicture {
    /// From a picture already decoded (a library photo's thumbnail).
    nonisolated static func make(from image: CGImage) -> Data? {
        let side = min(image.width, image.height)
        let crop = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let square = image.cropping(to: crop) else { return nil }
        let target = FolderIcon.pictureSide
        guard let context = CGContext(
            data: nil, width: target, height: target, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: target, height: target))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// From an image file on disk, read downsampled (never decoded whole).
    nonisolated static func make(from url: URL) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: FolderIcon.pictureSide * 4,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return make(from: image)
    }

    nonisolated static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension LibraryModel {
    /// Keeps `rootIcons` in step with the library (D-129).
    func startRootIcons() {
        Task { [weak self] in
            guard let store = self?.store else { return }
            do {
                for try await icons in store.observeRootIcons() {
                    let images = await Task.detached(priority: .userInitiated) { Self.images(icons) }.value
                    self?.rootIcons = images
                }
            } catch {}
        }
    }

    private nonisolated static func images(_ icons: [Int64: FolderIcon]) -> [Int64: FolderIconImage] {
        icons.compactMapValues { icon in
            switch icon {
            case let .symbol(name): .symbol(name)
            case let .emoji(text): .emoji(text)
            case let .picture(data): FolderIconPicture.decode(data).map(FolderIconImage.picture)
            }
        }
    }

    func setRootIcon(_ icon: FolderIcon?, for rootID: Int64) {
        Task { try? await store.setRootIcon(icon, for: rootID) }
    }

    /// A picture file chosen on disk as the icon of `rootID`.
    func setRootIcon(fromFile url: URL, for rootID: Int64) {
        Task {
            guard let data = await Task.detached(priority: .userInitiated, operation: { FolderIconPicture.make(from: url) }).value else {
                NSSound.beep()
                return
            }
            try? await store.setRootIcon(.picture(data), for: rootID)
        }
    }

    /// A photo of the library as the icon of the library folder that holds it (Set as Folder Icon). Made from its
    /// thumbnail: a photo kept only in the cloud is not downloaded for this (D-124).
    func setFolderIcon(fromAsset assetID: Int64) async {
        guard let asset = try? await store.assets(ids: [assetID]).first, !asset.isCloudOnly,
              let root = roots.first(where: { asset.url.path.hasPrefix($0.path + "/") })
        else {
            NSSound.beep()
            return
        }
        let request = ThumbnailRequest(
            assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
            modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: .medium
        )
        guard let thumbnail = await thumbnails.thumbnail(for: request, priority: .visible),
              let data = await Task.detached(priority: .userInitiated, operation: { FolderIconPicture.make(from: thumbnail) }).value
        else {
            NSSound.beep()
            return
        }
        try? await store.setRootIcon(.picture(data), for: root.id)
    }
}
