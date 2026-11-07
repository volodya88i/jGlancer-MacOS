import CoreGraphics
import Foundation
import JGModel
import os

/// Produces thumbnails for the grid, filmstrip and previews (docs/ARCHITECTURE.md §6).
///
/// Lookup order: memory cache (synchronous, `cachedThumbnail`) → `cache.sqlite` → generation from the
/// original under a priority-aware concurrency limit. Identical concurrent requests share one job; a job
/// is cancelled when every caller waiting for it has been cancelled. Callers can lower a job to background
/// (a tile scrolled past, D-81): it then waits behind visible work, runs one at a time, and its result goes to
/// `cache.sqlite` only, so it never pushes visible thumbnails out of memory.
public actor ThumbnailService {
    /// Shared state readable without an actor hop.
    public nonisolated let memory: ThumbnailMemoryCache
    private let disk: ThumbnailDiskCache?
    private let generator: any ThumbnailGenerating
    private let limiter: PriorityLimiter
    private var jobs: [ThumbnailKey: Job] = [:]
    /// The latest priority asked for each job.
    private var priorities: [ThumbnailKey: ThumbnailPriority] = [:]
    private let signposter = OSSignposter(subsystem: "JGCore", category: "thumbs")

    private struct Job {
        let task: Task<CGImage?, Never>
        var waiters: Set<UUID>
    }

    /// - Parameters:
    ///   - memoryLimitBytes: decoded-bitmap budget of the memory cache.
    ///   - concurrency: generations running at once (defaults to half the CPUs, 2…6: fast enough to fill a screen,
    ///     without loading every core during a fast scroll, D-81).
    public init(
        disk: ThumbnailDiskCache?,
        generator: any ThumbnailGenerating = ThumbnailGenerator(),
        memoryLimitBytes: Int = 48 * 1024 * 1024,
        concurrency: Int = min(max(2, ProcessInfo.processInfo.activeProcessorCount / 2), 6)
    ) {
        memory = ThumbnailMemoryCache(limitBytes: memoryLimitBytes)
        self.disk = disk
        self.generator = generator
        limiter = PriorityLimiter(capacity: concurrency)
    }

    /// The thumbnail if it is in memory: `.some(nil)` means "known to have none". No suspension.
    public nonisolated func cachedThumbnail(for request: ThumbnailRequest) -> CGImage?? {
        memory.lookup(request.key)
    }

    /// The thumbnail for `request`, or nil if the file has none or the caller was cancelled.
    public func thumbnail(for request: ThumbnailRequest, priority: ThumbnailPriority) async -> CGImage? {
        let key = request.key
        if let cached = memory.lookup(key) {
            return cached
        }
        let waiter = UUID()
        if jobs[key] != nil, priority > priorities[key] ?? .background {
            priorities[key] = priority
            await limiter.boost(tag: key, to: priority)
        }
        // No suspension from here until the waiter is registered: the job cannot vanish in between.
        if jobs[key] == nil {
            priorities[key] = priority
        }
        var job = jobs[key] ?? Job(task: makeJob(request, priority: priority), waiters: [])
        job.waiters.insert(waiter)
        jobs[key] = job
        let task = job.task
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.leave(key, waiter: waiter) }
        }
        leave(key, waiter: waiter)
        return Task.isCancelled ? nil : image
    }

    /// A thumbnail already made — in memory or in `cache.sqlite` — never generated (a stand-in while something
    /// bigger decodes, D-82). Nil when there is none yet.
    public func storedThumbnail(for request: ThumbnailRequest) async -> CGImage? {
        if let cached = memory.lookup(request.key) {
            return cached
        }
        guard let stored = try? await disk?.data(for: request.key), !stored.isEmpty else { return nil }
        return ThumbnailCodec.decode(stored)
    }

    /// Moves a pending job up or down (a tile came into view, or flew past); running work is not affected.
    public func reprioritize(_ request: ThumbnailRequest, to priority: ThumbnailPriority) async {
        let key = request.key
        guard jobs[key] != nil, priorities[key] != priority else { return }
        priorities[key] = priority
        await limiter.setPriority(tag: key, to: priority)
    }

    /// Several moves at once, in order.
    public func reprioritize(_ changes: [(ThumbnailRequest, ThumbnailPriority)]) async {
        for (request, priority) in changes {
            await reprioritize(request, to: priority)
        }
    }

    /// Whether a finished job's thumbnail belongs in memory (not for background work).
    private func keepsInMemory(_ key: ThumbnailKey) -> Bool {
        (priorities[key] ?? .visible) > .background
    }

    /// Removes everything from memory and disk ("Clear cache").
    public func removeAll() async throws {
        memory.removeAll()
        try await disk?.removeAll()
    }

    private func leave(_ key: ThumbnailKey, waiter: UUID) {
        guard var job = jobs[key], job.waiters.remove(waiter) != nil else { return }
        if job.waiters.isEmpty {
            job.task.cancel()
            jobs[key] = nil
            priorities[key] = nil
        } else {
            jobs[key] = job
        }
    }

    private func makeJob(_ request: ThumbnailRequest, priority: ThumbnailPriority) -> Task<CGImage?, Never> {
        let key = request.key
        let disk = disk
        let memory = memory
        let limiter = limiter
        let generator = generator
        let signposter = signposter
        // Detached: decoding, the redraw for display and encoding for the disk cache run in parallel on the global
        // pool. A plain `Task` here would inherit this actor and do all of them one at a time on it, in line with
        // every request's bookkeeping.
        return Task.detached(priority: priority == .visible ? .userInitiated : .utility) {
            if let stored = try? await disk?.data(for: key) {
                let image = stored.isEmpty ? nil : ThumbnailCodec.decode(stored)
                if await self.keepsInMemory(key) {
                    memory.insert(image, for: key)
                }
                return image
            }
            // A file kept only in the cloud is not downloaded for a thumbnail (D-124). Nothing is remembered: once
            // the file is downloaded, the next request makes its thumbnail.
            if CloudFile.isDataless(atPath: request.url.path) {
                return nil
            }
            guard let slot = await limiter.acquire(priority: priority, tag: key) else { return nil }
            let state = signposter.beginInterval("thumb.generate")
            let image = await generator.generate(request, maxPixelSize: key.bucket.maxPixelSize)
                .flatMap(ThumbnailCodec.displayReady)
            signposter.endInterval("thumb.generate", state)
            await limiter.release(slot)
            guard !Task.isCancelled else { return nil }
            if await self.keepsInMemory(key) {
                memory.insert(image, for: key)
            }
            let preserveAlpha = ThumbnailCodec.preservesAlpha(typeIdentifier: request.typeIdentifier)
            let encoded = image.flatMap { ThumbnailCodec.encode($0, preserveAlpha: preserveAlpha) } ?? Data()
            try? await disk?.store(encoded, width: image?.width ?? 0, height: image?.height ?? 0, for: key)
            return image
        }
    }
}
