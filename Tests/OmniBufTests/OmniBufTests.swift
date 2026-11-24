import Foundation
import Testing
@testable import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf
import SwiftProtobufPluginLibrary

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

    @Test("Code generator handles recursive messages, nested type qualification, enums, and depth limits")
    func testCodegenRecursiveNestedEnumsAndDepthLimit() throws {
        // Locate the built protoc-gen-omnibuf-swift executable
        let testFileURL = URL(fileURLWithPath: #filePath)
        let pkgRoot = testFileURL
            .deletingLastPathComponent() // OmniBufTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // omnibuf-swift
        let buildDir = pkgRoot.appendingPathComponent(".build")
        let candidatePaths = [
            buildDir.appendingPathComponent("debug/protoc-gen-omnibuf-swift"),
            buildDir.appendingPathComponent("arm64-apple-macosx/debug/protoc-gen-omnibuf-swift"),
            buildDir.appendingPathComponent("x86_64-apple-macosx/debug/protoc-gen-omnibuf-swift"),
            buildDir.appendingPathComponent("release/protoc-gen-omnibuf-swift"),
        ]
        guard let pluginURL = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            Issue.record("protoc-gen-omnibuf-swift executable not found in \(buildDir.path)")
            return
        }

        // Build a synthetic FileDescriptorProto containing:
        // - Top-level enum TopStatus
        // - Self-recursive message TreeNode (singular primary: TreeNode, repeated children: TreeNode)
        // - Mutually recursive messages MutualA <-> MutualB
        // - Two messages OuterA and OuterB, each with nested message Item and nested enum Status
        var file = Google_Protobuf_FileDescriptorProto()
        file.name = "test_codegen.proto"
        file.package = "test.pkg"
        file.syntax = "proto3"

        file.enumType = [
            Google_Protobuf_EnumDescriptorProto.with {
                $0.name = "TopStatus"
                $0.value = [
                    Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "TOP_STATUS_UNSPECIFIED"; $0.number = 0 },
                    Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "TOP_STATUS_OK"; $0.number = 1 },
                ]
            },
        ]

        let treeNode = Google_Protobuf_DescriptorProto.with {
            $0.name = "TreeNode"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "id"; $0.jsonName = "id"; $0.number = 1; $0.label = .optional; $0.type = .uint32
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "primary"; $0.jsonName = "primary"; $0.number = 2; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.TreeNode"
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "children"; $0.jsonName = "children"; $0.number = 3; $0.label = .repeated; $0.type = .message; $0.typeName = ".test.pkg.TreeNode"
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "status"; $0.jsonName = "status"; $0.number = 4; $0.label = .optional; $0.type = .enum; $0.typeName = ".test.pkg.TopStatus"
                },
            ]
        }

        let mutualA = Google_Protobuf_DescriptorProto.with {
            $0.name = "MutualA"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "b"; $0.jsonName = "b"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.MutualB"
                },
            ]
        }
        let mutualB = Google_Protobuf_DescriptorProto.with {
            $0.name = "MutualB"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "a"; $0.jsonName = "a"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.MutualA"
                },
            ]
        }

        func makeOuter(_ outerName: String) -> Google_Protobuf_DescriptorProto {
            Google_Protobuf_DescriptorProto.with {
                $0.name = outerName
                $0.nestedType = [
                    Google_Protobuf_DescriptorProto.with {
                        $0.name = "Item"
                        $0.field = [
                            Google_Protobuf_FieldDescriptorProto.with {
                                $0.name = "val"; $0.jsonName = "val"; $0.number = 1; $0.label = .optional; $0.type = .uint32
                            },
                        ]
                    },
                ]
                $0.enumType = [
                    Google_Protobuf_EnumDescriptorProto.with {
                        $0.name = "Status"
                        $0.value = [
                            Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "STATUS_UNSPECIFIED"; $0.number = 0 },
                            Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "STATUS_ACTIVE"; $0.number = 1 },
                        ]
                    },
                ]
                $0.field = [
                    Google_Protobuf_FieldDescriptorProto.with {
                        $0.name = "item"; $0.jsonName = "item"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.\(outerName).Item"
                    },
                    Google_Protobuf_FieldDescriptorProto.with {
                        $0.name = "status"; $0.jsonName = "status"; $0.number = 2; $0.label = .optional; $0.type = .enum; $0.typeName = ".test.pkg.\(outerName).Status"
                    },
                ]
            }
        }

        file.messageType = [treeNode, mutualA, mutualB, makeOuter("OuterA"), makeOuter("OuterB")]

        var req = Google_Protobuf_Compiler_CodeGeneratorRequest()
        req.fileToGenerate = [file.name]
        req.protoFile = [file]
        let reqData = try req.serializedData()

        let proc = Process()
        proc.executableURL = pluginURL
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        try proc.run()
        stdinPipe.fileHandleForWriting.write(reqData)
        stdinPipe.fileHandleForWriting.closeFile()
        let respData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        #expect(proc.terminationStatus == 0)
        let resp = try Google_Protobuf_Compiler_CodeGeneratorResponse(serializedBytes: respData)
        #expect(resp.error.isEmpty)
        // Must not falsely advertise proto3_optional
        #expect(resp.supportedFeatures == 0)
        guard resp.file.count == 1 else {
            Issue.record("expected 1 generated file, got \(resp.file.count)")
            return
        }

        let code = resp.file[0].content
        // Self-recursive singular field uses Indirect<TreeNode>?, repeated stays [TreeNode]
        #expect(code.contains("public var primary: Indirect<TreeNode>?"))
        #expect(code.contains("public var children: [TreeNode]"))
        // Mutually recursive singular fields use Indirect<MutualB>? and Indirect<MutualA>?
        #expect(code.contains("public var b: Indirect<MutualB>?"))
        #expect(code.contains("public var a: Indirect<MutualA>?"))
        // Non-cyclic nested singular message fields stay plain Optional, qualified with parent name
        #expect(code.contains("public struct OuterA_Item:"))
        #expect(code.contains("public struct OuterB_Item:"))
        #expect(code.contains("public var item: OuterA_Item?"))
        #expect(code.contains("public var item: OuterB_Item?"))
        // Nested enums are qualified and enum fields use generated enum types
        #expect(code.contains("public enum OuterA_Status: Int32"))
        #expect(code.contains("public enum OuterB_Status: Int32"))
        #expect(code.contains("public var status: TopStatus"))
        #expect(code.contains("public var status: OuterA_Status"))
        #expect(code.contains("public var status: OuterB_Status"))
        // Encoding enforces WireType.maxNestingDepth and does not call estimatedOmniBufSize inside encodeOmniBufBodyFast
        #expect(code.contains("guard depth <= WireType.maxNestingDepth"))
        #expect(!code.contains("sub.estimatedOmniBufSize"))
        #expect(!code.contains("elem.estimatedOmniBufSize"))
        // Pre-allocation budget checks & SchemaMeta.validateSlice with budget
        #expect(code.contains("try SchemaMeta.validateSlice(slice, depth: depth &+ 1, budget: &budget)"))
    }
}
