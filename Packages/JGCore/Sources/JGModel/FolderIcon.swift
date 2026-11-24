import Foundation

/// A library folder's own icon (D-129), shown in the sidebar and its strip instead of the disk: an SF Symbol, an emoji,
/// or a small square picture made once from a photo (the photo itself is never changed nor needed later).
public enum FolderIcon: Hashable, Sendable {
    case symbol(String)
    case emoji(String)
    /// JPEG data, square, `FolderIcon.pictureSide` pixels.
    case picture(Data)

    /// The side of a picture icon in pixels: sharp at the sidebar's size on a Retina screen, small in the library.
    public static let pictureSide = 96
}
