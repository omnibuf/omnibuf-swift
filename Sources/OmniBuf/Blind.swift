/// Dynamic value returned by schema-less `decodeBlind` packet inspection (Tier 4).
public enum BlindValue: Equatable, Sendable {
    case bool(Bool)
    case uint(UInt64)
    case int(Int64)
    case float32(Float)
    case float64(Double)
    case string(String)
    case bytes([UInt8])
    case array([BlindValue])
    case object([String: BlindValue])
}

/// Options controlling `decodeBlind`.
public struct DecodeBlindOptions: Sendable {
    public var inheritedSchema: SchemaMeta?
    public var decodeOptions: DecodeOptions

    public init(inheritedSchema: SchemaMeta? = nil, decodeOptions: DecodeOptions = .default) {
        self.inheritedSchema = inheritedSchema
        self.decodeOptions = decodeOptions
    }

    public static let `default` = DecodeBlindOptions()
}

/// Decodes any OmniBuf packet without a compile-time schema.
///
/// Resolves Field #0 (`omnibuf.v1.SchemaMeta`) field names across nested sub-messages,
/// arrays of sub-messages, and map values. Unnamed fields fall back to `"field_<N>"`.
public func decodeBlind(
    _ packet: [UInt8],
    options: DecodeBlindOptions = .default
) throws -> [String: BlindValue] {
    guard packet.count <= options.decodeOptions.maxMessageBytes else {
        throw OmniBufError.allocationLimitExceeded(
            "message length \(packet.count) exceeds maxMessageBytes \(options.decodeOptions.maxMessageBytes)"
        )
    }
    var budget = DecodeBudget(options: options.decodeOptions)
    return try packet.withUnsafeBufferPointer { buf in
        var layers: [SchemaMeta] = []
        if let inherited = options.inheritedSchema {
            layers.append(inherited)
        }
        return try decodeBlindObject(buf, inheritedLayers: layers, depth: 0, budget: &budget)
    }
}

/// Decodes `packet` without a schema and serializes the result to canonical JSON.
///
/// Throws `OmniBufError.serialize` if the packet contains `NaN` or `Infinity`.
public func decodeBlindJSON(
    _ packet: [UInt8],
    options: DecodeBlindOptions = .default
) throws -> String {
    let map = try decodeBlind(packet, options: options)
    var out = ""
    out.reserveCapacity(map.count * 24 + 2)
    var hasNonFinite = false
    serializeBlindObject(&out, map, step: "", curIndent: "", hasNonFinite: &hasNonFinite)
    if hasNonFinite {
        throw OmniBufError.serialize("non-finite floating-point value cannot be represented in JSON")
    }
    return out
}

/// Formats a blind-decoded dictionary as canonical JSON.
public func stringifyBlindJSON(
    _ map: [String: BlindValue],
    indent: Int? = nil,
    fallbackOnNonFinite: Bool = false
) -> String {
    let step = (indent ?? 0) > 0 ? String(repeating: " ", count: min(indent!, 10)) : ""
    var out = ""
    out.reserveCapacity(map.count * 24 + 2)
    var hasNonFinite = false
    serializeBlindObject(&out, map, step: step, curIndent: "", hasNonFinite: &hasNonFinite)
    if hasNonFinite && fallbackOnNonFinite {
        return "{}"
    }
    return out
}

// MARK: - Internal Blind Shape Consistency & Decoder

private indirect enum BlindShape: Equatable {
    case scalar(UInt8)
    case array(elemType: UInt8, elemShape: BlindShape?)
    case map(keyType: UInt8, valType: UInt8, valShape: BlindShape?)
}

private func normalizeWireType(_ wt: UInt8) -> UInt8 {
    wt == WireType.wireBoolTrue ? WireType.wireBoolFalse : wt
}

private func unifyShapes(_ a: BlindShape?, _ b: BlindShape?) -> BlindShape? {
    guard let sa = a else { return b }
    guard let sb = b else { return sa }
    switch (sa, sb) {
    case (.scalar(let wa), .scalar(let wb)):
        return wa == wb ? sa : nil
    case (.array(let ea, let subA), .array(let eb, let subB)):
        guard ea == eb else { return nil }
        if subA == nil && subB == nil {
            return .array(elemType: ea, elemShape: nil)
        }
        guard let unified = unifyShapes(subA, subB) else { return nil }
        return .array(elemType: ea, elemShape: unified)
    case (.map(let ka, let va, let subA), .map(let kb, let vb, let subB)):
        guard ka == kb && va == vb else { return nil }
        if subA == nil && subB == nil {
            return .map(keyType: ka, valType: va, valShape: nil)
        }
        guard let unified = unifyShapes(subA, subB) else { return nil }
        return .map(keyType: ka, valType: va, valShape: unified)
    default:
        return nil
    }
}

