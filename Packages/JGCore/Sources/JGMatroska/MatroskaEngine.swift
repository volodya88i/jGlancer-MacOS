import AVFoundation
import CoreMedia
import Foundation

/// Plays a Matroska file with the system's decoders (D-71): its packets become sample buffers for an
/// `AVSampleBufferDisplayLayer` (H.264, HEVC) and an `AVSampleBufferAudioRenderer` (AAC, AC3, E-AC3, MP3, Opus) on one
/// `AVSampleBufferRenderSynchronizer` clock. Feeding runs on a private serial queue; the caller calls from the main
/// thread. Unsupported tracks are skipped; a file with neither a playable video nor audio track cannot be opened.
public final class MatroskaEngine: @unchecked Sendable {
    public let file: MatroskaFile
    public let synchronizer = AVSampleBufferRenderSynchronizer()
    /// The picture, for the viewer's surface; nil for audio-only files.
    public let videoLayer: AVSampleBufferDisplayLayer?
    public let audioRenderer: AVSampleBufferAudioRenderer?
    /// The video layer's renderer, taken once on the main thread (the layer belongs to it); fed from `queue`.
    private let videoRenderer: AVSampleBufferVideoRenderer?
    public let videoTrack: MatroskaTrack?
    public let audioTrack: MatroskaTrack?
    /// Called on the main queue when the last packet has been shown.
    public var onEnd: (@MainActor @Sendable () -> Void)?

    private let videoFormat: CMFormatDescription?
    private let audioFormat: CMFormatDescription?
    private let queue = DispatchQueue(label: "jGlancer.matroska")
    // State below is touched on `queue` only.
    private var reader: MatroskaPacketReader?
    private var pending: [UInt64: [MatroskaPacket]] = [:]
    private var startTime: Double = 0
    private var generation = 0
    private var exhausted: Set<UInt64> = []
    private var lastTime: Double = 0
    private var boundaryObserver: Any?

