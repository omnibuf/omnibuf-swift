/// Zero-decode field scanning and in-place wire splicing helpers for lazy `Opaque` message views.
public enum OpaqueWire {
    /// Scans `raw` and returns the `(valueStart, valueEnd, wireType)` of the LAST occurrence of `targetField`
    /// with matching wire type (or any boolean wire type if `expectedWireType` is `wireBoolFalse`/`wireBoolTrue`).
    @inlinable
    public static func locateLastField(
        in raw: UnsafeBufferPointer<UInt8>,
        fieldNumber targetField: UInt32,
        expectedWireType: UInt8
    ) -> (start: Int, end: Int, wireType: UInt8)? {
        var r = OmniBufReader(raw)
        var found: (Int, Int, UInt8)? = nil
        let isBool = (expectedWireType == WireType.wireBoolFalse || expectedWireType == WireType.wireBoolTrue)

        while !r.isAtEnd {
            guard let (fnum, wt) = try? r.readTag() else { return nil }
            let valStart = r.position
            if fnum == 0 {
                guard wt == WireType.wireSubMsg else { return nil }
                guard (try? r.skipValue(wireType: wt)) != nil else { return nil }
                continue
            }
            guard (try? r.skipValue(wireType: wt)) != nil else { return nil }
            let valEnd = r.position
            if fnum == targetField {
                if isBool {
                    if wt == WireType.wireBoolFalse || wt == WireType.wireBoolTrue {
                        found = (valStart, valEnd, wt)
                    }
                } else if wt == expectedWireType {
                    found = (valStart, valEnd, wt)
                }
            }
        }
        return found
    }