private func resolveFieldName(_ fieldNumber: UInt32, layers: [SchemaMeta]) -> String {
    for layer in layers.reversed() {
        if let name = layer.fields[fieldNumber] {
            return name
        }
    }
    return ""
}

private func resolveChildLayers(_ fieldNumber: UInt32, layers: [SchemaMeta]) -> [SchemaMeta] {
    var out: [SchemaMeta] = []
    for layer in layers {
        if let child = layer.children[fieldNumber] {
            out.append(child)
        }
    }
    return out
}

private func decodeBlindObject(
    _ data: UnsafeBufferPointer<UInt8>,
    inheritedLayers: [SchemaMeta],
    depth: Int,
    budget: inout DecodeBudget
) throws -> [String: BlindValue] {
    try decodeBlindSegments([data], inheritedLayers: inheritedLayers, depth: depth, budget: &budget)
}

private func decodeBlindSegments(
    _ segments: [UnsafeBufferPointer<UInt8>],
    inheritedLayers: [SchemaMeta],
    depth: Int,
    budget: inout DecodeBudget
) throws -> [String: BlindValue] {
    guard depth <= budget.maxDepth else {
        throw OmniBufError.depthLimitExceeded(depth)
    }

    // Pass 1: Extract and merge all Field #0 SchemaMeta blocks across all segments at this level.
    // Every segment MUST be structurally valid on its own (no split tags/payloads across segments).
    var localMeta: SchemaMeta? = nil
    for seg in segments {
        var r = OmniBufReader(seg)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            if fnum == 0 {
                guard wt == WireType.wireSubMsg else {
                    throw OmniBufError.parse("Field #0 must have WireSubMsg (12), got \(wt)")
                }
                let slice = try r.readLenSlice()
                let meta = try SchemaMeta.decodeSlice(slice, depth: depth &+ 1, budget: &budget)
                if var existing = localMeta {
                    existing.merge(from: meta)
                    localMeta = existing
                } else {
                    localMeta = meta
                }
            } else {
                try r.skipValue(wireType: wt)
            }
        }
    }

    var effectiveLayers = inheritedLayers
    if let lm = localMeta {
        effectiveLayers.append(lm)
    }

    // Pass 2: Decode all fields merging by numeric field number and enforcing shape consistency.
    var fieldOrder: [UInt32] = []
    var seenFields = Set<UInt32>()
    var fieldShapes: [UInt32: BlindShape] = [:]
    var numericMap: [UInt32: BlindValue] = [:]
    var subMsgSegments: [UInt32: [UnsafeBufferPointer<UInt8>]] = [:]

    for seg in segments {
        var r = OmniBufReader(seg)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            if fnum == 0 {
                _ = try r.readLenSlice()
                continue
            }
            if !seenFields.contains(fnum) {
                try budget.addElements(1)
                try budget.addAlloc(64)
                seenFields.insert(fnum)
                fieldOrder.append(fnum)
            }

            if wt == WireType.wireSubMsg {
                let nextDepth = depth &+ 1
                guard nextDepth <= budget.maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let incomingShape = BlindShape.scalar(WireType.wireSubMsg)
                if let prevShape = fieldShapes[fnum] {
                    guard unifyShapes(prevShape, incomingShape) != nil else {
                        throw OmniBufError.parse("conflicting wire shape for field #\(fnum)")
                    }
                } else {
                    fieldShapes[fnum] = incomingShape
                }
                let slice = try r.readLenSlice()
                try budget.addElements(1)
                try budget.addAlloc(16)
                subMsgSegments[fnum, default: []].append(slice)
                continue
            }

            let childLayers = resolveChildLayers(fnum, layers: effectiveLayers)
            let (decoded, incomingShape) = try decodeBlindValue(
                reader: &r,
                wireType: wt,
                inCollection: false,
                childLayers: childLayers,
                depth: depth,
                budget: &budget
            )

            if let prevShape = fieldShapes[fnum] {
                guard let unified = unifyShapes(prevShape, incomingShape) else {
                    throw OmniBufError.parse("conflicting wire shape for field #\(fnum)")
                }
                fieldShapes[fnum] = unified
            } else {
                fieldShapes[fnum] = incomingShape
            }

            switch (numericMap[fnum], decoded) {
            case (.array(var existing), .array(let incoming)):
                existing.append(contentsOf: incoming)
                numericMap[fnum] = .array(existing)
            case (.object(var existing), .object(let incoming)) where wt == WireType.wireMap:
                for (k, v) in incoming {
                    existing[k] = v
                }
                numericMap[fnum] = .object(existing)
            default:
                numericMap[fnum] = decoded
            }
        }
    }

    // Decode accumulated submessages keeping each segment boundary intact
    for (fnum, segSlices) in subMsgSegments {
        let childLayers = resolveChildLayers(fnum, layers: effectiveLayers)
        let subObj = try decodeBlindSegments(
            segSlices,
            inheritedLayers: childLayers,
            depth: depth &+ 1,
            budget: &budget
        )
        numericMap[fnum] = .object(subObj)
    }

    // Resolve presentation names from merged Field #0 metadata and reject collisions
    var result: [String: BlindValue] = [:]
    result.reserveCapacity(numericMap.count)
    var usedKeys = Set<String>()

    for fnum in fieldOrder.sorted() {
        guard let val = numericMap[fnum] else { continue }
        let metaName = resolveFieldName(fnum, layers: effectiveLayers)
        let key = metaName.isEmpty ? "field_\(fnum)" : metaName
        guard !usedKeys.contains(key) else {
            throw OmniBufError.parse("Field #0 name collision on '\(key)' at field #\(fnum)")
        }
        usedKeys.insert(key)
        result[key] = val
    }

    return result
}

