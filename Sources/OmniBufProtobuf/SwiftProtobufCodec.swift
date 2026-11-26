import Foundation
import OmniBuf
import SwiftProtobuf

/// Optional protocol that `SwiftProtobuf.Message` types can conform to in order to supply
/// Field #0 `SchemaMeta` automatically when encoding with `EncodeOptions.selfDescribing`.
public protocol OmniBufSchemaMetaProviding {
    static var omniBufSchemaMeta: SchemaMeta { get }
}

/// Tier 2 OmniBuf codec for standard `SwiftProtobuf.Message` types.
public enum OmniBufProtobuf {
    /// Encodes a `SwiftProtobuf.Message` directly to OmniBuf wire bytes.
    public static func encode<M: SwiftProtobuf.Message>(
        _ message: M,
        options: EncodeOptions = .default,
        schemaMeta: SchemaMeta? = nil
    ) throws -> [UInt8] {
        let box = OmniBufWriterBox(initialCapacity: 256)
        if options.selfDescribing {
            if let meta = schemaMeta {
                meta.appendField0(to: &box.writer)
            } else if let provider = M.self as? any OmniBufSchemaMetaProviding.Type {
                provider.omniBufSchemaMeta.appendField0(to: &box.writer)
            }
        }
        var visitor = OmniBufVisitor(box: box, options: options, depth: 0)
        try message.traverse(visitor: &visitor)
        return box.writer.toBytes()
    }

    /// Encodes a `SwiftProtobuf.Message` body (without Field #0) into `writer`.
    public static func encodeBody<M: SwiftProtobuf.Message>(
        _ message: M,
        into writer: inout OmniBufWriter,
        options: EncodeOptions = .default
    ) throws {
        let box = OmniBufWriterBox(initialCapacity: 256)
        var visitor = OmniBufVisitor(box: box, options: options, depth: 0)
        try message.traverse(visitor: &visitor)
        box.writer.withUnsafeBytes { buf in
            writer.appendRaw(buf)
        }
    }