    /// Reads a `UInt64` field from `raw` (last occurrence wins, 0 if absent).
    @inlinable
    public static func readUint64(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> UInt64 {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireUint) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readVarint()) ?? 0
    }

    /// Reads a `UInt32` field from `raw` (last occurrence wins, 0 if absent).
    @inlinable
    public static func readUint32(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> UInt32 {
        UInt32(truncatingIfNeeded: readUint64(in: raw, fieldNumber: fieldNumber))
    }

    /// Reads an `Int64` ZigZag field from `raw` (last occurrence wins, 0 if absent).
    @inlinable
    public static func readSint64(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Int64 {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireSint) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readSint64()) ?? 0
    }

    /// Reads an `Int32` ZigZag field from `raw` (last occurrence wins, 0 if absent).
    @inlinable
    public static func readSint32(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Int32 {
        Int32(truncatingIfNeeded: readSint64(in: raw, fieldNumber: fieldNumber))
    }

    /// Reads a `Bool` field from `raw` (last occurrence wins, false if absent).
    @inlinable
    public static func readBool(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Bool {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireBoolFalse) else {
            return false
        }
        return loc.wireType == WireType.wireBoolTrue
    }

    /// Reads a `UInt32` fixed32 field from `raw`.
    @inlinable
    public static func readFixed32(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> UInt32 {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireFixed32) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readFixed32()) ?? 0
    }

    /// Reads a `UInt64` fixed64 field from `raw`.
    @inlinable
    public static func readFixed64(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> UInt64 {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireFixed64) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readFixed64()) ?? 0
    }

    /// Reads an `Int32` sfixed32 field from `raw`.
    @inlinable
    public static func readSfixed32(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Int32 {
        Int32(bitPattern: readFixed32(in: raw, fieldNumber: fieldNumber))
    }

    /// Reads an `Int64` sfixed64 field from `raw`.
    @inlinable
    public static func readSfixed64(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Int64 {
        Int64(bitPattern: readFixed64(in: raw, fieldNumber: fieldNumber))
    }

    /// Reads a `Float` field from `raw`.
    @inlinable
    public static func readFloat32(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Float {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireFloat32) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readFloat32()) ?? 0
    }

    /// Reads a `Double` field from `raw`.
    @inlinable
    public static func readFloat64(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> Double {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireFloat64) else {
            return 0
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readFloat64()) ?? 0
    }

    /// Reads a `String` field from `raw` with strict UTF-8 validation.
    @inlinable
    public static func readString(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> String {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireString) else {
            return ""
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readString()) ?? ""
    }

    /// Reads a `[UInt8]` bytes field from `raw`.
    @inlinable
    public static func readBytes(in raw: UnsafeBufferPointer<UInt8>, fieldNumber: UInt32) -> [UInt8] {
        guard let loc = locateLastField(in: raw, fieldNumber: fieldNumber, expectedWireType: WireType.wireBytes) else {
            return []
        }
        var r = OmniBufReader(raw)
        r.position = loc.start
        return (try? r.readBytes()) ?? []
    }

    /// Locates the byte range `(start, end)` of a `WireSubMsg` field inside `raw`.
    /// If the field occurs once, `multiple` is `false` so callers can create a zero-copy sub-view.
    @inlinable
    public static func locateSubMsgRange(
        in raw: UnsafeBufferPointer<UInt8>,
        fieldNumber targetField: UInt32
    ) -> (start: Int, end: Int, multiple: Bool)? {
        var r = OmniBufReader(raw)
        var firstStart = 0
        var firstEnd = 0
        var count = 0
        while !r.isAtEnd {
            guard let (fnum, wt) = try? r.readTag() else { return nil }
            if fnum == targetField && wt == WireType.wireSubMsg {
                guard let len = try? r.readVarint(), len <= UInt64(r.remaining) else { return nil }
                let s = r.position
                let e = s &+ Int(len)
                r.position = e
                if count == 0 {
                    firstStart = s
                    firstEnd = e
                }
                count &+= 1
            } else {
                guard (try? r.skipValue(wireType: wt)) != nil else { return nil }
            }
        }
        guard count > 0 else { return nil }
        return (firstStart, firstEnd, count > 1)
    }

    /// Collects and concatenates all occurrences of a `WireSubMsg` field into a byte array.
    public static func readMergedSubMsgBytes(
        in raw: UnsafeBufferPointer<UInt8>,
        fieldNumber targetField: UInt32
    ) -> [UInt8] {
        var r = OmniBufReader(raw)
        var out: [UInt8] = []
        while !r.isAtEnd {
            guard let (fnum, wt) = try? r.readTag() else { return [] }
            if fnum == targetField && wt == WireType.wireSubMsg {
                guard let slice = try? r.readLenSlice() else { return [] }
                if !slice.isEmpty {
                    out.append(contentsOf: slice)
                }
            } else {
                guard (try? r.skipValue(wireType: wt)) != nil else { return [] }
            }
        }
        return out
    }

    /// Counts total elements across all `WireArray` occurrences of `fieldNumber`.
    @inlinable
    public static func arrayCount(
        in raw: UnsafeBufferPointer<UInt8>,
        fieldNumber targetField: UInt32,
        expectedElemType: UInt8
    ) -> Int {
        var r = OmniBufReader(raw)
        var total = 0
        while !r.isAtEnd {
            guard let (fnum, wt) = try? r.readTag() else { return 0 }
            if fnum == targetField && wt == WireType.wireArray {
                guard let body = try? r.readLenSlice(minLen: 2),
                      let (elemWT, cnt, _) = try? OmniBufReader.parseArrayBody(body),
                      elemWT == expectedElemType else {
                    return 0
                }
                total &+= cnt
            } else {
                guard (try? r.skipValue(wireType: wt)) != nil else { return 0 }
            }
        }
        return total
    }

    /// Looks up a string key in a `map<string, uint64>` field (last matching entry across occurrences wins).
    public static func lookupMapStringUint64(
        in raw: UnsafeBufferPointer<UInt8>,
        fieldNumber targetField: UInt32,
        key targetKey: String
    ) -> UInt64? {
        var r = OmniBufReader(raw)
        var result: UInt64? = nil
        while !r.isAtEnd {
            guard let (fnum, wt) = try? r.readTag() else { return nil }
            if fnum == targetField && wt == WireType.wireMap {
                guard let body = try? r.readLenSlice(minLen: 3),
                      let (keyWT, valWT, cnt, mapReader) = try? OmniBufReader.parseMapBody(body),
                      keyWT == WireType.wireString,
                      valWT == WireType.wireUint else {
                    return nil
                }
                var mr = mapReader
                for _ in 0..<cnt {
                    guard let k = try? mr.readString(), let v = try? mr.readVarint() else {
                        return nil
                    }
                    if k == targetKey {
                        result = v
                    }
                }
            } else {
                guard (try? r.skipValue(wireType: wt)) != nil else { return nil }
            }
        }
        return result
    }

    // MARK: - In-Place Wire Splicing

    /// Splices unmodified contiguous byte ranges from `raw` into `dst` (preserving any existing
    /// prefix bytes in `dst`) and invokes `appendDirty` only for fields marked in `dirtyMask`.
    ///
    /// Untouched fields are hopped in O(1) time without decoding their bodies.
    /// `dst` is a value-typed `[UInt8]`, so `raw` is never mutated even if they originally shared storage.
    @inlinable
    public static func spliceFields(
        into dst: inout [UInt8],
        raw: [UInt8],
        dirtyMask: UInt64,
        maxField: UInt16,
        appendDirty: (inout OmniBufWriter, UInt16) -> Void
    ) {
        let userMask = dirtyMask & ~1
        let prefixLen = dst.count
        var writer = OmniBufWriter(initialCapacity: prefixLen &+ raw.count &+ 64)
        if prefixLen > 0 {
            writer.appendRaw(dst)
        }
        raw.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress
            var r = OmniBufReader(buf)
            var cleanStart = 0
            var validEnd = 0
            var emitted: UInt64 = 0

            while !r.isAtEnd {
                let fieldStart = r.position
                guard let (fnum, wt) = try? r.readTag() else { break }
                if fnum == 0 {
                    guard wt == WireType.wireSubMsg,
                          let slice = try? r.readLenSlice(),
                          (try? SchemaMeta.validateSlice(slice, depth: 1)) != nil else {
                        break
                    }
                } else {
                    guard (try? r.skipValue(wireType: wt)) != nil else { break }
                }
                let fieldEnd = r.position
                validEnd = fieldEnd

                let bit: UInt64 = (fnum > 0 && fnum < 64) ? (1 &<< UInt64(fnum)) : 0
                if (userMask & bit) != 0 {
                    if cleanStart < fieldStart, let b = base {
                        writer.appendRaw(b.advanced(by: cleanStart), count: fieldStart &- cleanStart)
                    }
                    if (emitted & bit) == 0 {
                        appendDirty(&writer, UInt16(fnum))
                        emitted |= bit
                    }
                    cleanStart = fieldEnd
                } else {
                    emitted |= bit
                }
            }

            if cleanStart < validEnd, let b = base {
                writer.appendRaw(b.advanced(by: cleanStart), count: validEnd &- cleanStart)
            }

            let rem = userMask & ~emitted
            if rem != 0 {
                let limit = min(maxField, 63)
                if limit >= 1 {
                    for fnum in UInt16(1)...limit {
                        if (rem & (1 &<< UInt64(fnum))) != 0 {
                            appendDirty(&writer, fnum)
                        }
                    }
                }
            }
        }
        dst = writer.toBytes()
    }

    /// Fallible counterpart to `spliceFields` that validates every field in `raw` and throws
    /// `OmniBufError` (leaving `dst` unmodified) if `raw` contains any malformed tag or payload.
    @inlinable
    public static func trySpliceFields(
        into dst: inout [UInt8],
        raw: [UInt8],
        dirtyMask: UInt64,
        maxField: UInt16,
        appendDirty: (inout OmniBufWriter, UInt16) -> Void
    ) throws {
        let userMask = dirtyMask & ~1
        let prefixLen = dst.count
        var writer = OmniBufWriter(initialCapacity: prefixLen &+ raw.count &+ 64)
        if prefixLen > 0 {
            writer.appendRaw(dst)
        }
        try raw.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress
            var r = OmniBufReader(buf)
            var cleanStart = 0
            var emitted: UInt64 = 0

            while !r.isAtEnd {
                let fieldStart = r.position
                let (fnum, wt) = try r.readTag()
                if fnum == 0 {
                    guard wt == WireType.wireSubMsg else {
                        throw OmniBufError.parse("invalid Field #0 wire type \(wt)")
                    }
                    let slice = try r.readLenSlice()
                    _ = try SchemaMeta.validateSlice(slice, depth: 1)
                } else {
                    try r.validateValue(wireType: wt, inCollection: false, depth: 0)
                }
                let fieldEnd = r.position

                let bit: UInt64 = (fnum > 0 && fnum < 64) ? (1 &<< UInt64(fnum)) : 0
                if (userMask & bit) != 0 {
                    if cleanStart < fieldStart, let b = base {
                        writer.appendRaw(b.advanced(by: cleanStart), count: fieldStart &- cleanStart)
                    }
                    if (emitted & bit) == 0 {
                        appendDirty(&writer, UInt16(fnum))
                        emitted |= bit
                    }
                    cleanStart = fieldEnd
                } else {
                    emitted |= bit
                }
            }

            if cleanStart < buf.count, let b = base {
                writer.appendRaw(b.advanced(by: cleanStart), count: buf.count &- cleanStart)
            }

            let rem = userMask & ~emitted
            if rem != 0 {
                let limit = min(maxField, 63)
                if limit >= 1 {
                    for fnum in UInt16(1)...limit {
                        if (rem & (1 &<< UInt64(fnum))) != 0 {
                            appendDirty(&writer, fnum)
                        }
                    }
                }
            }
        }
        dst = writer.toBytes()
    }
}