private func decodeBlindValue(
    reader r: inout OmniBufReader,
    wireType: UInt8,
    inCollection: Bool,
    childLayers: [SchemaMeta],
    depth: Int,
    budget: inout DecodeBudget
) throws -> (BlindValue, BlindShape) {
    let normWT = normalizeWireType(wireType)
    switch wireType {
    case WireType.wireUint:
        return (.uint(try r.readVarint()), .scalar(normWT))
    case WireType.wireSint:
        return (.int(try r.readSint64()), .scalar(normWT))
    case WireType.wireBoolFalse:
        if inCollection {
            return (.bool(try r.readBoolByte()), .scalar(normWT))
        }
        return (.bool(false), .scalar(normWT))
    case WireType.wireBoolTrue:
        if inCollection {
            throw OmniBufError.parse("WireBoolTrue (3) is invalid inside collections")
        }
        return (.bool(true), .scalar(normWT))
    case WireType.wireFixed32:
        return (.uint(UInt64(try r.readFixed32())), .scalar(normWT))
    case WireType.wireFixed64:
        return (.uint(try r.readFixed64()), .scalar(normWT))
    case WireType.wireSfixed32:
        return (.int(Int64(try r.readSfixed32())), .scalar(normWT))
    case WireType.wireSfixed64:
        return (.int(try r.readSfixed64()), .scalar(normWT))
    case WireType.wireFloat32:
        return (.float32(try r.readFloat32()), .scalar(normWT))
    case WireType.wireFloat64:
        return (.float64(try r.readFloat64()), .scalar(normWT))
    case WireType.wireString:
        let s = try r.readString()
        try budget.addAlloc(s.utf8.count)
        return (.string(s), .scalar(normWT))
    case WireType.wireBytes:
        let b = try r.readBytes()
        try budget.addAlloc(b.count)
        return (.bytes(b), .scalar(normWT))
    case WireType.wireSubMsg:
        let nextDepth = depth &+ 1
        guard nextDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(nextDepth)
        }
        let slice = try r.readLenSlice()
        let obj = try decodeBlindObject(slice, inheritedLayers: childLayers, depth: nextDepth, budget: &budget)
        return (.object(obj), .scalar(WireType.wireSubMsg))
    case WireType.wireArray:
        let nextDepth = depth &+ 1
        guard nextDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(nextDepth)
        }
        let body = try r.readLenSlice(minLen: 2)
        let (elemWT, count, elemReader) = try OmniBufReader.parseArrayBody(body)
        try budget.addElements(count)
        try budget.addAlloc(count: count, elementBytes: 32)
        var er = elemReader
        var items: [BlindValue] = []
        items.reserveCapacity(count)
        var unifiedElemShape: BlindShape? = nil
        for _ in 0..<count {
            let (item, itemShape) = try decodeBlindValue(
                reader: &er,
                wireType: elemWT,
                inCollection: true,
                childLayers: childLayers,
                depth: nextDepth,
                budget: &budget
            )
            if elemWT == WireType.wireArray || elemWT == WireType.wireMap {
                guard let nextUnified = unifyShapes(unifiedElemShape, itemShape) else {
                    throw OmniBufError.parse("conflicting nested container element types inside WireArray")
                }
                unifiedElemShape = nextUnified
            }
            items.append(item)
        }
        guard er.isAtEnd else {
            throw OmniBufError.parse("WireArray has \(er.remaining) trailing bytes")
        }
        return (.array(items), .array(elemType: elemWT, elemShape: unifiedElemShape))
    case WireType.wireMap:
        let nextDepth = depth &+ 1
        guard nextDepth <= budget.maxDepth else {
            throw OmniBufError.depthLimitExceeded(nextDepth)
        }
        let body = try r.readLenSlice(minLen: 3)
        let (keyWT, valWT, count, mapReader) = try OmniBufReader.parseMapBody(body)
        try budget.addElements(count)
        try budget.addAlloc(count: count, elementBytes: 64)
        var mr = mapReader
        var mapObj: [String: BlindValue] = [:]
        mapObj.reserveCapacity(count)
        var unifiedValShape: BlindShape? = nil
        for _ in 0..<count {
            let keyStr = try decodeBlindMapKey(reader: &mr, keyType: keyWT, budget: &budget)
            let (val, valShape) = try decodeBlindValue(
                reader: &mr,
                wireType: valWT,
                inCollection: true,
                childLayers: childLayers,
                depth: nextDepth,
                budget: &budget
            )
            if valWT == WireType.wireArray || valWT == WireType.wireMap {
                guard let nextUnified = unifyShapes(unifiedValShape, valShape) else {
                    throw OmniBufError.parse("conflicting nested container value types inside WireMap")
                }
                unifiedValShape = nextUnified
            }
            mapObj[keyStr] = val
        }
        guard mr.isAtEnd else {
            throw OmniBufError.parse("WireMap has \(mr.remaining) trailing bytes")
        }
        return (.object(mapObj), .map(keyType: keyWT, valType: valWT, valShape: unifiedValShape))
    case WireType.wireExtended:
        let slice = try r.readLenSlice(minLen: 1)
        let extType = slice[0]
        throw OmniBufError.unsupportedExtension(extType)
    default:
        throw OmniBufError.parse("invalid wire type \(wireType)")
    }
}

