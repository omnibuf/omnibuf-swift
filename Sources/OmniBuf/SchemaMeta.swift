/// Optional inline schema header encoded as Field #0 (`Tag = 0x19`, `WireSubMsg = 12`)
/// inside an OmniBuf message (`omnibuf.v1.SchemaMeta`).
public struct SchemaMeta: Equatable, Sendable {
    public var typeName: String
    public var fields: [UInt32: String]
    public var children: [UInt32: SchemaMeta]

    public init(
        typeName: String = "",
        fields: [UInt32: String] = [:],
        children: [UInt32: SchemaMeta] = [:]
    ) {
        self.typeName = typeName
        self.fields = fields
        self.children = children
    }

    /// Appends Field #0 (`Tag = 0x19`, `WireSubMsg = 12`) encoding `self` to `writer` deterministically.
    public func appendField0(to writer: inout OmniBufWriter) {
        writer.appendByte(WireType.field0TagByte)
        let lenPos = writer.reserveLength2()
        appendBody(to: &writer)
        writer.backpatchLength2(at: lenPos)
    }

    /// Encodes Field #0 into a new byte array.
    public func encodeField0() -> [UInt8] {
        var writer = OmniBufWriter(initialCapacity: 128)
        appendField0(to: &writer)
        return writer.toBytes()
    }

    private func appendBody(to writer: inout OmniBufWriter) {
        // Field #1: type_name (WireString = 10 -> Tag 0x35)
        if !typeName.isEmpty {
            writer.appendByte(0x35)
            writer.appendStringValue(typeName)
        }
        // Field #2: fields map<uint32, string> (WireMap = 14 -> Tag 0x5D)
        if !fields.isEmpty {
            writer.appendByte(0x5D)
            let lenPos = writer.reserveLength2()
            writer.appendTwoBytes(WireType.wireUint, WireType.wireString)
            writer.appendVarint(UInt64(fields.count))
            for key in fields.keys.sorted() {
                writer.appendVarint(UInt64(key))
                writer.appendStringValue(fields[key]!)
            }
            writer.backpatchLength2(at: lenPos)
        }
        // Field #3: children map<uint32, SchemaMeta> (WireMap = 14 -> Tag 0x7D)
        if !children.isEmpty {
            writer.appendByte(0x7D)
            let lenPos = writer.reserveLength2()
            writer.appendTwoBytes(WireType.wireUint, WireType.wireSubMsg)
            writer.appendVarint(UInt64(children.count))
            for key in children.keys.sorted() {
                writer.appendVarint(UInt64(key))
                let childLenPos = writer.reserveLength2()
                children[key]!.appendBody(to: &writer)
                writer.backpatchLength2(at: childLenPos)
            }
            writer.backpatchLength2(at: lenPos)
        }
    }

    /// Merges `next` into `self` (later non-empty `typeName` wins, `fields` override per field number,
    /// and `children` merge recursively by field number).
    public mutating func merge(from next: SchemaMeta) {
        if !next.typeName.isEmpty {
            typeName = next.typeName
        }
        for (k, v) in next.fields {
            fields[k] = v
        }
        for (k, child) in next.children {
            if var existing = children[k] {
                existing.merge(from: child)
                children[k] = existing
            } else {
                children[k] = child
            }
        }
    }

    private static let fieldEntryOverhead = 64
    private static let childEntryOverhead = 96

