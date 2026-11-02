import Foundation
import Testing
@testable import JGActions

struct ByteCompareTests {
    @Test func comparesEveryByte() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ByteCompare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var bytes = Data((0 ..< (ByteCompare.chunkSize + 500)).map { UInt8($0 % 251) })
        let original = folder.appendingPathComponent("a.bin")
        let copy = folder.appendingPathComponent("b.bin")
        let edited = folder.appendingPathComponent("c.bin")
        try bytes.write(to: original)
        try bytes.write(to: copy)
        // Same size, one byte different past the first chunk: a quick hash of the ends would not see it either.
        bytes[ByteCompare.chunkSize + 10] ^= 0xFF
        try bytes.write(to: edited)
        #expect(ByteCompare.identical(original, copy))
        #expect(!ByteCompare.identical(original, edited))
        #expect(!ByteCompare.identical(original, original))
        #expect(!ByteCompare.identical(original, folder.appendingPathComponent("missing.bin")))
    }
}
