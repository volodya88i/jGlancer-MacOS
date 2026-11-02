import Foundation

/// Element IDs of the Matroska elements the reader uses (matroska.org, EBML specification RFC 8794).
enum MatroskaID {
    static let ebml: UInt32 = 0x1A45_DFA3
    static let segment: UInt32 = 0x1853_8067
    static let info: UInt32 = 0x1549_A966
    static let timecodeScale: UInt32 = 0x2AD7B1
    static let duration: UInt32 = 0x4489
    static let title: UInt32 = 0x7BA9
    static let tracks: UInt32 = 0x1654_AE6B
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackType: UInt32 = 0x83
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let codecDelay: UInt32 = 0x56AA
    static let defaultDuration: UInt32 = 0x23E383
    static let contentEncodings: UInt32 = 0x6D80
    static let video: UInt32 = 0xE0
    static let pixelWidth: UInt32 = 0xB0
    static let pixelHeight: UInt32 = 0xBA
    static let displayWidth: UInt32 = 0x54B0
    static let displayHeight: UInt32 = 0x54BA
    static let audio: UInt32 = 0xE1
    static let samplingFrequency: UInt32 = 0xB5
    static let channels: UInt32 = 0x9F
    static let bitDepth: UInt32 = 0x6264
    static let cluster: UInt32 = 0x1F43_B675
    static let timecode: UInt32 = 0xE7
    static let simpleBlock: UInt32 = 0xA3
    static let blockGroup: UInt32 = 0xA0
    static let block: UInt32 = 0xA1
    static let blockDuration: UInt32 = 0x9B
    static let referenceBlock: UInt32 = 0xFB
    static let cues: UInt32 = 0x1C53_BB6B
    static let cuePoint: UInt32 = 0xBB
    static let cueTime: UInt32 = 0xB3
    static let cueTrackPositions: UInt32 = 0xB7
    static let cueClusterPosition: UInt32 = 0xF1

    /// Children of the segment; one of them ends a cluster of unknown size.
    static let topLevel: Set<UInt32> = [
        cluster, cues, info, tracks, 0x114D_9B74, 0x1254_C367, 0x1043_A770, 0x1941_A469,
    ]
}

/// A variable-length integer: its value, how many bytes it took, and whether all value bits were set (an unknown size).
struct VInt {
    let value: UInt64
    let length: Int
    let isAllOnes: Bool
}

/// An element header: its ID, where its payload starts and ends (unknown sizes end at `limit`).
struct EBMLElement {
    let id: UInt32
    let payload: Int
    let end: Int
    let hasUnknownSize: Bool
}

/// Reads EBML from a byte buffer (a memory-mapped file). Offsets are relative to the buffer's start. Read-only over
/// memory the owning `MatroskaFile` keeps alive and never changes, hence `@unchecked Sendable`.
struct EBMLReader: @unchecked Sendable {
    let bytes: UnsafeRawBufferPointer

    var count: Int {
        bytes.count
    }

    func byte(_ offset: Int) -> UInt8 {
        bytes[offset]
    }

    /// A variable-length integer at `offset`: its value (marker removed unless `keepMarker`), its length, and whether
    /// all value bits are set (an unknown size).
    func vint(at offset: Int, keepMarker: Bool = false) -> VInt? {
        guard offset < count else { return nil }
        let first = bytes[offset]
        guard first != 0 else { return nil }
        let length = first.leadingZeroBitCount + 1
        guard length <= 8, offset + length <= count else { return nil }
        var value = UInt64(keepMarker ? first : first & (0xFF >> length))
        var allOnes = (first & (0xFF >> length)) == (0xFF >> length)
        for index in 1 ..< length {
            let next = bytes[offset + index]
            value = value << 8 | UInt64(next)
            allOnes = allOnes && next == 0xFF
        }
        return VInt(value: value, length: length, isAllOnes: allOnes)
    }

    /// The element header at `offset`, its payload bounded by `limit`.
    func element(at offset: Int, limit: Int) -> EBMLElement? {
        guard let id = vint(at: offset, keepMarker: true), let size = vint(at: offset + id.length) else { return nil }
        let payload = offset + id.length + size.length
        guard payload <= limit else { return nil }
        if size.isAllOnes {
            return EBMLElement(id: UInt32(truncatingIfNeeded: id.value), payload: payload, end: limit, hasUnknownSize: true)
        }
        let end = payload + Int(clamping: size.value)
        return EBMLElement(id: UInt32(truncatingIfNeeded: id.value), payload: payload, end: min(end, limit), hasUnknownSize: false)
    }

    /// The children of `range`, in order.
    func children(_ range: Range<Int>) -> [EBMLElement] {
        var result: [EBMLElement] = []
        var offset = range.lowerBound
        while offset < range.upperBound, let element = element(at: offset, limit: range.upperBound) {
            result.append(element)
            guard element.end > offset else { break }
            offset = element.end
        }
        return result
    }

    func unsigned(_ element: EBMLElement) -> UInt64 {
        var value: UInt64 = 0
        for offset in element.payload ..< min(element.end, element.payload + 8) {
            value = value << 8 | UInt64(bytes[offset])
        }
        return value
    }

    func float(_ element: EBMLElement) -> Double {
        let raw = unsigned(element)
        switch element.end - element.payload {
        case 4: return Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
        case 8: return Double(bitPattern: raw)
        default: return 0
        }
    }

    func string(_ element: EBMLElement) -> String {
        let slice = UnsafeRawBufferPointer(rebasing: bytes[element.payload ..< element.end])
        return String(bytes: slice.prefix { $0 != 0 }, encoding: .utf8) ?? ""
    }

    func data(_ range: Range<Int>) -> Data {
        Data(UnsafeRawBufferPointer(rebasing: bytes[range]))
    }
}
