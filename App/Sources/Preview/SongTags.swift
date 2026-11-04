import AVFoundation
import JGPlayback

/// Title, artist and album of songs, shared by the preview pane and Quick Preview (D-110): read once per file, so a
/// song shown again has its tags at once instead of after its player loads.
@MainActor
final class SongTags {
    static let shared = SongTags()
    private var tags: [URL: MediaInfo] = [:]
    /// Files remembered at most; the oldest are dropped past it.
    private static let capacity = 500
    private var order: [URL] = []

    /// The tags read earlier, or nil.
    func cached(_ url: URL) -> MediaInfo? {
        tags[url]
    }

    /// The tags of `url`, read now if they are not known yet.
    func load(_ url: URL) async -> MediaInfo? {
        if let known = tags[url] {
            return known
        }
        guard let info = try? await MediaInfo.load(AVURLAsset(url: url)) else { return nil }
        remember(info, for: url)
        return info
    }

    private func remember(_ info: MediaInfo, for url: URL) {
        if tags[url] == nil {
            order.append(url)
        }
        tags[url] = info
        if order.count > Self.capacity {
            tags[order.removeFirst()] = nil
        }
    }
}
