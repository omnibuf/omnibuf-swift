/// Core protocol implemented by both generated OmniBuf messages (Tier 1) and
/// native Swift structs using declarative schemas (Tier 3).
public protocol OmniBufMessage: Sendable {
    init()

    /// Encodes the message body (without Field #0) into `writer`.
    func encodeOmniBufBody(into writer: inout OmniBufWriter, options: EncodeOptions) throws

    /// Decodes from `data` in merge mode (leaves omitted fields intact, appends arrays, merges submessages/maps).
    mutating func mergeOmniBuf(
        from data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        budget: inout DecodeBudget
    ) throws

    /// Optional Field #0 `SchemaMeta` for self-describing encoding.
    static var omniBufSchemaMeta: SchemaMeta { get }

    /// Instance-aware Field #0 `SchemaMeta` builder (handles deep recursive types within `maxDepth`).
    func buildInstanceSchemaMeta(depth: Int, maxDepth: Int) -> SchemaMeta
}

extension OmniBufMessage {
    public func buildInstanceSchemaMeta(depth: Int, maxDepth: Int) -> SchemaMeta {
        Self.omniBufSchemaMeta
    }

    /// Encodes this message to OmniBuf wire bytes.
    @inlinable
    public func encodeOmniBuf(options: EncodeOptions = .default) throws -> [UInt8] {
        var writer = OmniBufWriter(initialCapacity: 256)
        if options.selfDescribing {
            buildInstanceSchemaMeta(depth: 1, maxDepth: WireType.maxNestingDepth).appendField0(to: &writer)
        }
        try encodeOmniBufBody(into: &writer, options: options)
        return writer.toBytes()
    }

    /// Replaces `self` by resetting to defaults and decoding `bytes` (replace mode).
    @inlinable
    public mutating func decodeOmniBuf(
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws {
        guard bytes.count <= options.maxMessageBytes else {
            throw OmniBufError.allocationLimitExceeded(
                "message length \(bytes.count) exceeds maxMessageBytes \(options.maxMessageBytes)"
            )
        }
        var fresh = Self()
        var budget = DecodeBudget(options: options)
        try bytes.withUnsafeBufferPointer { buf in
            try fresh.mergeOmniBuf(from: buf, depth: 0, budget: &budget)
        }
        self = fresh
    }

    /// Merges `bytes` into `self` (merge mode: preserves omitted fields, appends arrays, merges maps/submessages).
    @inlinable
    public mutating func mergeOmniBuf(
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
            try self.mergeOmniBuf(from: buf, depth: 0, budget: &budget)
        }
    }

    /// Decodes a new instance from `bytes`.
    @inlinable
    public static func decoded(
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws -> Self {
        var msg = Self()
        try msg.decodeOmniBuf(from: bytes, options: options)
        return msg
    }
}

/// Top-level convenience namespace for encoding and decoding `OmniBufMessage` types.
public enum OmniBuf {
    @inlinable
    public static func encode<T: OmniBufMessage>(
        _ value: T,
        options: EncodeOptions = .default
    ) throws -> [UInt8] {
        try value.encodeOmniBuf(options: options)
    }

    @inlinable
    public static func decode<T: OmniBufMessage>(
        _ type: T.Type = T.self,
        from bytes: [UInt8],
        options: DecodeOptions = .default
    ) throws -> T {
        try T.decoded(from: bytes, options: options)
    }
}

// MARK: - Indirect Box for Recursive Structs (e.g. TreeNode)

/// Value-semantic copy-on-write heap box enabling recursive Swift structs (such as `TreeNode`).
public struct Indirect<T: Sendable>: Sendable {
    private final class Storage: @unchecked Sendable {
        var value: T
        init(_ value: T) {
            self.value = value
        }
    }

    private var storage: Storage

    public init(_ value: T) {
        self.storage = Storage(value)
    }