    /// Decodes OmniBuf bytes into a fresh `SwiftProtobuf.Message` (replace mode).
    public static func decode<M: SwiftProtobuf.Message>(
        _ type: M.Type = M.self,
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws -> M {
        var msg = M()
        try decode(into: &msg, from: bytes, options: options)
        return msg
    }

    /// Replaces `message` by resetting to defaults and decoding `bytes` (replace mode).
    public static func decode<M: SwiftProtobuf.Message>(
        into message: inout M,
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws {
        guard bytes.count <= options.maxMessageBytes else {
            throw OmniBufError.allocationLimitExceeded(
                "message length \(bytes.count) exceeds maxMessageBytes \(options.maxMessageBytes)"
            )
        }
        var fresh = M()
        var budget = DecodeBudget(options: options)
        try bytes.withUnsafeBufferPointer { buf in
            var decoder = OmniBufSwiftDecoder(buffer: buf, depth: 0, budget: budget)
            try fresh.decodeMessage(decoder: &decoder)
            try decoder.finishUnknownFieldIfAny()
            budget = decoder.budget
        }
        message = fresh
    }

    /// Merges OmniBuf bytes into an existing `SwiftProtobuf.Message` (merge mode).
    public static func merge<M: SwiftProtobuf.Message>(
        into message: inout M,
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws {
        guard bytes.count <= options.maxMessageBytes else {
            throw OmniBufError.allocationLimitExceeded(
                "message length \(bytes.count) exceeds maxMessageBytes \(options.maxMessageBytes)"
            )
        }
        var budget = DecodeBudget(options: options)
        try bytes.withUnsafeBufferPointer { buf in
            var decoder = OmniBufSwiftDecoder(buffer: buf, depth: 0, budget: budget)
            try message.decodeMessage(decoder: &decoder)
            try decoder.finishUnknownFieldIfAny()
            budget = decoder.budget
        }
    }
}

// MARK: - SwiftProtobuf.Visitor -> OmniBufWriter

private final class OmniBufWriterBox {
    var writer: OmniBufWriter

    init(initialCapacity: Int = 256) {
        self.writer = OmniBufWriter(initialCapacity: initialCapacity)
    }
}

private struct OmniBufVisitor: SwiftProtobuf.Visitor {
    private let box: OmniBufWriterBox
    private let options: EncodeOptions
    private let depth: Int

    init(box: OmniBufWriterBox, options: EncodeOptions, depth: Int = 0) {
        self.box = box
        self.options = options
        self.depth = depth
    }

    private mutating func write(_ body: (inout OmniBufWriter) throws -> Void) rethrows {
        try body(&box.writer)
    }

    // MARK: Singular Scalars

    mutating func visitSingularFloatField(value: Float, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireFloat32)
            w.appendFloat32(value)
        }
    }

    mutating func visitSingularDoubleField(value: Double, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireFloat64)
            w.appendFloat64(value)
        }
    }

    mutating func visitSingularInt32Field(value: Int32, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSint)
            w.appendZigZag32(value)
        }
    }

    mutating func visitSingularInt64Field(value: Int64, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSint)
            w.appendZigZag(value)
        }
    }

    mutating func visitSingularUInt32Field(value: UInt32, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireUint)
            w.appendVarint(UInt64(value))
        }
    }

    mutating func visitSingularUInt64Field(value: UInt64, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireUint)
            w.appendVarint(value)
        }
    }

    mutating func visitSingularSInt32Field(value: Int32, fieldNumber: Int) throws {
        try visitSingularInt32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitSingularSInt64Field(value: Int64, fieldNumber: Int) throws {
        try visitSingularInt64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitSingularFixed32Field(value: UInt32, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireFixed32)
            w.appendFixed32(value)
        }
    }

    mutating func visitSingularFixed64Field(value: UInt64, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireFixed64)
            w.appendFixed64(value)
        }
    }

    mutating func visitSingularSFixed32Field(value: Int32, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSfixed32)
            w.appendSfixed32(value)
        }
    }

    mutating func visitSingularSFixed64Field(value: Int64, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSfixed64)
            w.appendSfixed64(value)
        }
    }

    mutating func visitSingularBoolField(value: Bool, fieldNumber: Int) throws {
        write { w in
            w.appendTag(
                fieldNumber: UInt32(fieldNumber),
                wireType: value ? WireType.wireBoolTrue : WireType.wireBoolFalse
            )
        }
    }

    mutating func visitSingularStringField(value: String, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireString)
            w.appendStringValue(value)
        }
    }

    mutating func visitSingularBytesField(value: Data, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireBytes)
            w.appendVarint(UInt64(value.count))
            value.withUnsafeBytes { rawBuf in
                if let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), !rawBuf.isEmpty {
                    w.appendRaw(ptr, count: rawBuf.count)
                }
            }
        }
    }

    mutating func visitSingularEnumField<E: SwiftProtobuf.Enum>(value: E, fieldNumber: Int) throws {
        write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSint)
            w.appendZigZag(Int64(value.rawValue))
        }
    }

    mutating func visitSingularMessageField<M: SwiftProtobuf.Message>(value: M, fieldNumber: Int) throws {
        let nextDepth = depth &+ 1
        guard nextDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(nextDepth)
        }
        box.writer.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireSubMsg)
        let lenPos = box.writer.reserveLength2()
        var subVisitor = OmniBufVisitor(box: box, options: options, depth: nextDepth)
        try value.traverse(visitor: &subVisitor)
        box.writer.backpatchLength2(at: lenPos)
    }

    mutating func visitSingularGroupField<G: SwiftProtobuf.Message>(value: G, fieldNumber: Int) throws {
        try visitSingularMessageField(value: value, fieldNumber: fieldNumber)
    }

    // MARK: Repeated & Packed Fields -> WireArray (13)

    private mutating func writeArray(
        fieldNumber: Int,
        elemType: UInt8,
        count: Int,
        body: (inout OmniBufWriter) throws -> Void
    ) throws {
        guard count > 0 else { return }
        let arrDepth = depth &+ 1
        guard arrDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(arrDepth)
        }
        try write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireArray)
            let lenPos = w.reserveLength2()
            w.appendByte(elemType)
            w.appendVarint(UInt64(count))
            try body(&w)
            w.backpatchLength2(at: lenPos)
        }
    }

    mutating func visitRepeatedFloatField(value: [Float], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireFloat32, count: value.count) { w in
            for v in value { w.appendFloat32(v) }
        }
    }
    mutating func visitPackedFloatField(value: [Float], fieldNumber: Int) throws {
        try visitRepeatedFloatField(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedDoubleField(value: [Double], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireFloat64, count: value.count) { w in
            for v in value { w.appendFloat64(v) }
        }
    }
    mutating func visitPackedDoubleField(value: [Double], fieldNumber: Int) throws {
        try visitRepeatedDoubleField(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedInt32Field(value: [Int32], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireSint, count: value.count) { w in
            for v in value { w.appendZigZag32(v) }
        }
    }
    mutating func visitPackedInt32Field(value: [Int32], fieldNumber: Int) throws {
        try visitRepeatedInt32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedInt64Field(value: [Int64], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireSint, count: value.count) { w in
            for v in value { w.appendZigZag(v) }
        }
    }
    mutating func visitPackedInt64Field(value: [Int64], fieldNumber: Int) throws {
        try visitRepeatedInt64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedUInt32Field(value: [UInt32], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireUint, count: value.count) { w in
            for v in value { w.appendVarint(UInt64(v)) }
        }
    }
    mutating func visitPackedUInt32Field(value: [UInt32], fieldNumber: Int) throws {
        try visitRepeatedUInt32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedUInt64Field(value: [UInt64], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireUint, count: value.count) { w in
            for v in value { w.appendVarint(v) }
        }
    }
    mutating func visitPackedUInt64Field(value: [UInt64], fieldNumber: Int) throws {
        try visitRepeatedUInt64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedSInt32Field(value: [Int32], fieldNumber: Int) throws {
        try visitRepeatedInt32Field(value: value, fieldNumber: fieldNumber)
    }
    mutating func visitPackedSInt32Field(value: [Int32], fieldNumber: Int) throws {
        try visitRepeatedInt32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedSInt64Field(value: [Int64], fieldNumber: Int) throws {
        try visitRepeatedInt64Field(value: value, fieldNumber: fieldNumber)
    }
    mutating func visitPackedSInt64Field(value: [Int64], fieldNumber: Int) throws {
        try visitRepeatedInt64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedFixed32Field(value: [UInt32], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireFixed32, count: value.count) { w in
            for v in value { w.appendFixed32(v) }
        }
    }
    mutating func visitPackedFixed32Field(value: [UInt32], fieldNumber: Int) throws {
        try visitRepeatedFixed32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedFixed64Field(value: [UInt64], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireFixed64, count: value.count) { w in
            for v in value { w.appendFixed64(v) }
        }
    }
    mutating func visitPackedFixed64Field(value: [UInt64], fieldNumber: Int) throws {
        try visitRepeatedFixed64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedSFixed32Field(value: [Int32], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireSfixed32, count: value.count) { w in
            for v in value { w.appendSfixed32(v) }
        }
    }
    mutating func visitPackedSFixed32Field(value: [Int32], fieldNumber: Int) throws {
        try visitRepeatedSFixed32Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedSFixed64Field(value: [Int64], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireSfixed64, count: value.count) { w in
            for v in value { w.appendSfixed64(v) }
        }
    }
    mutating func visitPackedSFixed64Field(value: [Int64], fieldNumber: Int) throws {
        try visitRepeatedSFixed64Field(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedBoolField(value: [Bool], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireBoolFalse, count: value.count) { w in
            for v in value { w.appendByte(v ? 1 : 0) }
        }
    }
    mutating func visitPackedBoolField(value: [Bool], fieldNumber: Int) throws {
        try visitRepeatedBoolField(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedStringField(value: [String], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireString, count: value.count) { w in
            for v in value { w.appendStringValue(v) }
        }
    }

    mutating func visitRepeatedBytesField(value: [Data], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireBytes, count: value.count) { w in
            for v in value {
                w.appendVarint(UInt64(v.count))
                v.withUnsafeBytes { rawBuf in
                    if let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), !rawBuf.isEmpty {
                        w.appendRaw(ptr, count: rawBuf.count)
                    }
                }
            }
        }
    }

    mutating func visitRepeatedEnumField<E: SwiftProtobuf.Enum>(value: [E], fieldNumber: Int) throws {
        try writeArray(fieldNumber: fieldNumber, elemType: WireType.wireSint, count: value.count) { w in
            for v in value { w.appendZigZag(Int64(v.rawValue)) }
        }
    }
    mutating func visitPackedEnumField<E: SwiftProtobuf.Enum>(value: [E], fieldNumber: Int) throws {
        try visitRepeatedEnumField(value: value, fieldNumber: fieldNumber)
    }

    mutating func visitRepeatedMessageField<M: SwiftProtobuf.Message>(value: [M], fieldNumber: Int) throws {
        guard !value.isEmpty else { return }
        let arrDepth = depth &+ 1
        guard arrDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(arrDepth)
        }
        let elemDepth = arrDepth &+ 1
        guard elemDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(elemDepth)
        }
        box.writer.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireArray)
        let lenPos = box.writer.reserveLength2()
        box.writer.appendByte(WireType.wireSubMsg)
        box.writer.appendVarint(UInt64(value.count))
        for item in value {
            let elemLenPos = box.writer.reserveLength2()
            var subVisitor = OmniBufVisitor(box: box, options: options, depth: elemDepth)
            try item.traverse(visitor: &subVisitor)
            box.writer.backpatchLength2(at: elemLenPos)
        }
        box.writer.backpatchLength2(at: lenPos)
    }

    mutating func visitRepeatedGroupField<G: SwiftProtobuf.Message>(value: [G], fieldNumber: Int) throws {
        try visitRepeatedMessageField(value: value, fieldNumber: fieldNumber)
    }

    // MARK: Map Fields -> WireMap (14)

    mutating func visitMapField<KeyType, ValueType: SwiftProtobuf.MapValueType>(
        fieldType: SwiftProtobuf._ProtobufMap<KeyType, ValueType>.Type,
        value: SwiftProtobuf._ProtobufMap<KeyType, ValueType>.BaseType,
        fieldNumber: Int
    ) throws {
        guard !value.isEmpty else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let keyWT = try wireTypeForFieldType(KeyType.self)
        let valWT = try wireTypeForFieldType(ValueType.self)
        let det = options.deterministic
        try write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireMap)
            let lenPos = w.reserveLength2()
            w.appendTwoBytes(keyWT, valWT)
            w.appendVarint(UInt64(value.count))
            let keys = sortedMapKeys(Array(value.keys), keyType: KeyType.self, deterministic: det)
            for k in keys {
                try appendMapScalar(k, fieldType: KeyType.self, to: &w)
                try appendMapScalar(value[k]!, fieldType: ValueType.self, to: &w)
            }
            w.backpatchLength2(at: lenPos)
        }
    }

    mutating func visitMapField<KeyType, ValueType>(
        fieldType: SwiftProtobuf._ProtobufEnumMap<KeyType, ValueType>.Type,
        value: SwiftProtobuf._ProtobufEnumMap<KeyType, ValueType>.BaseType,
        fieldNumber: Int
    ) throws where ValueType.RawValue == Int {
        guard !value.isEmpty else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let keyWT = try wireTypeForFieldType(KeyType.self)
        let det = options.deterministic
        try write { w in
            w.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireMap)
            let lenPos = w.reserveLength2()
            w.appendTwoBytes(keyWT, WireType.wireSint)
            w.appendVarint(UInt64(value.count))
            let keys = sortedMapKeys(Array(value.keys), keyType: KeyType.self, deterministic: det)
            for k in keys {
                try appendMapScalar(k, fieldType: KeyType.self, to: &w)
                w.appendZigZag(Int64(value[k]!.rawValue))
            }
            w.backpatchLength2(at: lenPos)
        }
    }

    mutating func visitMapField<KeyType, ValueType>(
        fieldType: SwiftProtobuf._ProtobufMessageMap<KeyType, ValueType>.Type,
        value: SwiftProtobuf._ProtobufMessageMap<KeyType, ValueType>.BaseType,
        fieldNumber: Int
    ) throws {
        guard !value.isEmpty else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let valDepth = mapDepth &+ 1
        guard valDepth <= WireType.maxNestingDepth else {
            throw OmniBufError.depthLimitExceeded(valDepth)
        }
        let keyWT = try wireTypeForFieldType(KeyType.self)
        box.writer.appendTag(fieldNumber: UInt32(fieldNumber), wireType: WireType.wireMap)
        let lenPos = box.writer.reserveLength2()
        box.writer.appendTwoBytes(keyWT, WireType.wireSubMsg)
        box.writer.appendVarint(UInt64(value.count))
        let keys = sortedMapKeys(Array(value.keys), keyType: KeyType.self, deterministic: options.deterministic)
        for k in keys {
            try appendMapScalar(k, fieldType: KeyType.self, to: &box.writer)
            let msgLenPos = box.writer.reserveLength2()
            var subVisitor = OmniBufVisitor(box: box, options: options, depth: valDepth)
            try value[k]!.traverse(visitor: &subVisitor)
            box.writer.backpatchLength2(at: msgLenPos)
        }
        box.writer.backpatchLength2(at: lenPos)
    }

    mutating func visitExtensionFields(fields: ExtensionFieldValueSet, start: Int, end: Int) throws {}
    mutating func visitExtensionFieldsAsMessageSet(fields: ExtensionFieldValueSet, start: Int, end: Int) throws {}
    mutating func visitUnknown(bytes: Data) throws {}
}

