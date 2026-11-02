import CoreServices
import Foundation

/// Flags of a file-system event (a subset of `kFSEventStreamEventFlag…`).
public struct FileSystemEventFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let mustScanSubDirs = Self(kFSEventStreamEventFlagMustScanSubDirs)
    public static let userDropped = Self(kFSEventStreamEventFlagUserDropped)
    public static let kernelDropped = Self(kFSEventStreamEventFlagKernelDropped)
    public static let eventIDsWrapped = Self(kFSEventStreamEventFlagEventIdsWrapped)
    public static let historyDone = Self(kFSEventStreamEventFlagHistoryDone)
    public static let rootChanged = Self(kFSEventStreamEventFlagRootChanged)
    public static let itemCreated = Self(kFSEventStreamEventFlagItemCreated)
    public static let itemRemoved = Self(kFSEventStreamEventFlagItemRemoved)
    public static let itemRenamed = Self(kFSEventStreamEventFlagItemRenamed)
    public static let itemModified = Self(kFSEventStreamEventFlagItemModified)
    public static let itemIsFile = Self(kFSEventStreamEventFlagItemIsFile)
    public static let itemIsDirectory = Self(kFSEventStreamEventFlagItemIsDir)

    private init(_ flag: Int) {
        rawValue = UInt32(flag)
    }

    /// The stream lost events or its history; the affected tree must be rescanned.
    public var requiresFullRescan: Bool {
        !intersection([.userDropped, .kernelDropped, .eventIDsWrapped, .rootChanged]).isEmpty
    }
}

/// One file-system event.
public struct FileSystemEvent: Hashable, Sendable {
    public let path: String
    public let flags: FileSystemEventFlags
    public let id: UInt64

    public init(path: String, flags: FileSystemEventFlags, id: UInt64) {
        self.path = path
        self.flags = flags
        self.id = id
    }
}

/// Watches a directory tree with FSEvents and delivers coalesced batches as an `AsyncStream`
/// (docs/ARCHITECTURE.md §5). No polling: the system wakes us only when something changed.
public struct FolderWatcher: Sendable {
    /// Coalescing delay of the stream, in seconds.
    public let latency: TimeInterval

    public init(latency: TimeInterval = 0.5) {
        self.latency = latency
    }

    /// The id of the most recent event system-wide; record it before a full scan to replay later changes.
    public static func currentEventID() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// UUID of the FSEvents database of the volume holding `path`. Stored event ids are only valid
    /// while it stays the same.
    public static func eventDatabaseUUID(forPath path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Events below `path`, starting after event `since` (replaying history), or from now when nil.
    /// Cancelling the consuming task stops the stream.
    public func events(at path: String, since: UInt64? = nil) -> AsyncStream<[FileSystemEvent]> {
        AsyncStream { continuation in
            let box = StreamBox(continuation: continuation)
            box.start(path: path, since: since ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency: latency)
            continuation.onTermination = { _ in box.stop() }
        }
    }
}

/// Owns one FSEventStream; all stream calls and callbacks run on its serial queue.
private final class StreamBox: @unchecked Sendable {
    let continuation: AsyncStream<[FileSystemEvent]>.Continuation
    let queue = DispatchQueue(label: "FolderWatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    init(continuation: AsyncStream<[FileSystemEvent]>.Continuation) {
        self.continuation = continuation
    }

    func start(path: String, since: FSEventStreamEventId, latency: TimeInterval) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passRetained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let box = Unmanaged<StreamBox>.fromOpaque(info).takeUnretainedValue()
            let names = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let batch = (0 ..< min(count, names.count)).map { index in
                FileSystemEvent(path: names[index], flags: FileSystemEventFlags(rawValue: flags[index]), id: ids[index])
            }
            box.continuation.yield(batch)
        }
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        )
        queue.sync {
            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, [path] as CFArray, since, latency, createFlags
            ) else {
                Unmanaged.passUnretained(self).release()
                continuation.finish()
                return
            }
            stream = created
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
        }
    }

    func stop() {
        queue.async {
            guard let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            Unmanaged.passUnretained(self).release()
        }
    }
}
