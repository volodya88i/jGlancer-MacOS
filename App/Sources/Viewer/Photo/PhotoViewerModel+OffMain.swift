import CoreGraphics

/// Work done off the main actor.
extension PhotoViewerModel {
    /// `image` turned clockwise by `quarterTurns` × 90°.
    nonisolated static func rotated(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let odd = !quarterTurns.isMultiple(of: 2)
        let width = odd ? image.height : image.width
        let height = odd ? image.width : image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    /// Runs `work` on the global pool; cancelling the caller cancels it, so a decode for a photo paged past while it
    /// waited for a thread never starts (holding → would otherwise queue a screen-size decode for every photo
    /// passed, each finishing for nothing).
    nonisolated static func offMain<Value: Sendable>(
        priority: TaskPriority, _ work: @escaping @Sendable () -> Value?
    ) async -> Value? {
        let task = Task.detached(priority: priority) { Task.isCancelled ? nil : work() }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