private func wireTypeForFieldType<FT: SwiftProtobuf.FieldType>(_ type: FT.Type) throws -> UInt8 {
    switch type {
    case is ProtobufUInt32.Type, is ProtobufUInt64.Type: return WireType.wireUint
    case is ProtobufInt32.Type, is ProtobufInt64.Type,
         is ProtobufSInt32.Type, is ProtobufSInt64.Type: return WireType.wireSint
    case is ProtobufBool.Type: return WireType.wireBoolFalse
    case is ProtobufFixed32.Type: return WireType.wireFixed32
    case is ProtobufFixed64.Type: return WireType.wireFixed64
    case is ProtobufSFixed32.Type: return WireType.wireSfixed32
    case is ProtobufSFixed64.Type: return WireType.wireSfixed64
    case is ProtobufFloat.Type: return WireType.wireFloat32
    case is ProtobufDouble.Type: return WireType.wireFloat64
    case is ProtobufString.Type: return WireType.wireString
    case is ProtobufBytes.Type: return WireType.wireBytes
    default:
        throw OmniBufError.serialize("unsupported SwiftProtobuf map field type \(type)")
    }
}

private func sortedMapKeys<K: SwiftProtobuf.MapKeyType>(
    _ keys: [K.BaseType],
    keyType: K.Type,
    deterministic: Bool
) -> [K.BaseType] {
    guard deterministic else { return keys }
    if keyType == ProtobufString.self {
        return keys.sorted { a, b in
            compareUTF8Bytes(a as! String, b as! String)
        }
    }
    return keys.sorted { K._lessThan(lhs: $0, rhs: $1) }
}