private func decodeBlindMapKey(
    reader r: inout OmniBufReader,
    keyType: UInt8,
    budget: inout DecodeBudget
) throws -> String {
    switch keyType {
    case WireType.wireUint:
        return String(try r.readVarint())
    case WireType.wireSint:
        return String(try r.readSint64())
    case WireType.wireBoolFalse:
        return (try r.readBoolByte()) ? "true" : "false"
    case WireType.wireFixed32:
        return String(try r.readFixed32())
    case WireType.wireFixed64:
        return String(try r.readFixed64())
    case WireType.wireSfixed32:
        return String(try r.readSfixed32())
    case WireType.wireSfixed64:
        return String(try r.readSfixed64())
    case WireType.wireString:
        let s = try r.readString()
        try budget.addAlloc(s.utf8.count)
        return s
    default:
        throw OmniBufError.parse("invalid WireMap key type \(keyType)")
    }
}

// MARK: - Base64 & Canonical JSON Serialization

private let base64Table: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

/// Encodes `bytes` as standard RFC 4648 Base64.
public func encodeBase64(_ bytes: [UInt8]) -> String {
    if bytes.isEmpty { return "" }
    var out: [UInt8] = []
    out.reserveCapacity(((bytes.count + 2) / 3) * 4)
    var i = 0
    while i + 2 < bytes.count {
        let n = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i + 2])
        out.append(base64Table[Int((n >> 18) & 63)])
        out.append(base64Table[Int((n >> 12) & 63)])
        out.append(base64Table[Int((n >> 6) & 63)])
        out.append(base64Table[Int(n & 63)])
        i += 3
    }
    let rem = bytes.count - i
    if rem == 1 {
        let n = UInt32(bytes[i]) << 16
        out.append(base64Table[Int((n >> 18) & 63)])
        out.append(base64Table[Int((n >> 12) & 63)])
        out.append(UInt8(ascii: "="))
        out.append(UInt8(ascii: "="))
    } else if rem == 2 {
        let n = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8)
        out.append(base64Table[Int((n >> 18) & 63)])
        out.append(base64Table[Int((n >> 12) & 63)])
        out.append(base64Table[Int((n >> 6) & 63)])
        out.append(UInt8(ascii: "="))
    }
    return String(decoding: out, as: UTF8.self)
}

