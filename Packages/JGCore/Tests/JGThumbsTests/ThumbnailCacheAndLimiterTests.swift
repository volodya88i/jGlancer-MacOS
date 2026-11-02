import Foundation
import Testing
@testable import JGThumbs

struct ThumbnailDiskCacheTests {
    private func key(_ id: Int64, mtime: Int64 = 1) -> ThumbnailKey {
        ThumbnailKey(assetID: id, modifiedAt: mtime, bucket: .medium)
    }

    @Test func storesFindsAndMarksMissingThumbnails() async throws {
        let cache = try ThumbnailDiskCache.inMemory()
        #expect(try await cache.data(for: key(1)) == nil)
        try await cache.store(Data([1, 2, 3]), width: 10, height: 10, for: key(1))
        try await cache.store(Data(), width: 0, height: 0, for: key(2))
        #expect(try await cache.data(for: key(1)) == Data([1, 2, 3]))
        #expect(try await cache.data(for: key(2)) == Data())
        #expect(try await cache.data(for: key(1, mtime: 2)) == nil)
        #expect(try await cache.usedBytes() == 3)
        try await cache.store(Data([9]), width: 1, height: 1, for: key(1))
        #expect(try await cache.usedBytes() == 1)
        try await cache.removeAll()
        #expect(try await cache.usedBytes() == 0)
    }

    @Test func evictionDropsLeastRecentlyUsedEntriesFirst() async throws {
        let cache = try ThumbnailDiskCache.inMemory(limitBytes: 1000)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for id in 1 ... 10 {
            try await cache.store(Data(count: 150), width: 1, height: 1, for: key(Int64(id)), now: start.addingTimeInterval(Double(id)))
        }
        // Entry 1 is read two days later, so it becomes the most recently used.
        _ = try await cache.data(for: key(1), now: start.addingTimeInterval(2 * 86400))
        try await cache.evictIfNeeded()
        #expect(try await cache.usedBytes() <= 900)
        #expect(try await cache.data(for: key(1)) != nil)
        #expect(try await cache.data(for: key(2)) == nil)
        #expect(try await cache.data(for: key(10)) != nil)
    }

    @Test func corruptCacheFileIsRecreated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JGThumbsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cache.sqlite")
        try Data("this is not a database".utf8).write(to: url)
        let cache = try ThumbnailDiskCache.open(at: url)
        try await cache.store(Data([1]), width: 1, height: 1, for: key(1))
        #expect(try await cache.data(for: key(1)) == Data([1]))
    }
}

struct PriorityLimiterTests {
    @Test func backgroundWorkTakesOneSlotAtATime() async throws {
        let limiter = PriorityLimiter(capacity: 3, backgroundCapacity: 1)
        let first = try #require(await limiter.acquire(priority: .background))
        let second = Task { await limiter.acquire(priority: .background) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await limiter.runningCount == 1) // the second background job waits although slots are free
        let visible = try #require(await limiter.acquire(priority: .visible))
        #expect(await limiter.runningCount == 2)
        await limiter.release(first)
        let next = try #require(await second.value)
        #expect(next.isBackground)
        await limiter.release(next)
        await limiter.release(visible)
    }

    @Test func aLoweredWaiterFallsBehind() async throws {
        let limiter = PriorityLimiter(capacity: 1, backgroundCapacity: 1)
        let held = try #require(await limiter.acquire(priority: .visible))
        let order = OrderLog()
        let lowered = Task {
            if let slot = await limiter.acquire(priority: .visible, tag: "away") {
                await order.append("away")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let nearby = Task {
            if let slot = await limiter.acquire(priority: .nearby) {
                await order.append("nearby")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        await limiter.setPriority(tag: "away", to: .background)
        await limiter.release(held)
        await lowered.value
        await nearby.value
        #expect(await order.entries == ["nearby", "away"])
    }

    @Test func capacityIsRespectedAndHighPriorityGoesFirst() async throws {
        let limiter = PriorityLimiter(capacity: 1)
        let held = try #require(await limiter.acquire(priority: .visible))
        let order = OrderLog()
        let background = Task {
            if let slot = await limiter.acquire(priority: .background) {
                await order.append("background")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let visible = Task {
            if let slot = await limiter.acquire(priority: .visible) {
                await order.append("visible")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await limiter.runningCount == 1)
        await limiter.release(held)
        await background.value
        await visible.value
        #expect(await order.entries == ["visible", "background"])
    }

    @Test func boostedWaiterOvertakes() async throws {
        let limiter = PriorityLimiter(capacity: 1)
        let held = try #require(await limiter.acquire(priority: .visible))
        let order = OrderLog()
        let first = Task {
            if let slot = await limiter.acquire(priority: .nearby) {
                await order.append("nearby")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let second = Task {
            if let slot = await limiter.acquire(priority: .background, tag: "x") {
                await order.append("boosted")
                await limiter.release(slot)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        await limiter.boost(tag: "x", to: .visible)
        await limiter.release(held)
        await first.value
        await second.value
        #expect(await order.entries == ["boosted", "nearby"])
    }

    @Test func cancelledWaiterGetsNoSlot() async throws {
        let limiter = PriorityLimiter(capacity: 1)
        let held = try #require(await limiter.acquire(priority: .visible))
        let waiter = Task { await limiter.acquire(priority: .visible) != nil }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        #expect(await waiter.value == false)
        await limiter.release(held)
        #expect(await limiter.runningCount == 0)
    }
}

actor OrderLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

struct ThumbnailCacheLimitTests {
    @Test func aSmallerCapEvictsAtOnce() async throws {
        let cache = try ThumbnailDiskCache.inMemory(limitBytes: 10000)
        for id in 0 ..< 10 {
            try await cache.store(
                Data(repeating: 1, count: 900),
                width: 1,
                height: 1,
                for: ThumbnailKey(assetID: Int64(id), modifiedAt: 0, bucket: .medium)
            )
        }
        #expect(try await cache.usedBytes() == 9000)
        try await cache.setLimit(bytes: 3000)
        #expect(cache.limitBytes == 3000)
        #expect(try await cache.usedBytes() <= 2700)
    }
}