private func appendMapScalar<FT: SwiftProtobuf.FieldType>(
    _ value: FT.BaseType,
    fieldType: FT.Type,
    to w: inout OmniBufWriter
) throws {
    switch fieldType {
    case is ProtobufUInt32.Type: w.appendVarint(UInt64(value as! UInt32))
    case is ProtobufUInt64.Type: w.appendVarint(value as! UInt64)
    case is ProtobufInt32.Type, is ProtobufSInt32.Type: w.appendZigZag32(value as! Int32)
    case is ProtobufInt64.Type, is ProtobufSInt64.Type: w.appendZigZag(value as! Int64)
    case is ProtobufBool.Type: w.appendByte((value as! Bool) ? 1 : 0)
    case is ProtobufFixed32.Type: w.appendFixed32(value as! UInt32)
    case is ProtobufFixed64.Type: w.appendFixed64(value as! UInt64)
    case is ProtobufSFixed32.Type: w.appendSfixed32(value as! Int32)
    case is ProtobufSFixed64.Type: w.appendSfixed64(value as! Int64)
    case is ProtobufFloat.Type: w.appendFloat32(value as! Float)
    case is ProtobufDouble.Type: w.appendFloat64(value as! Double)
    case is ProtobufString.Type: w.appendStringValue(value as! String)
    case is ProtobufBytes.Type:
        let d = value as! Data
        w.appendVarint(UInt64(d.count))
        d.withUnsafeBytes { rawBuf in
            if let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), !rawBuf.isEmpty {
                w.appendRaw(ptr, count: rawBuf.count)
            }
        }
    default:
        throw OmniBufError.serialize("unsupported SwiftProtobuf map scalar \(fieldType)")
    }
}

// MARK: - OmniBufReader -> SwiftProtobuf.Decoder