    /// Validates a `SchemaMeta` payload slice in place with zero heap allocations,
    /// enforcing `maxDepth`, `maxElements`, and `maxAllocBytes` via `budget`.
    public static func validateSlice(
        _ data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        budget: inout DecodeBudget
    ) throws {
        guard depth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(depth)
        }
        var r = OmniBufReader(data)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            switch fnum {
            case 1:
                guard wt == WireType.wireString else {
                    throw OmniBufError.parse("SchemaMeta field #1 (type_name) must be WireString, got \(wt)")
                }
                let slice = try r.readLenSlice()
                try budget.addAlloc(slice.count)
                if let ptr = slice.baseAddress, !slice.isEmpty {
                    guard isValidUTF8(ptr, count: slice.count) else {
                        throw OmniBufError.parse("invalid UTF-8 in SchemaMeta type_name")
                    }
                }
            case 2:
                guard wt == WireType.wireMap else {
                    throw OmniBufError.parse("SchemaMeta field #2 (fields) must be WireMap, got \(wt)")
                }
                guard depth &+ 1 <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(depth &+ 1)
                }
                let body = try r.readLenSlice(minLen: 3)
                let (keyWT, valWT, count, mapReader) = try OmniBufReader.parseMapBody(body)
                guard keyWT == WireType.wireUint && valWT == WireType.wireString else {
                    throw OmniBufError.parse("SchemaMeta fields map must have uint->string types")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: fieldEntryOverhead)
                var mr = mapReader
                for _ in 0..<count {
                    let k64 = try mr.readVarint()
                    guard k64 > 0 && k64 <= WireType.maxFieldNumber else {
                        throw OmniBufError.parse("invalid SchemaMeta field number \(k64)")
                    }
                    let nameSlice = try mr.readLenSlice()
                    try budget.addAlloc(nameSlice.count)
                    if let ptr = nameSlice.baseAddress, !nameSlice.isEmpty {
                        guard isValidUTF8(ptr, count: nameSlice.count) else {
                            throw OmniBufError.parse("invalid UTF-8 in SchemaMeta field name")
                        }
                    }
                }
                guard mr.isAtEnd else {
                    throw OmniBufError.parse("SchemaMeta fields map trailing bytes")
                }
            case 3:
                guard wt == WireType.wireMap else {
                    throw OmniBufError.parse("SchemaMeta field #3 (children) must be WireMap, got \(wt)")
                }
                guard depth &+ 1 <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(depth &+ 1)
                }
                let body = try r.readLenSlice(minLen: 3)
                let (keyWT, valWT, count, mapReader) = try OmniBufReader.parseMapBody(body)
                guard keyWT == WireType.wireUint && valWT == WireType.wireSubMsg else {
                    throw OmniBufError.parse("SchemaMeta children map must have uint->submsg types")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: childEntryOverhead)
                var mr = mapReader
                for _ in 0..<count {
                    let k64 = try mr.readVarint()
                    guard k64 > 0 && k64 <= WireType.maxFieldNumber else {
                        throw OmniBufError.parse("invalid SchemaMeta child field number \(k64)")
                    }
                    let childSlice = try mr.readLenSlice()
                    try validateSlice(childSlice, depth: depth &+ 2, budget: &budget)
                }
                guard mr.isAtEnd else {
                    throw OmniBufError.parse("SchemaMeta children map trailing bytes")
                }
            case 0:
                throw OmniBufError.parse("invalid Field #0 inside SchemaMeta")
            default:
                try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
            }
        }
    }

    /// Validates a `SchemaMeta` payload slice in place with zero heap allocations using default element/allocation limits.
    @discardableResult
    public static func validateSlice(
        _ data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        maxDepth: Int = WireType.maxNestingDepth
    ) throws -> Int {
        var budget = DecodeBudget(options: DecodeOptions(maxDepth: maxDepth))
        try validateSlice(data, depth: depth, budget: &budget)
        return budget.allocBytes
    }

    /// Decodes a `SchemaMeta` payload slice enforcing depth and allocation budget.
    public static func decodeSlice(
        _ data: UnsafeBufferPointer<UInt8>,
        depth: Int,
        budget: inout DecodeBudget
    ) throws -> SchemaMeta {
        guard depth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(depth)
        }
        var meta = SchemaMeta()
        var r = OmniBufReader(data)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            switch fnum {
            case 1:
                guard wt == WireType.wireString else {
                    throw OmniBufError.parse("SchemaMeta field #1 (type_name) must be WireString, got \(wt)")
                }
                meta.typeName = try r.readString(budget: &budget)
            case 2:
                guard wt == WireType.wireMap else {
                    throw OmniBufError.parse("SchemaMeta field #2 (fields) must be WireMap, got \(wt)")
                }
                guard depth &+ 1 <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(depth &+ 1)
                }
                let body = try r.readLenSlice(minLen: 3)
                let (keyWT, valWT, count, mapReader) = try OmniBufReader.parseMapBody(body)
                guard keyWT == WireType.wireUint && valWT == WireType.wireString else {
                    throw OmniBufError.parse("SchemaMeta fields map must have uint->string types")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: fieldEntryOverhead)
                var mr = mapReader
                for _ in 0..<count {
                    let k64 = try mr.readVarint()
                    guard k64 > 0 && k64 <= WireType.maxFieldNumber else {
                        throw OmniBufError.parse("invalid SchemaMeta field number \(k64)")
                    }
                    let name = try mr.readString(budget: &budget)
                    meta.fields[UInt32(k64)] = name
                }
                guard mr.isAtEnd else {
                    throw OmniBufError.parse("SchemaMeta fields map trailing bytes")
                }
            case 3:
                guard wt == WireType.wireMap else {
                    throw OmniBufError.parse("SchemaMeta field #3 (children) must be WireMap, got \(wt)")
                }
                guard depth &+ 1 <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(depth &+ 1)
                }
                let body = try r.readLenSlice(minLen: 3)
                let (keyWT, valWT, count, mapReader) = try OmniBufReader.parseMapBody(body)
                guard keyWT == WireType.wireUint && valWT == WireType.wireSubMsg else {
                    throw OmniBufError.parse("SchemaMeta children map must have uint->submsg types")
                }
                try budget.addElements(count)
                try budget.addAlloc(count: count, elementBytes: childEntryOverhead)
                var mr = mapReader
                for _ in 0..<count {
                    let k64 = try mr.readVarint()
                    guard k64 > 0 && k64 <= WireType.maxFieldNumber else {
                        throw OmniBufError.parse("invalid SchemaMeta child field number \(k64)")
                    }
                    let childSlice = try mr.readLenSlice()
                    let child = try decodeSlice(childSlice, depth: depth &+ 2, budget: &budget)
                    let key = UInt32(k64)
                    meta.children[key] = child
                }
                guard mr.isAtEnd else {
                    throw OmniBufError.parse("SchemaMeta children map trailing bytes")
                }
            case 0:
                throw OmniBufError.parse("invalid Field #0 inside SchemaMeta")
            default:
                try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)
            }
        }
        return meta
    }
}
