@testable import OmniBuf
import Testing

@Suite("OmniBuf Wire Primitives & Codec Tests")
struct WireCodecTests {
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