private struct OmniBufSwiftDecoder: SwiftProtobuf.Decoder {
    var reader: OmniBufReader
    let depth: Int
    var budget: DecodeBudget
    var currentWireType: UInt8 = 0
    var hasUnconsumedField: Bool = false

    init(buffer: UnsafeBufferPointer<UInt8>, depth: Int, budget: DecodeBudget) {
        self.reader = OmniBufReader(buffer)
        self.depth = depth
        self.budget = budget
    }

    mutating func finishUnknownFieldIfAny() throws {
        if hasUnconsumedField {
            hasUnconsumedField = false
            try reader.validateValue(wireType: currentWireType, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
        }
    }

    mutating func handleConflictingOneOf() throws {}

    mutating func nextFieldNumber() throws -> Int? {
        // If previous field was not consumed by the message's switch statement (unknown field), validate & skip it!
        try finishUnknownFieldIfAny()

        while !reader.isAtEnd {
            let (fnum, wt) = try reader.readTag()
            if fnum == 0 {
                guard wt == WireType.wireSubMsg else {
                    throw OmniBufError.parse("Field #0 must have WireSubMsg (12), got \(wt)")
                }
                let slice = try reader.readLenSlice()
                try SchemaMeta.validateSlice(slice, depth: depth &+ 1, budget: &budget)
                continue
            }
            currentWireType = wt
            hasUnconsumedField = true
            return Int(fnum)
        }
        return nil
    }

    private mutating func expectOrSkip(_ expectedWT: UInt8) throws -> Bool {
        hasUnconsumedField = false
        if currentWireType != expectedWT {
            try reader.validateValue(wireType: currentWireType, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
            return false
        }
        return true
    }

    // MARK: Singular Decoders

    mutating func decodeSingularFloatField(value: inout Float) throws {
        guard try expectOrSkip(WireType.wireFloat32) else { return }
        value = try reader.readFloat32()
    }
    mutating func decodeSingularFloatField(value: inout Float?) throws {
        guard try expectOrSkip(WireType.wireFloat32) else { return }
        value = try reader.readFloat32()
    }

    mutating func decodeSingularDoubleField(value: inout Double) throws {
        guard try expectOrSkip(WireType.wireFloat64) else { return }
        value = try reader.readFloat64()
    }
    mutating func decodeSingularDoubleField(value: inout Double?) throws {
        guard try expectOrSkip(WireType.wireFloat64) else { return }
        value = try reader.readFloat64()
    }

    mutating func decodeSingularInt32Field(value: inout Int32) throws {
        guard try expectOrSkip(WireType.wireSint) else { return }
        value = try reader.readSint32()
    }
    mutating func decodeSingularInt32Field(value: inout Int32?) throws {
        guard try expectOrSkip(WireType.wireSint) else { return }
        value = try reader.readSint32()
    }

    mutating func decodeSingularInt64Field(value: inout Int64) throws {
        guard try expectOrSkip(WireType.wireSint) else { return }
        value = try reader.readSint64()
    }
    mutating func decodeSingularInt64Field(value: inout Int64?) throws {
        guard try expectOrSkip(WireType.wireSint) else { return }
        value = try reader.readSint64()
    }

    mutating func decodeSingularUInt32Field(value: inout UInt32) throws {
        guard try expectOrSkip(WireType.wireUint) else { return }
        value = UInt32(truncatingIfNeeded: try reader.readVarint())
    }
    mutating func decodeSingularUInt32Field(value: inout UInt32?) throws {
        guard try expectOrSkip(WireType.wireUint) else { return }
        value = UInt32(truncatingIfNeeded: try reader.readVarint())
    }

    mutating func decodeSingularUInt64Field(value: inout UInt64) throws {
        guard try expectOrSkip(WireType.wireUint) else { return }
        value = try reader.readVarint()
    }
    mutating func decodeSingularUInt64Field(value: inout UInt64?) throws {
        guard try expectOrSkip(WireType.wireUint) else { return }
        value = try reader.readVarint()
    }

    mutating func decodeSingularSInt32Field(value: inout Int32) throws {
        try decodeSingularInt32Field(value: &value)
    }
    mutating func decodeSingularSInt32Field(value: inout Int32?) throws {
        try decodeSingularInt32Field(value: &value)
    }

    mutating func decodeSingularSInt64Field(value: inout Int64) throws {
        try decodeSingularInt64Field(value: &value)
    }
    mutating func decodeSingularSInt64Field(value: inout Int64?) throws {
        try decodeSingularInt64Field(value: &value)
    }

    mutating func decodeSingularFixed32Field(value: inout UInt32) throws {
        guard try expectOrSkip(WireType.wireFixed32) else { return }
        value = try reader.readFixed32()
    }
    mutating func decodeSingularFixed32Field(value: inout UInt32?) throws {
        guard try expectOrSkip(WireType.wireFixed32) else { return }
        value = try reader.readFixed32()
    }

    mutating func decodeSingularFixed64Field(value: inout UInt64) throws {
        guard try expectOrSkip(WireType.wireFixed64) else { return }
        value = try reader.readFixed64()
    }
    mutating func decodeSingularFixed64Field(value: inout UInt64?) throws {
        guard try expectOrSkip(WireType.wireFixed64) else { return }
        value = try reader.readFixed64()
    }

    mutating func decodeSingularSFixed32Field(value: inout Int32) throws {
        guard try expectOrSkip(WireType.wireSfixed32) else { return }
        value = try reader.readSfixed32()
    }
    mutating func decodeSingularSFixed32Field(value: inout Int32?) throws {
        guard try expectOrSkip(WireType.wireSfixed32) else { return }
        value = try reader.readSfixed32()
    }

    mutating func decodeSingularSFixed64Field(value: inout Int64) throws {
        guard try expectOrSkip(WireType.wireSfixed64) else { return }
        value = try reader.readSfixed64()
    }
    mutating func decodeSingularSFixed64Field(value: inout Int64?) throws {
        guard try expectOrSkip(WireType.wireSfixed64) else { return }
        value = try reader.readSfixed64()
    }

    mutating func decodeSingularBoolField(value: inout Bool) throws {
        hasUnconsumedField = false
        if currentWireType == WireType.wireBoolFalse {
            value = false
        } else if currentWireType == WireType.wireBoolTrue {
            value = true
        } else {
            try reader.validateValue(wireType: currentWireType, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
        }
    }
    mutating func decodeSingularBoolField(value: inout Bool?) throws {
        hasUnconsumedField = false
        if currentWireType == WireType.wireBoolFalse {
            value = false
        } else if currentWireType == WireType.wireBoolTrue {
            value = true
        } else {
            try reader.validateValue(wireType: currentWireType, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
        }
    }

    mutating func decodeSingularStringField(value: inout String) throws {
        guard try expectOrSkip(WireType.wireString) else { return }
        value = try reader.readString(budget: &budget)
    }
    mutating func decodeSingularStringField(value: inout String?) throws {
        guard try expectOrSkip(WireType.wireString) else { return }
        value = try reader.readString(budget: &budget)
    }

    mutating func decodeSingularBytesField(value: inout Data) throws {
        guard try expectOrSkip(WireType.wireBytes) else { return }
        let slice = try reader.readLenSlice()
        try budget.addAlloc(slice.count)
        value = Data(slice)
    }
    mutating func decodeSingularBytesField(value: inout Data?) throws {
        guard try expectOrSkip(WireType.wireBytes) else { return }
        let slice = try reader.readLenSlice()
        try budget.addAlloc(slice.count)
        value = Data(slice)
    }

    mutating func decodeSingularEnumField<E: SwiftProtobuf.Enum>(value: inout E) throws where E.RawValue == Int {
        guard try expectOrSkip(WireType.wireSint) else { return }
        let raw = Int(try reader.readSint32())
        value = E(rawValue: raw) ?? E()
    }
    mutating func decodeSingularEnumField<E: SwiftProtobuf.Enum>(value: inout E?) throws where E.RawValue == Int {
        guard try expectOrSkip(WireType.wireSint) else { return }
        let raw = Int(try reader.readSint32())
        value = E(rawValue: raw) ?? E()
    }

    mutating func decodeSingularMessageField<M: SwiftProtobuf.Message>(value: inout M?) throws {
        guard try expectOrSkip(WireType.wireSubMsg) else { return }
        let nextDepth = depth &+ 1
        guard nextDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(nextDepth)
        }
        let slice = try reader.readLenSlice()
        var sub = value ?? M()
        var subDecoder = OmniBufSwiftDecoder(buffer: slice, depth: nextDepth, budget: budget)
        try sub.decodeMessage(decoder: &subDecoder)
        try subDecoder.finishUnknownFieldIfAny()
        budget = subDecoder.budget
        value = sub
    }

    mutating func decodeSingularGroupField<G: SwiftProtobuf.Message>(value: inout G?) throws {
        try decodeSingularMessageField(value: &value)
    }

    // MARK: Repeated Decoders

    private mutating func decodeArray(
        expectedElemWT: UInt8,
        elemAllocBytes: Int,
        body: (inout OmniBufReader, Int, inout DecodeBudget) throws -> Void
    ) throws {
        guard try expectOrSkip(WireType.wireArray) else { return }
        let arrDepth = depth &+ 1
        guard arrDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(arrDepth)
        }
        let slice = try reader.readLenSlice(minLen: 2)
        let (elemWT, count, er0) = try OmniBufReader.parseArrayBody(slice)
        guard elemWT == expectedElemWT else {
            throw OmniBufError.parse("WireArray element type mismatch: expected \(expectedElemWT), got \(elemWT)")
        }
        try budget.addElements(count)
        if elemAllocBytes > 0 {
            try budget.addAlloc(count: count, elementBytes: elemAllocBytes)
        }
        var er = er0
        try body(&er, count, &budget)
        guard er.isAtEnd else {
            throw OmniBufError.parse("WireArray has \(er.remaining) trailing bytes")
        }
    }

    private static func safeReserve<T>(_ array: inout [T], additional count: Int) throws {
        let (newCap, overflow) = array.count.addingReportingOverflow(count)
        if overflow {
            throw OmniBufError.allocationLimitExceeded("array capacity overflow")
        }
        array.reserveCapacity(newCap)
    }

    mutating func decodeRepeatedFloatField(value: inout [Float]) throws {
        try decodeArray(expectedElemWT: WireType.wireFloat32, elemAllocBytes: 4) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readFloat32()) }
        }
    }

    mutating func decodeRepeatedDoubleField(value: inout [Double]) throws {
        try decodeArray(expectedElemWT: WireType.wireFloat64, elemAllocBytes: 8) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readFloat64()) }
        }
    }

    mutating func decodeRepeatedInt32Field(value: inout [Int32]) throws {
        try decodeArray(expectedElemWT: WireType.wireSint, elemAllocBytes: 4) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readSint32()) }
        }
    }

    mutating func decodeRepeatedInt64Field(value: inout [Int64]) throws {
        try decodeArray(expectedElemWT: WireType.wireSint, elemAllocBytes: 8) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readSint64()) }
        }
    }

    mutating func decodeRepeatedUInt32Field(value: inout [UInt32]) throws {
        try decodeArray(expectedElemWT: WireType.wireUint, elemAllocBytes: 4) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(UInt32(truncatingIfNeeded: try er.readVarint())) }
        }
    }

    mutating func decodeRepeatedUInt64Field(value: inout [UInt64]) throws {
        try decodeArray(expectedElemWT: WireType.wireUint, elemAllocBytes: 8) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readVarint()) }
        }
    }

    mutating func decodeRepeatedSInt32Field(value: inout [Int32]) throws {
        try decodeRepeatedInt32Field(value: &value)
    }

    mutating func decodeRepeatedSInt64Field(value: inout [Int64]) throws {
        try decodeRepeatedInt64Field(value: &value)
    }

    mutating func decodeRepeatedFixed32Field(value: inout [UInt32]) throws {
        try decodeArray(expectedElemWT: WireType.wireFixed32, elemAllocBytes: 4) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readFixed32()) }
        }
    }

    mutating func decodeRepeatedFixed64Field(value: inout [UInt64]) throws {
        try decodeArray(expectedElemWT: WireType.wireFixed64, elemAllocBytes: 8) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readFixed64()) }
        }
    }

    mutating func decodeRepeatedSFixed32Field(value: inout [Int32]) throws {
        try decodeArray(expectedElemWT: WireType.wireSfixed32, elemAllocBytes: 4) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readSfixed32()) }
        }
    }

    mutating func decodeRepeatedSFixed64Field(value: inout [Int64]) throws {
        try decodeArray(expectedElemWT: WireType.wireSfixed64, elemAllocBytes: 8) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readSfixed64()) }
        }
    }

    mutating func decodeRepeatedBoolField(value: inout [Bool]) throws {
        try decodeArray(expectedElemWT: WireType.wireBoolFalse, elemAllocBytes: 1) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt { value.append(try er.readBoolByte()) }
        }
    }

    mutating func decodeRepeatedStringField(value: inout [String]) throws {
        try decodeArray(expectedElemWT: WireType.wireString, elemAllocBytes: MemoryLayout<String>.stride) { er, cnt, b in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt {
                value.append(try er.readString(budget: &b))
            }
        }
    }

    mutating func decodeRepeatedBytesField(value: inout [Data]) throws {
        try decodeArray(expectedElemWT: WireType.wireBytes, elemAllocBytes: MemoryLayout<Data>.stride) { er, cnt, b in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt {
                let slice = try er.readLenSlice()
                try b.addAlloc(slice.count)
                value.append(Data(slice))
            }
        }
    }

    mutating func decodeRepeatedEnumField<E: SwiftProtobuf.Enum>(value: inout [E]) throws where E.RawValue == Int {
        try decodeArray(expectedElemWT: WireType.wireSint, elemAllocBytes: max(MemoryLayout<E>.stride, 4)) { er, cnt, _ in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt {
                let raw = Int(try er.readSint32())
                value.append(E(rawValue: raw) ?? E())
            }
        }
    }

    mutating func decodeRepeatedMessageField<M: SwiftProtobuf.Message>(value: inout [M]) throws {
        let elemDepth = depth &+ 2
        try decodeArray(expectedElemWT: WireType.wireSubMsg, elemAllocBytes: max(MemoryLayout<M>.stride, 16)) { er, cnt, b in
            try Self.safeReserve(&value, additional: cnt)
            for _ in 0..<cnt {
                guard elemDepth <= b.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(elemDepth)
                }
                let slice = try er.readLenSlice()
                var item = M()
                var subDecoder = OmniBufSwiftDecoder(buffer: slice, depth: elemDepth, budget: b)
                try item.decodeMessage(decoder: &subDecoder)
                try subDecoder.finishUnknownFieldIfAny()
                b = subDecoder.budget
                value.append(item)
            }
        }
    }

    mutating func decodeRepeatedGroupField<G: SwiftProtobuf.Message>(value: inout [G]) throws {
        try decodeRepeatedMessageField(value: &value)
    }

    // MARK: Map Decoders

    mutating func decodeMapField<KeyType, ValueType: SwiftProtobuf.MapValueType>(
        fieldType: SwiftProtobuf._ProtobufMap<KeyType, ValueType>.Type,
        value: inout SwiftProtobuf._ProtobufMap<KeyType, ValueType>.BaseType
    ) throws {
        guard try expectOrSkip(WireType.wireMap) else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let expectedKeyWT = try wireTypeForFieldType(KeyType.self)
        let expectedValWT = try wireTypeForFieldType(ValueType.self)
        let body = try reader.readLenSlice(minLen: 3)
        let (keyWT, valWT, count, mr0) = try OmniBufReader.parseMapBody(body)
        guard keyWT == expectedKeyWT && valWT == expectedValWT else {
            throw OmniBufError.parse("WireMap type mismatch: expected (\(expectedKeyWT),\(expectedValWT)), got (\(keyWT),\(valWT))")
        }
        try budget.addElements(count)
        try budget.addAlloc(count: count, elementBytes: 32)
        var mr = mr0
        for _ in 0..<count {
            let k = try readMapScalar(KeyType.self, from: &mr, budget: &budget)
            let v = try readMapScalar(ValueType.self, from: &mr, budget: &budget)
            value[k] = v
        }
        guard mr.isAtEnd else {
            throw OmniBufError.parse("WireMap trailing bytes")
        }
    }

    mutating func decodeMapField<KeyType, ValueType>(
        fieldType: SwiftProtobuf._ProtobufEnumMap<KeyType, ValueType>.Type,
        value: inout SwiftProtobuf._ProtobufEnumMap<KeyType, ValueType>.BaseType
    ) throws where ValueType.RawValue == Int {
        guard try expectOrSkip(WireType.wireMap) else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let expectedKeyWT = try wireTypeForFieldType(KeyType.self)
        let body = try reader.readLenSlice(minLen: 3)
        let (keyWT, valWT, count, mr0) = try OmniBufReader.parseMapBody(body)
        guard keyWT == expectedKeyWT && valWT == WireType.wireSint else {
            throw OmniBufError.parse("WireMap enum type mismatch")
        }
        try budget.addElements(count)
        try budget.addAlloc(count: count, elementBytes: 32)
        var mr = mr0
        for _ in 0..<count {
            let k = try readMapScalar(KeyType.self, from: &mr, budget: &budget)
            let raw = Int(try mr.readSint32())
            value[k] = ValueType(rawValue: raw) ?? ValueType()
        }
        guard mr.isAtEnd else {
            throw OmniBufError.parse("WireMap trailing bytes")
        }
    }

    mutating func decodeMapField<KeyType, ValueType>(
        fieldType: SwiftProtobuf._ProtobufMessageMap<KeyType, ValueType>.Type,
        value: inout SwiftProtobuf._ProtobufMessageMap<KeyType, ValueType>.BaseType
    ) throws {
        guard try expectOrSkip(WireType.wireMap) else { return }
        let mapDepth = depth &+ 1
        guard mapDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(mapDepth)
        }
        let expectedKeyWT = try wireTypeForFieldType(KeyType.self)
        let body = try reader.readLenSlice(minLen: 3)
        let (keyWT, valWT, count, mr0) = try OmniBufReader.parseMapBody(body)
        guard keyWT == expectedKeyWT && valWT == WireType.wireSubMsg else {
            throw OmniBufError.parse("WireMap message type mismatch")
        }
        try budget.addElements(count)
        try budget.addAlloc(count: count, elementBytes: max(MemoryLayout<ValueType>.stride, 32))
        var mr = mr0
        let valDepth = mapDepth &+ 1
        for _ in 0..<count {
            let k = try readMapScalar(KeyType.self, from: &mr, budget: &budget)
            guard valDepth <= budget.maxDepth else {
                throw OmniBufError.depthLimitExceeded(valDepth)
            }
            let slice = try mr.readLenSlice()
            var sub = ValueType()
            var subDecoder = OmniBufSwiftDecoder(buffer: slice, depth: valDepth, budget: budget)
            try sub.decodeMessage(decoder: &subDecoder)
            try subDecoder.finishUnknownFieldIfAny()
            budget = subDecoder.budget
            value[k] = sub
        }
        guard mr.isAtEnd else {
            throw OmniBufError.parse("WireMap trailing bytes")
        }
    }

    mutating func decodeExtensionField(
        values: inout ExtensionFieldValueSet,
        messageType: any SwiftProtobuf.Message.Type,
        fieldNumber: Int
    ) throws {
        try finishUnknownFieldIfAny()
    }
}

