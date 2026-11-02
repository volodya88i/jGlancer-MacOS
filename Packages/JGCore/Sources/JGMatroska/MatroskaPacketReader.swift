import Foundation

/// Reads blocks in file order, cluster after cluster (also clusters of unknown size).
public struct MatroskaPacketReader: IteratorProtocol, Sendable {
    let file: MatroskaFile
    let reader: EBMLReader
    var offset: Int
    let end: Int
    /// The cluster being read: where its payload ends and its timecode.
    private var clusterEnd: Int?
    private var clusterTime: Int64 = 0
    private var pending: [MatroskaPacket] = []

    init(file: MatroskaFile, reader: EBMLReader, offset: Int, end: Int) {
        self.file = file
        self.reader = reader
        self.offset = offset
        self.end = end
    }

    public mutating func next() -> MatroskaPacket? {
        while pending.isEmpty {
            guard offset < end, advance() else { return nil }
        }
        return pending.removeFirst()
    }

    /// Reads one element: a block (into `pending`), a cluster header, or something skipped. False at the end.
    private mutating func advance() -> Bool {
        if let clusterEnd {
            advance(inClusterEndingAt: clusterEnd)
            return true
        }
        guard let element = reader.element(at: offset, limit: end) else { return false }
        if element.id == MatroskaID.cluster {
            clusterEnd = element.end
            offset = element.payload
            return true
        }
        guard !element.hasUnknownSize, element.end > offset else { return false }
        offset = element.end
        return true
    }

    private mutating func advance(inClusterEndingAt clusterEnd: Int) {
        guard offset < clusterEnd, let element = reader.element(at: offset, limit: clusterEnd),
              !MatroskaID.topLevel.contains(element.id) // the next top-level element ends an unknown-size cluster
        else {
            self.clusterEnd = nil
            return
        }
        offset = element.hasUnknownSize ? clusterEnd : element.end
        readClusterChild(element)
    }

    private mutating func readClusterChild(_ element: EBMLElement) {
        switch element.id {
        case MatroskaID.timecode:
            clusterTime = Int64(reader.unsigned(element))
        case MatroskaID.simpleBlock:
            if let packet = block(element.payload ..< element.end, simple: true, duration: nil, referenced: false) {
                pending.append(packet)
            }
        case MatroskaID.blockGroup:
            if let packet = blockGroup(element) {
                pending.append(packet)
            }
        default:
            break
        }
    }

    /// A BlockGroup: its Block, with a duration and, without ReferenceBlock, a keyframe.
    private func blockGroup(_ element: EBMLElement) -> MatroskaPacket? {
        var blockRange: Range<Int>?
        var duration: UInt64?
        var referenced = false
        for child in reader.children(element.payload ..< element.end) {
            switch child.id {
            case MatroskaID.block: blockRange = child.payload ..< child.end
            case MatroskaID.blockDuration: duration = reader.unsigned(child)
            case MatroskaID.referenceBlock: referenced = true
            default: break
            }
        }
        return blockRange.flatMap { block($0, simple: false, duration: duration, referenced: referenced) }
    }

    /// A Block or SimpleBlock: track, relative time, flags, then one or more (laced) frames.
    private func block(_ range: Range<Int>, simple: Bool, duration: UInt64?, referenced: Bool) -> MatroskaPacket? {
        guard let track = reader.vint(at: range.lowerBound) else { return nil }
        let header = range.lowerBound + track.length
        guard header + 3 <= range.upperBound else { return nil }
        let relative = Int16(bitPattern: UInt16(reader.byte(header)) << 8 | UInt16(reader.byte(header + 1)))
        let flags = reader.byte(header + 2)
        guard let frames = MatroskaLacing.frames(reader, from: header + 3, to: range.upperBound, lacing: (flags >> 1) & 0x03)
        else { return nil }
        let keyframe = simple ? flags & 0x80 != 0 : !referenced
        return MatroskaPacket(
            track: track.value, time: file.seconds(clusterTime + Int64(relative)),
            duration: duration.map { file.seconds(Int64($0)) }, isKeyframe: keyframe, frames: frames
        )
    }
}

/// Splits laced blocks into frames: none, Xiph, fixed-size or EBML lacing.
enum MatroskaLacing {
    static func frames(_ reader: EBMLReader, from start: Int, to end: Int, lacing: UInt8) -> [Data]? {
        guard lacing != 0 else { return [reader.data(start ..< end)] }
        guard start < end else { return nil }
        let count = Int(reader.byte(start)) + 1
        var offset = start + 1
        var sizes: [Int]
        switch lacing {
        case 1: sizes = xiphSizes(reader, count: count, offset: &offset, end: end)
        case 3: guard let ebml = ebmlSizes(reader, count: count, offset: &offset) else { return nil }
            sizes = ebml
        default: sizes = Array(repeating: (end - offset) / count, count: count - 1)
        }
        let used = sizes.reduce(0, +)
        guard used <= end - offset, sizes.allSatisfy({ $0 >= 0 }) else { return nil }
        sizes.append(end - offset - used)
        return sizes.map { size in
            defer { offset += size }
            return reader.data(offset ..< offset + size)
        }
    }

    /// Xiph lacing: each size (but the last) as a run of 255s plus a final byte.
    private static func xiphSizes(_ reader: EBMLReader, count: Int, offset: inout Int, end: Int) -> [Int] {
        (0 ..< count - 1).map { _ in
            var size = 0
            while offset < end {
                let byte = Int(reader.byte(offset))
                offset += 1
                size += byte
                if byte != 255 {
                    break
                }
            }
            return size
        }
    }

    /// EBML lacing: the first size as a vint, then signed differences (none for a single frame).
    private static func ebmlSizes(_ reader: EBMLReader, count: Int, offset: inout Int) -> [Int]? {
        guard count > 1 else { return [] }
        guard let first = reader.vint(at: offset) else { return nil }
        offset += first.length
        var size = Int(first.value)
        var sizes = [size]
        for _ in 0 ..< max(count - 2, 0) {
            guard let delta = reader.vint(at: offset) else { return nil }
            offset += delta.length
            size += Int(delta.value) - ((1 << (7 * delta.length - 1)) - 1)
            sizes.append(size)
        }
        return sizes
    }
}
