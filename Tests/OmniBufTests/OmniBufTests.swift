import Foundation
import Testing
@testable import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf

@Suite("OmniBuf Core Wire & Codec Tests")
struct OmniBufCoreTests {
    @Test("Prefix-Varint round-trip across 1, 2, 4, and 9 byte widths")
    func testPrefixVarintWidths() throws {
        let values: [(UInt64, Int)] = [
            (0, 1), (1, 1), (127, 1), (128, 2), (300, 2),
            (16_383, 2), (16_384, 4), (536_870_911, 4), (536_870_912, 9), (UInt64.max, 9),
        ]
        for (v, expectedLen) in values {
            var w = OmniBufWriter()
            w.appendVarint(v)
            let bytes = w.toBytes()
            #expect(bytes.count == expectedLen)
            let decoded = try bytes.withUnsafeBufferPointer { buf -> UInt64 in
                var r = OmniBufReader(buf)
                let val = try r.readVarint()
                #expect(r.isAtEnd)
                return val
            }
            #expect(decoded == v)
        }
    }

    @Test("Non-minimal Prefix-Varint accepted and reserved prefixes rejected")
    func testNonMinimalAndReservedVarints() throws {
        for encoded in [[UInt8(0x55)], [UInt8(0xAA), UInt8(0x00)]] {
            let val = try encoded.withUnsafeBufferPointer { buf -> UInt64 in
                var r = OmniBufReader(buf)
                return try r.readVarint()
            }
            #expect(val == 42)
        }
        for reserved in [UInt8(0x08), UInt8(0x10), UInt8(0x80), UInt8(0xF8)] {
            let bytes: [UInt8] = [reserved, 0, 0, 0, 0, 0, 0, 0, 0]
            #expect(throws: OmniBufError.self) {
                try bytes.withUnsafeBufferPointer { buf in
                    var r = OmniBufReader(buf)
                    _ = try r.readVarint()
                }
            }
        }
    }

    @Test("ZigZag 64-bit encoding and decoding")
    func testZigZag() {
        let pairs: [(Int64, UInt64)] = [
            (0, 0), (-1, 1), (1, 2), (-2, 3), (-64, 127), (64, 128),
            (Int64.max, UInt64.max - 1), (Int64.min, UInt64.max),
        ]
        for (s, u) in pairs {
            #expect(OmniBufWriter.encodeZigZag(s) == u)
            #expect(OmniBufReader.decodeZigZag(u) == s)
        }
    }

    @Test("Strict UTF-8 validation")
    func testStrictUTF8() {
        for bytes in [Array("hello world".utf8), Array("Frankfurt 🚀 日本語".utf8), []] {
            let ok = bytes.withUnsafeBufferPointer { buf in
                buf.baseAddress.map { isValidUTF8($0, count: buf.count) } ?? true
            }
            #expect(ok)
        }
        for bytes in [[UInt8(0x80)], [0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x82]] {
            let ok = bytes.withUnsafeBufferPointer { buf in
                isValidUTF8(buf.baseAddress!, count: buf.count)
            }
            #expect(!ok)
        }
    }

    @Test("Spec Section 9 complete Node example")
    func testSpecNodeExample() throws {
        let expected: [UInt8] = [
            0x21, 0xb2, 0x04, 0x67, 0x72, 0x02, 0x1e, 0x00,
            0x75, 0x07, 0x46, 0x52, 0x41, 0x81, 0x55,
        ]
        let blind = try decodeBlind(expected)
        #expect(blind["field_1"] == .uint(300))
        #expect(blind["field_3"] == .bool(true))
        if case .object(let loc) = blind["field_9"] {
            #expect(loc["field_3"] == .string("FRA"))
            #expect(loc["field_4"] == .uint(42))
        } else {
            Issue.record("expected field_9 object")
        }
    }

    @Test("Empty WireArray and WireMap reject trailing bytes")
    func testEmptyCollectionTrailingBytesRejected() {
        #expect(throws: OmniBufError.self) { _ = try decodeBlind([0x3B, 0x07, 0x00, 0x01, 0xFF]) }
        #expect(throws: OmniBufError.self) { _ = try decodeBlind([0x3D, 0x09, 0x0A, 0x00, 0x01, 0x00]) }
    }

    @Test("Field #0 SchemaMeta validation and name resolution")
    func testField0SchemaMeta() throws {
        #expect(throws: OmniBufError.self) { _ = try decodeBlind([0x01, 0x03]) }
        var w = OmniBufWriter()
        SchemaMeta(typeName: "Demo", fields: [1: "greeting"]).appendField0(to: &w)
        w.appendTag(fieldNumber: 1, wireType: WireType.wireString)
        w.appendStringValue("hello")
        #expect(try decodeBlindJSON(w.toBytes()) == "{\"greeting\":\"hello\"}")
    }

    @Test("Container recursion depth limit (max 32)")
    func testDepthLimitEnforced() {
        var bytes: [UInt8] = []
        for _ in 0..<33 {
            var w = OmniBufWriter()
            w.appendTag(fieldNumber: 1, wireType: WireType.wireSubMsg)
            w.appendVarint(UInt64(bytes.count))
            w.appendRaw(bytes)
            bytes = w.toBytes()
        }
        #expect(throws: OmniBufError.self) { _ = try decodeBlind(bytes) }
    }

    @Test("Single-pass backpatch widening past 16 KiB")
    func testBackpatchWideningPast16KiB() throws {
        var w = OmniBufWriter()
        w.appendTag(fieldNumber: 1, wireType: WireType.wireSubMsg)
        let lenPos = w.reserveLength2()
        w.appendTag(fieldNumber: 1, wireType: WireType.wireString)
        w.appendStringValue(String(repeating: "a", count: 20_000))
        w.backpatchLength2(at: lenPos)
        let blind = try decodeBlind(w.toBytes())
        if case .object(let sub) = blind["field_1"], case .string(let s) = sub["field_1"] {
            #expect(s.count == 20_000)
        } else {
            Issue.record("expected 20000-byte string")
        }
    }

    @Test("Tier 3 OmniBufStruct replace vs merge semantics")
    func testStructReplaceVsMerge() throws {
        struct Simple: OmniBufStruct, Equatable {
            var id: UInt32 = 0
            var tags: [String] = []
            static let omniBufSchema = OmniBufStructSchema<Self>(
                typeName: "Simple",
                fields: [
                    Field.uint32(1, "id", \.id),
                    Field.stringArray(2, "tags", \.tags),
                ]
            )
        }
        let pkt1 = try Simple(id: 7, tags: ["a"]).encodeOmniBuf()
        let pkt2 = try Simple(id: 0, tags: ["b"]).encodeOmniBuf()

        var merged = try Simple.decoded(from: pkt1)
        try merged.mergeOmniBuf(from: pkt2)
        #expect(merged.id == 7)
        #expect(merged.tags == ["a", "b"])

        var replaced = merged
        try replaced.decodeOmniBuf(from: pkt2)
        #expect(replaced.id == 0)
        #expect(replaced.tags == ["b"])
    }

    @Test("Blind decoder handles thousands of repeated sub-message segments without stack overflow")
    func testBlindRepeatedSubMsgNoStackOverflow() throws {
        var w = OmniBufWriter(initialCapacity: 65_536)
        // 20,000 empty sub-message occurrences on field #1 plus a final occurrence with field #1 = 42
        for _ in 0..<20_000 {
            w.appendTag(fieldNumber: 1, wireType: WireType.wireSubMsg)
            w.appendVarint(0)
        }
        w.appendTag(fieldNumber: 1, wireType: WireType.wireSubMsg)
        let lenPos = w.reserveLength2()
        w.appendTag(fieldNumber: 1, wireType: WireType.wireUint)
        w.appendVarint(42)
        w.backpatchLength2(at: lenPos)

        let bytes = w.toBytes()
        let decoded = try decodeBlind(bytes)
        if case .object(let sub) = decoded["field_1"] {
            #expect(sub["field_1"] == .uint(42))
        } else {
            Issue.record("expected merged sub-message object")
        }

        // Verify element budget is charged for repeated sub-message occurrences
        let tightOpts = DecodeBlindOptions(
            decodeOptions: DecodeOptions(maxElements: 100)
        )
        #expect(throws: OmniBufError.self) {
            _ = try decodeBlind(bytes, options: tightOpts)
        }
    }

    @Test("Blind decoder charges budget for distinct scalar fields")
    func testBlindDistinctScalarFieldsBudget() {
        var w = OmniBufWriter()
        for fnum in UInt32(1)...50 {
            w.appendTag(fieldNumber: fnum, wireType: WireType.wireBoolTrue)
        }
        let tightOpts = DecodeBlindOptions(
            decodeOptions: DecodeOptions(maxElements: 20)
        )
        #expect(throws: OmniBufError.self) {
            _ = try decodeBlind(w.toBytes(), options: tightOpts)
        }
    }

    @Test("DecodeOptions clamps negative limits and DecodeBudget rejects negative/overflowing values")
    func testDecodeBudgetSafety() throws {
        let opts = DecodeOptions(
            maxMessageBytes: -10,
            maxElements: -5,
            maxAllocBytes: -100,
            maxDepth: -3
        )
        #expect(opts.maxMessageBytes == 0)
        #expect(opts.maxElements == 0)
        #expect(opts.maxAllocBytes == 0)
        #expect(opts.maxDepth == 0)

        var budget = DecodeBudget(options: .default)
        #expect(throws: OmniBufError.self) { try budget.addElements(-1) }
        #expect(throws: OmniBufError.self) { try budget.addAlloc(-1) }
        #expect(throws: OmniBufError.self) { try budget.addAlloc(count: -1, elementBytes: 8) }
        #expect(throws: OmniBufError.self) { try budget.addAlloc(count: 8, elementBytes: -1) }
        #expect(throws: OmniBufError.self) { try budget.addAlloc(count: Int.max, elementBytes: 32) }
    }

    @Test("SchemaMeta.decodeSlice enforces maxElements limit")
    func testSchemaMetaElementBudget() {
        var fields: [UInt32: String] = [:]
        for i in UInt32(1)...20 {
            fields[i] = "f\(i)"
        }
        var w = OmniBufWriter()
        SchemaMeta(typeName: "Big", fields: fields).appendField0(to: &w)
        let packet = w.toBytes()
        let tightOpts = DecodeBlindOptions(
            decodeOptions: DecodeOptions(maxElements: 5)
        )
        #expect(throws: OmniBufError.self) {
            _ = try decodeBlind(packet, options: tightOpts)
        }
    }

    @Test("OpaqueWire splices sub-ranges and supports field numbers >= 64 and > 65535")
    func testOpaqueWireSubRangeAndHighFields() throws {
        // Build a child payload with field #1 = 10, field #70 = 700, field #100_000 = 999
        var childWriter = OmniBufWriter()
        childWriter.appendTag(fieldNumber: 1, wireType: WireType.wireUint)
        childWriter.appendVarint(10)
        childWriter.appendTag(fieldNumber: 70, wireType: WireType.wireUint)
        childWriter.appendVarint(700)
        childWriter.appendTag(fieldNumber: 100_000, wireType: WireType.wireUint)
        childWriter.appendVarint(999)
        let childBytes = childWriter.toBytes()

        // Embed childBytes inside a larger parent buffer with surrounding sentinel bytes
        let parent: [UInt8] = [0xFF, 0xFE, 0xFD] + childBytes + [0xFC, 0xFB]
        let offset = 3
        let length = childBytes.count

        // Splice dirty field #70 (replace), field #100_000 (replace), and field #200_000 (append new)
        var dst: [UInt8] = []
        try OpaqueWire.trySpliceFields(
            into: &dst,
            raw: parent,
            offset: offset,
            length: length,
            dirtyMask: 0,
            dirtyHigh: [70, 100_000, 200_000],
            maxField: 200_000
        ) { w, fnum in
            w.appendTag(fieldNumber: fnum, wireType: WireType.wireUint)
            switch fnum {
            case 70: w.appendVarint(701)
            case 100_000: w.appendVarint(1000)
            case 200_000: w.appendVarint(2000)
            default: break
            }
        }

        let decoded = try decodeBlind(dst)
        #expect(decoded["field_1"] == .uint(10))
        #expect(decoded["field_70"] == .uint(701))
        #expect(decoded["field_100000"] == .uint(1000))
        #expect(decoded["field_200000"] == .uint(2000))
        #expect(decoded.count == 4)
    }

    @Test("Indirect<T> provides copy-on-write value semantics, Equatable, and Hashable")
    func testIndirectCopyOnWrite() {
        let a = Indirect<Int>(10)
        var b = a
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)

        b.value = 42
        #expect(a.value == 10)
        #expect(b.value == 42)
        #expect(a != b)

        // Mutating a uniquely referenced Indirect updates in place
        var c = Indirect<String>("hello")
        c.value = "world"
        #expect(c.value == "world")
    }

    @Test("OmniBufWriter truncate and OmniBufReader position within valid bounds")
    func testWriterAndReaderBounds() throws {
        var w = OmniBufWriter(initialCapacity: 64)
        w.appendRaw([1, 2, 3, 4, 5])
        w.truncate(to: 3)
        #expect(w.toBytes() == [1, 2, 3])
        w.truncate(to: 0)
        #expect(w.toBytes() == [])

        let data: [UInt8] = [0x03, 0x05]
        let v = try data.withUnsafeBufferPointer { buf -> UInt64 in
            var r = OmniBufReader(base: buf.baseAddress, count: buf.count)
            r.position = 1
            return try r.readVarint()
        }
        #expect(v == 2)
    }
}
