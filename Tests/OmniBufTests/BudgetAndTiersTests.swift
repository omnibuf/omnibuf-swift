@testable import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf
import Testing

@Suite("OmniBuf Budgets, OpaqueWire & Tier 2/3 Tests")
struct BudgetAndTiersTests {
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

    @Test("Pre-allocation budget checks reject oversized strings and bytes before validation or allocation")
    func testPreAllocationBudgetChecks() throws {
        // Construct a WireString payload with INVALID UTF-8 (0xFF bytes) whose length (64) exceeds maxAllocBytes (16).
        // Because budget.addAlloc(slice.count) runs BEFORE makeValidatedString, we must get
        // allocationLimitExceeded rather than a UTF-8 parse error.
        let badPayload = [UInt8](repeating: 0xFF, count: 64)
        var wStr = OmniBufWriter()
        wStr.appendTag(fieldNumber: 1, wireType: WireType.wireString)
        wStr.appendBytes(badPayload)
        let strPacket = wStr.toBytes()

        var wBytes = OmniBufWriter()
        wBytes.appendTag(fieldNumber: 2, wireType: WireType.wireBytes)
        wBytes.appendBytes(badPayload)
        let bytesPacket = wBytes.toBytes()

        // 1. Direct OmniBufReader.readString(budget:) / readBytes(budget:)
        var rawStr = OmniBufWriter()
        rawStr.appendBytes(badPayload)
        let rawStrBytes = rawStr.toBytes()
        do {
            try rawStrBytes.withUnsafeBufferPointer { buf in
                var r = OmniBufReader(buf)
                var budget = DecodeBudget(options: DecodeOptions(maxAllocBytes: 16))
                _ = try r.readString(budget: &budget)
            }
            Issue.record("expected allocationLimitExceeded from readString(budget:)")
        } catch OmniBufError.allocationLimitExceeded {
            // Expected: failed before UTF-8 validation and String allocation
        }

        do {
            try rawStrBytes.withUnsafeBufferPointer { buf in
                var r = OmniBufReader(buf)
                var budget = DecodeBudget(options: DecodeOptions(maxAllocBytes: 16))
                _ = try r.readBytes(budget: &budget)
            }
            Issue.record("expected allocationLimitExceeded from readBytes(budget:)")
        } catch OmniBufError.allocationLimitExceeded {
            // Expected: failed before Array allocation
        }

        // 2. Tier 3 OmniBufStruct
        struct BlobMsg: OmniBufStruct, Equatable {
            var s: String = ""
            var b: [UInt8] = []
            static let omniBufSchema = OmniBufStructSchema<Self>(
                typeName: "BlobMsg",
                fields: [
                    Field.string(1, "s", \.s),
                    Field.bytes(2, "b", \.b),
                ]
            )
        }
        let tightOpts = DecodeOptions(maxAllocBytes: 16)
        do {
            _ = try BlobMsg.decoded(from: strPacket, options: tightOpts)
            Issue.record("expected allocationLimitExceeded in Tier 3 string decode")
        } catch OmniBufError.allocationLimitExceeded {}
        do {
            _ = try BlobMsg.decoded(from: bytesPacket, options: tightOpts)
            Issue.record("expected allocationLimitExceeded in Tier 3 bytes decode")
        } catch OmniBufError.allocationLimitExceeded {}

        // 3. Tier 4 decodeBlind (alloc budget must allow 64B field entry overhead but reject 64B payload)
        let blindOpts = DecodeBlindOptions(decodeOptions: DecodeOptions(maxAllocBytes: 80))
        do {
            _ = try decodeBlind(strPacket, options: blindOpts)
            Issue.record("expected allocationLimitExceeded in blind string decode")
        } catch OmniBufError.allocationLimitExceeded {}
        do {
            _ = try decodeBlind(bytesPacket, options: blindOpts)
            Issue.record("expected allocationLimitExceeded in blind bytes decode")
        } catch OmniBufError.allocationLimitExceeded {}

        // 4. SchemaMeta.decodeSlice (field #1 type_name with invalid UTF-8 exceeding budget)
        do {
            try strPacket.withUnsafeBufferPointer { buf in
                var budget = DecodeBudget(options: DecodeOptions(maxAllocBytes: 16))
                _ = try SchemaMeta.decodeSlice(buf, depth: 1, budget: &budget)
            }
            Issue.record("expected allocationLimitExceeded in SchemaMeta.decodeSlice")
        } catch OmniBufError.allocationLimitExceeded {}

        // 5. Tier 2 OmniBufProtobuf (Google_Protobuf_StringValue has string field #1)
        do {
            _ = try OmniBufProtobuf.decode(Google_Protobuf_StringValue.self, from: strPacket, options: tightOpts)
            Issue.record("expected allocationLimitExceeded in Tier 2 string decode")
        } catch OmniBufError.allocationLimitExceeded {}
    }

    @Test("Tier 2 OmniBufVisitor encodes nested SwiftProtobuf messages with shared buffer")
    func testTier2SharedWriterRoundTrip() throws {
        var list = Google_Protobuf_ListValue()
        var v1 = Google_Protobuf_Value()
        v1.stringValue = "alpha"
        var v2 = Google_Protobuf_Value()
        v2.numberValue = 42.5
        var nested = Google_Protobuf_Struct()
        nested.fields["flag"] = Google_Protobuf_Value.with { $0.boolValue = true }
        var v3 = Google_Protobuf_Value()
        v3.structValue = nested
        list.values = [v1, v2, v3]

        let encoded = try OmniBufProtobuf.encode(list)
        let decoded = try OmniBufProtobuf.decode(Google_Protobuf_ListValue.self, from: encoded)
        #expect(decoded == list)
    }
}