    public var value: T {
        get { storage.value }
        set {
            if !isKnownUniquelyReferenced(&storage) {
                storage = Storage(newValue)
            } else {
                storage.value = newValue
            }
        }
    }
}

extension Indirect: Equatable where T: Equatable {
    public static func == (lhs: Indirect<T>, rhs: Indirect<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Indirect: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - Tier 3: Declarative Schema Mapping for Native Swift Structs

/// A single typed field codec binding a Swift struct property to an OmniBuf field number.
public struct OmniBufFieldCodec<Root: Sendable>: @unchecked Sendable {
    public let fieldNumber: UInt32
    public let name: String
    public let childMeta: ((Set<String>) -> SchemaMeta)?
    public let instanceChildMeta: ((Root, Int, Int) -> SchemaMeta?)?
    public let encode: (Root, inout OmniBufWriter, EncodeOptions) throws -> Void
    public let decode: (inout Root, inout OmniBufReader, UInt8, Int, inout DecodeBudget) throws -> Void

    public init(
        fieldNumber: UInt32,
        name: String,
        childMeta: ((Set<String>) -> SchemaMeta)? = nil,
        instanceChildMeta: ((Root, Int, Int) -> SchemaMeta?)? = nil,
        encode: @escaping (Root, inout OmniBufWriter, EncodeOptions) throws -> Void,
        decode: @escaping (inout Root, inout OmniBufReader, UInt8, Int, inout DecodeBudget) throws -> Void
    ) {
        self.fieldNumber = fieldNumber
        self.name = name
        self.childMeta = childMeta
        self.instanceChildMeta = instanceChildMeta
        self.encode = encode
        self.decode = decode
    }
}

/// Declarative schema binding a plain Swift struct to OmniBuf wire fields (Tier 3).
///
/// Conforming a struct to `OmniBufStruct` requires only `init()` and `static var omniBufSchema`.
public protocol OmniBufStruct: OmniBufMessage {
    static var omniBufSchema: OmniBufStructSchema<Self> { get }
}

extension OmniBufStruct {
    public func encodeOmniBufBody(into writer: inout OmniBufWriter, options: EncodeOptions) throws {
        try Self.omniBufSchema.encode(self, into: &writer, options: options)
    }

    public mutating func mergeOmniBuf(
        from data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        budget: inout DecodeBudget
    ) throws {
        try Self.omniBufSchema.merge(&self, from: data, depth: depth, budget: &budget)
    }

    public static var omniBufSchemaMeta: SchemaMeta {
        Self.omniBufSchema.buildSchemaMeta(visited: [])
    }

    public static func buildOmniBufSchemaMeta(visited: Set<String>) -> SchemaMeta {
        Self.omniBufSchema.buildSchemaMeta(visited: visited)
    }

    public func buildInstanceSchemaMeta(depth: Int, maxDepth: Int) -> SchemaMeta {
        Self.omniBufSchema.buildInstanceSchemaMeta(for: self, depth: depth, maxDepth: maxDepth)
    }
}

/// Runtime-compiled declarative schema for a Swift struct.
public final class OmniBufStructSchema<Root: Sendable>: @unchecked Sendable {
    public let typeName: String
    public let fields: [OmniBufFieldCodec<Root>]
    private let byFieldNumber: [UInt32: OmniBufFieldCodec<Root>]

    public init(typeName: String, fields: [OmniBufFieldCodec<Root>]) {
        self.typeName = typeName
        let sorted = fields.sorted { $0.fieldNumber < $1.fieldNumber }
        self.fields = sorted
        var lookup: [UInt32: OmniBufFieldCodec<Root>] = [:]
        lookup.reserveCapacity(sorted.count)
        for f in sorted {
            lookup[f.fieldNumber] = f
        }
        self.byFieldNumber = lookup
    }

    public func buildSchemaMeta(visited: Set<String>) -> SchemaMeta {
        var fieldNames: [UInt32: String] = [:]
        var children: [UInt32: SchemaMeta] = [:]
        let isCycle = visited.contains(typeName)
        var nextVisited = visited
        nextVisited.insert(typeName)

        for f in fields {
            fieldNames[f.fieldNumber] = f.name
            if !isCycle, let childFn = f.childMeta {
                children[f.fieldNumber] = childFn(nextVisited)
            }
        }
        return SchemaMeta(typeName: typeName, fields: fieldNames, children: children)
    }

    public func buildInstanceSchemaMeta(for value: Root, depth: Int, maxDepth: Int) -> SchemaMeta {
        var fieldNames: [UInt32: String] = [:]
        var children: [UInt32: SchemaMeta] = [:]
        // Each children hop adds +2 to SchemaMeta depth (children map = +1, child SchemaMeta = +2),
        // and the child's fields map needs +1 more, so require depth + 3 <= maxDepth.
        let canRecurse = (depth &+ 3) <= maxDepth
        for f in fields {
            fieldNames[f.fieldNumber] = f.name
            if canRecurse, let instFn = f.instanceChildMeta,
               let child = instFn(value, depth &+ 2, maxDepth) {
                children[f.fieldNumber] = child
            }
        }
        return SchemaMeta(typeName: typeName, fields: fieldNames, children: children)
    }

    public func encode(
        _ value: Root,
        into writer: inout OmniBufWriter,
        options: EncodeOptions
    ) throws {
        for field in fields {
            try field.encode(value, &writer, options)
        }
    }

    public func merge(
        _ target: inout Root,
        from data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        budget: inout DecodeBudget
    ) throws {
        guard depth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(depth)
        }
        var r = OmniBufReader(data)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            if fnum == 0 {
                guard wt == WireType.wireSubMsg else {
                    throw OmniBufError.parse("Field #0 must have WireSubMsg (12), got \(wt)")
                }
                let slice = try r.readLenSlice()
                _ = try SchemaMeta.validateSlice(slice, depth: depth &+ 1, maxDepth: budget.maxDepth)
                continue
            }
            if let codec = byFieldNumber[fnum] {
                try codec.decode(&target, &r, wt, depth, &budget)
            } else {
                try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
            }
        }
    }
}

// MARK: - Declarative Field Builders for OmniBufStructSchema

public enum Field {
    public static func uint32<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, UInt32>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireUint)
                    w.appendVarint(UInt64(v))
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireUint else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = UInt32(truncatingIfNeeded: try r.readVarint())
            }
        )
    }

    public static func uint64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, UInt64>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireUint)
                    w.appendVarint(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireUint else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readVarint()
            }
        )
    }

    public static func sint32<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Int32>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireSint)
                    w.appendZigZag32(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSint else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readSint32()
            }
        )
    }

    public static func sint64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Int64>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireSint)
                    w.appendZigZag(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSint else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readSint64()
            }
        )
    }

    public static func bool<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Bool>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                if root[keyPath: kp] {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireBoolTrue)
                }
            },
            decode: { root, r, wt, depth, budget in
                if wt == WireType.wireBoolFalse {
                    root[keyPath: kp] = false
                } else if wt == WireType.wireBoolTrue {
                    root[keyPath: kp] = true
                } else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                }
            }
        )
    }

    public static func fixed32<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, UInt32>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireFixed32)
                    w.appendFixed32(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireFixed32 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readFixed32()
            }
        )
    }

    public static func fixed64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, UInt64>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireFixed64)
                    w.appendFixed64(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireFixed64 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readFixed64()
            }
        )
    }

    public static func sfixed32<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Int32>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireSfixed32)
                    w.appendSfixed32(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSfixed32 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readSfixed32()
            }
        )
    }

    public static func sfixed64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Int64>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireSfixed64)
                    w.appendSfixed64(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSfixed64 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readSfixed64()
            }
        )
    }

    public static func float32<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Float>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v.bitPattern != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireFloat32)
                    w.appendFloat32(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireFloat32 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readFloat32()
            }
        )
    }

    public static func float64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Double>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if v.bitPattern != 0 {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireFloat64)
                    w.appendFloat64(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireFloat64 else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                root[keyPath: kp] = try r.readFloat64()
            }
        )
    }

    public static func string<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, String>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if !v.isEmpty {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireString)
                    w.appendStringValue(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireString else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let s = try r.readString()
                try budget.addAlloc(s.utf8.count)
                root[keyPath: kp] = s
            }
        )
    }

    public static func bytes<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, [UInt8]>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let v = root[keyPath: kp]
                if !v.isEmpty {
                    w.appendTag(fieldNumber: id, wireType: WireType.wireBytes)
                    w.appendBytes(v)
                }
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireBytes else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let b = try r.readBytes()
                try budget.addAlloc(b.count)
                root[keyPath: kp] = b
            }
        )
    }

    public static func message<Root: Sendable, Child: OmniBufMessage>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Child?>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            childMeta: { visited in
                if let sType = Child.self as? any OmniBufStruct.Type {
                    return sType.buildOmniBufSchemaMeta(visited: visited)
                }
                return Child.omniBufSchemaMeta
            },
            instanceChildMeta: { root, depth, maxDepth in
                guard let child = root[keyPath: kp] else { return nil }
                return child.buildInstanceSchemaMeta(depth: depth, maxDepth: maxDepth)
            },
            encode: { root, w, opts in
                guard let child = root[keyPath: kp] else { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireSubMsg)
                let lenPos = w.reserveLength2()
                try child.encodeOmniBufBody(into: &w, options: opts)
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSubMsg else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let slice = try r.readLenSlice()
                var child = root[keyPath: kp] ?? Child()
                try child.mergeOmniBuf(from: slice, depth: nextDepth, budget: &budget)
                root[keyPath: kp] = child
            }
        )
    }

    public static func indirectMessage<Root: Sendable, Child: OmniBufMessage>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, Indirect<Child>?>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            childMeta: { visited in
                if let sType = Child.self as? any OmniBufStruct.Type {
                    return sType.buildOmniBufSchemaMeta(visited: visited)
                }
                return Child.omniBufSchemaMeta
            },
            instanceChildMeta: { root, depth, maxDepth in
                guard let box = root[keyPath: kp] else { return nil }
                return box.value.buildInstanceSchemaMeta(depth: depth, maxDepth: maxDepth)
            },
            encode: { root, w, opts in
                guard let box = root[keyPath: kp] else { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireSubMsg)
                let lenPos = w.reserveLength2()
                try box.value.encodeOmniBufBody(into: &w, options: opts)
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireSubMsg else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let slice = try r.readLenSlice()
                var child = root[keyPath: kp]?.value ?? Child()
                try child.mergeOmniBuf(from: slice, depth: nextDepth, budget: &budget)
                root[keyPath: kp] = Indirect(child)
            }
        )
    }

    public static func stringArray<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, [String]>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let arr = root[keyPath: kp]
                guard !arr.isEmpty else { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireArray)
                let lenPos = w.reserveLength2()
                w.appendByte(WireType.wireString)
                w.appendVarint(UInt64(arr.count))
                for s in arr {
                    w.appendStringValue(s)
                }
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireArray else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let body = try r.readLenSlice(minLen: 2)
                let (elemWT, count, er0) = try OmniBufReader.parseArrayBody(body)
                guard elemWT == WireType.wireString else {
                    throw OmniBufError.parse("field \(id) expected WireString array, got element type \(elemWT)")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: MemoryLayout<String>.stride)
                let (newCap, capOverflow) = root[keyPath: kp].count.addingReportingOverflow(count)
                if capOverflow {
                    throw OmniBufError.allocationLimitExceeded("array capacity overflow")
                }
                var er = er0
                root[keyPath: kp].reserveCapacity(newCap)
                for _ in 0..<count {
                    let s = try er.readString()
                    try budget.addAlloc(s.utf8.count)
                    root[keyPath: kp].append(s)
                }
                guard er.isAtEnd else {
                    throw OmniBufError.parse("WireArray trailing bytes")
                }
            }
        )
    }

    public static func uint32Array<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, [UInt32]>
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, _ in
                let arr = root[keyPath: kp]
                guard !arr.isEmpty else { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireArray)
                let lenPos = w.reserveLength2()
                w.appendByte(WireType.wireUint)
                w.appendVarint(UInt64(arr.count))
                for v in arr {
                    w.appendVarint(UInt64(v))
                }
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireArray else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let body = try r.readLenSlice(minLen: 2)
                let (elemWT, count, er0) = try OmniBufReader.parseArrayBody(body)
                guard elemWT == WireType.wireUint else {
                    throw OmniBufError.parse("field \(id) expected WireUint array, got element type \(elemWT)")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: 4)
                let (newCap, capOverflow) = root[keyPath: kp].count.addingReportingOverflow(count)
                if capOverflow {
                    throw OmniBufError.allocationLimitExceeded("array capacity overflow")
                }
                var er = er0
                root[keyPath: kp].reserveCapacity(newCap)
                for _ in 0..<count {
                    root[keyPath: kp].append(UInt32(truncatingIfNeeded: try er.readVarint()))
                }
                guard er.isAtEnd else {
                    throw OmniBufError.parse("WireArray trailing bytes")
                }
            }
        )
    }

    public static func messageArray<Root: Sendable, Child: OmniBufMessage>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, [Child]>, omitEmpty: Bool = true
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            childMeta: { visited in
                if let sType = Child.self as? any OmniBufStruct.Type {
                    return sType.buildOmniBufSchemaMeta(visited: visited)
                }
                return Child.omniBufSchemaMeta
            },
            instanceChildMeta: { root, depth, maxDepth in
                let arr = root[keyPath: kp]
                guard !arr.isEmpty else { return nil }
                var merged = arr[0].buildInstanceSchemaMeta(depth: depth, maxDepth: maxDepth)
                for item in arr.dropFirst() {
                    merged.merge(from: item.buildInstanceSchemaMeta(depth: depth, maxDepth: maxDepth))
                }
                return merged
            },
            encode: { root, w, opts in
                let arr = root[keyPath: kp]
                if omitEmpty && arr.isEmpty { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireArray)
                let lenPos = w.reserveLength2()
                w.appendByte(WireType.wireSubMsg)
                w.appendVarint(UInt64(arr.count))
                for item in arr {
                    let elemLenPos = w.reserveLength2()
                    try item.encodeOmniBufBody(into: &w, options: opts)
                    w.backpatchLength2(at: elemLenPos)
                }
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireArray else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let arrDepth = depth &+ 1
                guard arrDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(arrDepth)
                }
                let body = try r.readLenSlice(minLen: 2)
                let (elemWT, count, er0) = try OmniBufReader.parseArrayBody(body)
                guard elemWT == WireType.wireSubMsg else {
                    throw OmniBufError.parse("field \(id) expected WireSubMsg array, got element type \(elemWT)")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: max(MemoryLayout<Child>.stride, 16))
                let (newCap, capOverflow) = root[keyPath: kp].count.addingReportingOverflow(count)
                if capOverflow {
                    throw OmniBufError.allocationLimitExceeded("array capacity overflow")
                }
                var er = er0
                root[keyPath: kp].reserveCapacity(newCap)
                let elemDepth = arrDepth &+ 1
                for _ in 0..<count {
                    guard elemDepth <= budget.maxDepth else {
                        throw OmniBufError.depthLimitExceeded(elemDepth)
                    }
                    let slice = try er.readLenSlice()
                    var item = Child()
                    try item.mergeOmniBuf(from: slice, depth: elemDepth, budget: &budget)
                    root[keyPath: kp].append(item)
                }
                guard er.isAtEnd else {
                    throw OmniBufError.parse("WireArray trailing bytes")
                }
            }
        )
    }

    public static func mapStringUint64<Root: Sendable>(
        _ id: UInt32, _ name: String, _ kp: WritableKeyPath<Root, [String: UInt64]>, omitEmpty: Bool = true
    ) -> OmniBufFieldCodec<Root> {
        OmniBufFieldCodec(
            fieldNumber: id,
            name: name,
            encode: { root, w, opts in
                let map = root[keyPath: kp]
                if omitEmpty && map.isEmpty { return }
                w.appendTag(fieldNumber: id, wireType: WireType.wireMap)
                let lenPos = w.reserveLength2()
                w.appendTwoBytes(WireType.wireString, WireType.wireUint)
                w.appendVarint(UInt64(map.count))
                if opts.deterministic {
                    for k in map.keys.sorted(by: compareUTF8Bytes) {
                        w.appendStringValue(k)
                        w.appendVarint(map[k]!)
                    }
                } else {
                    for (k, v) in map {
                        w.appendStringValue(k)
                        w.appendVarint(v)
                    }
                }
                w.backpatchLength2(at: lenPos)
            },
            decode: { root, r, wt, depth, budget in
                guard wt == WireType.wireMap else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
                    return
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let body = try r.readLenSlice(minLen: 3)
                let (keyWT, valWT, count, mr0) = try OmniBufReader.parseMapBody(body)
                guard keyWT == WireType.wireString && valWT == WireType.wireUint else {
                    throw OmniBufError.parse("field \(id) expected map<string, uint64>, got (\(keyWT), \(valWT))")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: 32)
                var mr = mr0
                for _ in 0..<count {
                    let k = try mr.readString()
                    try budget.addAlloc(k.utf8.count)
                    let v = try mr.readVarint()
                    root[keyPath: kp][k] = v
                }
                guard mr.isAtEnd else {
                    throw OmniBufError.parse("WireMap trailing bytes")
                }
            }
        )
    }
}