    /// Parse the file anywhere (`MatroskaFile` is the slow part); the engine and its layer are made on the main thread.
    @MainActor
    public init(file: MatroskaFile) throws {
        self.file = file
        let video = file.tracks.first { $0.kind == .video && MatroskaCodecs.isSupported($0) }
        let audio = file.tracks.first { $0.kind == .audio && MatroskaCodecs.isSupported($0) }
        videoFormat = video.flatMap(MatroskaCodecs.formatDescription(for:))
        audioFormat = audio.flatMap(MatroskaCodecs.formatDescription(for:))
        videoTrack = videoFormat == nil ? nil : video
        audioTrack = audioFormat == nil ? nil : audio
        guard videoTrack != nil || audioTrack != nil else { throw MatroskaError.unsupported }
        if videoTrack != nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspect
            videoLayer = layer
            videoRenderer = layer.sampleBufferRenderer
            synchronizer.addRenderer(layer.sampleBufferRenderer)
        } else {
            videoLayer = nil
            videoRenderer = nil
        }
        if audioTrack != nil {
            let renderer = AVSampleBufferAudioRenderer()
            audioRenderer = renderer
            synchronizer.addRenderer(renderer)
        } else {
            audioRenderer = nil
        }
    }

    deinit {
        videoRenderer?.stopRequestingMediaData()
        audioRenderer?.stopRequestingMediaData()
    }

    /// The display size of the picture (anamorphic files use their display size).
    public var videoSize: CGSize? {
        videoTrack.map { CGSize(width: $0.displayWidth ?? $0.width, height: $0.displayHeight ?? $0.height) }
    }

    public var currentTime: Double {
        let time = synchronizer.currentTime()
        return time.isNumeric ? max(time.seconds, 0) : 0
    }

    public var isRunning: Bool {
        synchronizer.rate != 0
    }

    // MARK: Transport

    /// Starts showing from `time` at `rate` (0 = paused on the frame at `time`).
    public func start(at time: Double, rate: Float) {
        synchronizer.setRate(0, time: CMTime(seconds: time, preferredTimescale: 90000))
        videoRenderer?.stopRequestingMediaData()
        audioRenderer?.stopRequestingMediaData()
        videoRenderer?.flush(removingDisplayedImage: false, completionHandler: nil)
        audioRenderer?.flush()
        removeBoundary()
        queue.sync {
            generation += 1
            startTime = time
            pending = [:]
            exhausted = []
            lastTime = time
            reader = file.packets(from: file.clusterOffset(before: time))
        }
        let generation = queue.sync { self.generation }
        // The feeders reach the renderers through the engine (shared across threads by design, `@unchecked Sendable`).
        if let track = videoTrack {
            videoRenderer?.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self, let renderer = videoRenderer else { return }
                feedVideo(renderer, track: track, generation: generation)
            }
        }
        if let track = audioTrack {
            audioRenderer?.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self, let renderer = audioRenderer else { return }
                feedAudio(renderer, track: track, generation: generation)
            }
        }
        synchronizer.setRate(rate, time: CMTime(seconds: time, preferredTimescale: 90000))
    }

    public func setRate(_ rate: Float) {
        synchronizer.setRate(rate, time: synchronizer.currentTime())
    }

    public func stop() {
        synchronizer.setRate(0, time: .zero)
        videoRenderer?.stopRequestingMediaData()
        audioRenderer?.stopRequestingMediaData()
        videoRenderer?.flush(removingDisplayedImage: true, completionHandler: nil)
        audioRenderer?.flush()
        removeBoundary()
    }

    public func addPeriodicTimeObserver(interval: Double, _ block: @escaping @Sendable (Double) -> Void) -> Any {
        synchronizer.addPeriodicTimeObserver(forInterval: CMTime(seconds: interval, preferredTimescale: 600), queue: .main) { time in
            if time.isNumeric {
                block(time.seconds)
            }
        }
    }

    /// Calls `block` on the main queue when playback passes `seconds`.
    public func addBoundaryTimeObserver(at seconds: Double, _ block: @escaping @Sendable () -> Void) -> Any {
        synchronizer.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: seconds, preferredTimescale: 90000))], queue: .main, using: block
        )
    }

    public func removeTimeObserver(_ observer: Any) {
        synchronizer.removeTimeObserver(observer)
    }

    // MARK: Feeding (on `queue`)

    private func feedVideo(_ renderer: AVSampleBufferVideoRenderer, track: MatroskaTrack, generation: Int) {
        while generation == self.generation, renderer.isReadyForMoreMediaData {
            guard let packet = nextPacket(track.number) else {
                renderer.stopRequestingMediaData()
                finished(track.number)
                return
            }
            for frame in packet.frames {
                if let buffer = videoBuffer(frame, packet: packet, track: track) {
                    renderer.enqueue(buffer)
                }
            }
            lastTime = max(lastTime, packet.time + (packet.duration ?? track.defaultDuration ?? 0))
        }
    }

    private func feedAudio(_ renderer: AVSampleBufferAudioRenderer, track: MatroskaTrack, generation: Int) {
        let frameSeconds = MatroskaCodecs.samplesPerPacket(track) / max(track.codecID == "A_OPUS" ? 48000 : track.sampleRate, 1)
        while generation == self.generation, renderer.isReadyForMoreMediaData {
            guard let packet = nextPacket(track.number) else {
                renderer.stopRequestingMediaData()
                finished(track.number)
                return
            }
            for (index, frame) in packet.frames.enumerated() {
                let time = packet.time + Double(index) * frameSeconds
                // Audio before the start would play late: it is skipped (video before it is decoded, not shown).
                guard time + frameSeconds >= startTime, let buffer = audioBuffer(frame, time: time) else { continue }
                renderer.enqueue(buffer)
                lastTime = max(lastTime, time + frameSeconds)
            }
        }
    }

    /// The next packet of `track`, reading ahead and keeping other tracks' packets for later.
    private func nextPacket(_ track: UInt64) -> MatroskaPacket? {
        if var queued = pending[track], !queued.isEmpty {
            let packet = queued.removeFirst()
            pending[track] = queued
            return packet
        }
        while let packet = reader?.next() {
            if packet.track == track {
                return packet
            }
            if packet.track == videoTrack?.number || packet.track == audioTrack?.number {
                pending[packet.track, default: []].append(packet)
            }
        }
        return nil
    }

    private func finished(_ track: UInt64) {
        exhausted.insert(track)
        let tracks = [videoTrack?.number, audioTrack?.number].compactMap(\.self)
        guard tracks.allSatisfy(exhausted.contains) else { return }
        let end = CMTime(seconds: max(lastTime, startTime), preferredTimescale: 90000)
        let observer = synchronizer.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            guard let onEnd = self?.onEnd else { return }
            MainActor.assumeIsolated { onEnd() }
        }
        boundaryObserver = observer
    }

    private func removeBoundary() {
        let observer: Any? = queue.sync {
            defer { boundaryObserver = nil }
            return boundaryObserver
        }
        if let observer {
            synchronizer.removeTimeObserver(observer)
        }
    }

    // MARK: Sample buffers

    private func blockBuffer(_ data: Data) -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        ) == noErr, let block else { return nil }
        let status = data.withUnsafeBytes { bytes in
            bytes.baseAddress.map { CMBlockBufferReplaceDataBytes(
                with: $0,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: data.count
            ) }
        }
        return status == noErr ? block : nil
    }

    private func videoBuffer(_ data: Data, packet: MatroskaPacket, track: MatroskaTrack) -> CMSampleBuffer? {
        guard let format = videoFormat, let block = blockBuffer(data) else { return nil }
        let duration = packet.duration ?? track.defaultDuration
        var timing = CMSampleTimingInfo(
            duration: duration.map { CMTime(seconds: $0, preferredTimescale: 90000) } ?? .invalid,
            presentationTimeStamp: CMTime(seconds: packet.time, preferredTimescale: 90000), decodeTimeStamp: .invalid
        )
        var size = data.count
        var buffer: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer
        )
        guard let buffer else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
           let first = (attachments as NSArray).firstObject as? NSMutableDictionary
        {
            first[kCMSampleAttachmentKey_NotSync] = !packet.isKeyframe
            // Frames before the seek target are decoded (later frames need them) but not shown.
            if packet.time < startTime - 0.001 {
                first[kCMSampleAttachmentKey_DoNotDisplay] = true
            }
        }
        return buffer
    }

    private func audioBuffer(_ data: Data, time: Double) -> CMSampleBuffer? {
        guard let format = audioFormat, let block = blockBuffer(data) else { return nil }
        var description = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 90000), packetDescriptions: &description,
            sampleBufferOut: &buffer
        )
        return buffer
    }
}