private func readMapScalar<FT: SwiftProtobuf.FieldType>(
    _ fieldType: FT.Type,
    from r: inout OmniBufReader,
    budget: inout DecodeBudget
) throws -> FT.BaseType {
    switch fieldType {
    case is ProtobufUInt32.Type:
        return UInt32(truncatingIfNeeded: try r.readVarint()) as! FT.BaseType
    case is ProtobufUInt64.Type:
        return (try r.readVarint()) as! FT.BaseType
    case is ProtobufInt32.Type, is ProtobufSInt32.Type:
        return (try r.readSint32()) as! FT.BaseType
    case is ProtobufInt64.Type, is ProtobufSInt64.Type:
        return (try r.readSint64()) as! FT.BaseType
    case is ProtobufBool.Type:
        return (try r.readBoolByte()) as! FT.BaseType
    case is ProtobufFixed32.Type:
        return (try r.readFixed32()) as! FT.BaseType
    case is ProtobufFixed64.Type:
        return (try r.readFixed64()) as! FT.BaseType
    case is ProtobufSFixed32.Type:
        return (try r.readSfixed32()) as! FT.BaseType
    case is ProtobufSFixed64.Type:
        return (try r.readSfixed64()) as! FT.BaseType
    case is ProtobufFloat.Type:
        return (try r.readFloat32()) as! FT.BaseType
    case is ProtobufDouble.Type:
        return (try r.readFloat64()) as! FT.BaseType
    case is ProtobufString.Type:
        return (try r.readString(budget: &budget)) as! FT.BaseType
    case is ProtobufBytes.Type:
        let slice = try r.readLenSlice()
        try budget.addAlloc(slice.count)
        return Data(slice) as! FT.BaseType
    default:
        throw OmniBufError.parse("unsupported SwiftProtobuf map scalar \(fieldType)")
    }
}