private func writeEscapedJSONString(_ dst: inout String, _ s: String) {
    dst.append("\"")
    for scalar in s.unicodeScalars {
        switch scalar.value {
        case 0x22: dst.append("\\\"")
        case 0x5C: dst.append("\\\\")
        case 0x08: dst.append("\\b")
        case 0x0C: dst.append("\\f")
        case 0x0A: dst.append("\\n")
        case 0x0D: dst.append("\\r")
        case 0x09: dst.append("\\t")
        case 0x00..<0x20:
            let hex = String(scalar.value, radix: 16, uppercase: false)
            dst.append("\\u")
            if hex.count < 4 {
                dst.append(String(repeating: "0", count: 4 - hex.count))
            }
            dst.append(hex)
        default:
            dst.unicodeScalars.append(scalar)
        }
    }
    dst.append("\"")
}

private func formatCanonicalFloat(_ value: Double, isFloat32: Bool) -> String {
    if value == 0.0 {
        return value.sign == .minus ? "-0" : "0"
    }
    var s = isFloat32 ? String(Float(value)) : String(value)
    if s.hasSuffix(".0") {
        s.removeLast(2)
    }
    return s
}

private func serializeBlindValue(
    _ dst: inout String,
    _ val: BlindValue,
    step: String,
    curIndent: String,
    hasNonFinite: inout Bool
) {
    switch val {
    case .bool(let b):
        dst.append(b ? "true" : "false")
    case .uint(let u):
        dst.append(String(u))
    case .int(let i):
        dst.append(String(i))
    case .float32(let f):
        if !f.isFinite {
            hasNonFinite = true
            dst.append("null")
        } else {
            dst.append(formatCanonicalFloat(Double(f), isFloat32: true))
        }
    case .float64(let d):
        if !d.isFinite {
            hasNonFinite = true
            dst.append("null")
        } else {
            dst.append(formatCanonicalFloat(d, isFloat32: false))
        }
    case .string(let s):
        writeEscapedJSONString(&dst, s)
    case .bytes(let b):
        writeEscapedJSONString(&dst, encodeBase64(b))
    case .array(let items):
        if items.isEmpty {
            dst.append("[]")
            return
        }
        if step.isEmpty {
            dst.append("[")
            for (idx, item) in items.enumerated() {
                if idx > 0 { dst.append(",") }
                serializeBlindValue(&dst, item, step: step, curIndent: "", hasNonFinite: &hasNonFinite)
            }
            dst.append("]")
        } else {
            let nextIndent = curIndent + step
            dst.append("[\n")
            for (idx, item) in items.enumerated() {
                if idx > 0 { dst.append(",\n") }
                dst.append(nextIndent)
                serializeBlindValue(&dst, item, step: step, curIndent: nextIndent, hasNonFinite: &hasNonFinite)
            }
            dst.append("\n")
            dst.append(curIndent)
            dst.append("]")
        }
    case .object(let map):
        serializeBlindObject(&dst, map, step: step, curIndent: curIndent, hasNonFinite: &hasNonFinite)
    }
}

private func serializeBlindObject(
    _ dst: inout String,
    _ map: [String: BlindValue],
    step: String,
    curIndent: String,
    hasNonFinite: inout Bool
) {
    if map.isEmpty {
        dst.append("{}")
        return
    }
    let sortedKeys = map.keys.sorted(by: compareUTF8Bytes)
    if step.isEmpty {
        dst.append("{")
        for (idx, key) in sortedKeys.enumerated() {
            if idx > 0 { dst.append(",") }
            writeEscapedJSONString(&dst, key)
            dst.append(":")
            serializeBlindValue(&dst, map[key]!, step: step, curIndent: "", hasNonFinite: &hasNonFinite)
        }
        dst.append("}")
    } else {
        let nextIndent = curIndent + step
        dst.append("{\n")
        for (idx, key) in sortedKeys.enumerated() {
            if idx > 0 { dst.append(",\n") }
            dst.append(nextIndent)
            writeEscapedJSONString(&dst, key)
            dst.append(": ")
            serializeBlindValue(&dst, map[key]!, step: step, curIndent: nextIndent, hasNonFinite: &hasNonFinite)
        }
        dst.append("\n")
        dst.append(curIndent)
        dst.append("}")
    }
}
