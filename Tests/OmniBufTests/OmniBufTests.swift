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
}
