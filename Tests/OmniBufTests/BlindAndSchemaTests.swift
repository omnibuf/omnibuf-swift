@testable import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf
import Testing

@Suite("OmniBuf Blind Decoder & SchemaMeta Tests")
struct BlindAndSchemaTests {
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

    @Test("SchemaMeta.validateSlice enforces maxElements and maxAllocBytes budgets")
    func testSchemaMetaValidateSliceBudgetEnforcement() throws {
        var fields: [UInt32: String] = [:]
        for i in UInt32(1)...20 {
            fields[i] = "field_\(i)"
        }
        var w = OmniBufWriter()
        SchemaMeta(typeName: "BudgetTest", fields: fields).appendField0(to: &w)
        let packet = w.toBytes()

        // Extract Field #0 slice and test validateSlice directly
        try packet.withUnsafeBufferPointer { buf in
            var r = OmniBufReader(buf)
            let (fnum, wt) = try r.readTag()
            #expect(fnum == 0)
            #expect(wt == WireType.wireSubMsg)
            let slice = try r.readLenSlice()

            // Exceeds maxElements
            var elemBudget = DecodeBudget(options: DecodeOptions(maxElements: 5))
            do {
                try SchemaMeta.validateSlice(slice, depth: 1, budget: &elemBudget)
                Issue.record("expected allocationLimitExceeded for maxElements in validateSlice")
            } catch OmniBufError.allocationLimitExceeded {}

            // Exceeds maxAllocBytes
            var allocBudget = DecodeBudget(options: DecodeOptions(maxAllocBytes: 128))
            do {
                try SchemaMeta.validateSlice(slice, depth: 1, budget: &allocBudget)
                Issue.record("expected allocationLimitExceeded for maxAllocBytes in validateSlice")
            } catch OmniBufError.allocationLimitExceeded {}

            // Succeeds with sufficient budget and charges it
            var okBudget = DecodeBudget(options: .default)
            try SchemaMeta.validateSlice(slice, depth: 1, budget: &okBudget)
            #expect(okBudget.elements == 20)
            #expect(okBudget.allocBytes > 20 * 64)
        }

        // Verify Tier 3 OmniBufStruct enforces budget on Field #0 via validateSlice
        struct EmptyMsg: OmniBufStruct {
            static let omniBufSchema = OmniBufStructSchema<Self>(typeName: "EmptyMsg", fields: [])
        }
        do {
            _ = try EmptyMsg.decoded(from: packet, options: DecodeOptions(maxElements: 5))
            Issue.record("expected allocationLimitExceeded for Field #0 in Tier 3")
        } catch OmniBufError.allocationLimitExceeded {}

        // Verify Tier 2 OmniBufProtobuf enforces budget on Field #0 via validateSlice
        do {
            _ = try OmniBufProtobuf.decode(
                Google_Protobuf_Empty.self,
                from: packet,
                options: DecodeOptions(maxElements: 5)
            )
            Issue.record("expected allocationLimitExceeded for Field #0 in Tier 2")
        } catch OmniBufError.allocationLimitExceeded {}
    }
}
