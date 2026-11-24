/// Fast strict UTF-8 validator per RFC 3629 (rejects overlong forms, surrogates, and > U+10FFFF).
@inlinable
public func isValidUTF8(_ ptr: UnsafePointer<UInt8>, count: Int) -> Bool {
    var i = 0
    // Fast ASCII loop: check 8 bytes at a time when possible
    while i &+ 8 <= count {
        let word = UnsafeRawPointer(ptr.advanced(by: i)).loadUnaligned(as: UInt64.self)
        if (word & 0x8080_8080_8080_8080) != 0 {
            break
        }
        i &+= 8
    }
    while i < count {
        let b0 = ptr[i]
        if b0 < 0x80 {
            i &+= 1
            continue
        }
        if b0 < 0xC2 || b0 > 0xF4 {
            return false
        }
        if b0 < 0xE0 {
            // 2-byte sequence: C2..DF 80..BF
            guard i &+ 1 < count else { return false }
            let b1 = ptr[i &+ 1]
            guard (b1 & 0xC0) == 0x80 else { return false }
            i &+= 2
        } else if b0 < 0xF0 {
            // 3-byte sequence
            guard i &+ 2 < count else { return false }
            let b1 = ptr[i &+ 1]
            let b2 = ptr[i &+ 2]
            guard (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80 else { return false }
            if b0 == 0xE0 && b1 < 0xA0 { return false } // overlong
            if b0 == 0xED && b1 >= 0xA0 { return false } // UTF-16 surrogate U+D800..U+DFFF
            i &+= 3
        } else {
            // 4-byte sequence: F0..F4
            guard i &+ 3 < count else { return false }
            let b1 = ptr[i &+ 1]
            let b2 = ptr[i &+ 2]
            let b3 = ptr[i &+ 3]
            guard (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80 && (b3 & 0xC0) == 0x80 else {
                return false
            }
            if b0 == 0xF0 && b1 < 0x90 { return false } // overlong
            if b0 == 0xF4 && b1 >= 0x90 { return false } // > U+10FFFF
            i &+= 4
        }
    }
    return true
}

/// Constructs a Swift `String` from validated UTF-8 bytes without re-scanning.
@inlinable
@inline(__always)
public func makeValidatedString(_ ptr: UnsafePointer<UInt8>, count: Int) throws -> String {
    guard count > 0 else { return "" }
    guard isValidUTF8(ptr, count: count) else {
        throw OmniBufError.parse("invalid UTF-8 in WireString")
    }
    return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
}

/// High-performance bounds-checked OmniBuf wire reader operating on raw byte pointers.
public struct OmniBufReader {
    @usableFromInline
    internal let base: UnsafePointer<UInt8>?
    @usableFromInline
    internal let count: Int
    @usableFromInline
    internal var pos: Int

    @inlinable
    public init(_ buffer: UnsafeBufferPointer<UInt8>) {
        self.base = buffer.baseAddress
        self.count = buffer.count
        self.pos = 0
    }

    @inlinable
    public init(base: UnsafePointer<UInt8>?, count: Int) {
        precondition(count >= 0, "OmniBufReader count must be non-negative")
        self.base = base
        self.count = count
        self.pos = 0
    }

    @inlinable
    public var position: Int {
        get { pos }
        set {
            precondition(newValue >= 0 && newValue <= count, "OmniBufReader position out of bounds")
            pos = newValue
        }
    }

    @inlinable
    public var remaining: Int { count &- pos }

    @inlinable
    public var isAtEnd: Bool { pos >= count }

    // MARK: - Prefix-Varint Decoding

    @inlinable
    @inline(__always)
    public mutating func readVarint() throws -> UInt64 {
        let rem = count &- pos
        guard rem > 0, let b = base else {
            throw OmniBufError.parse("truncated varint at offset \(pos)")
        }
        let p = b.advanced(by: pos)
        let b0 = p[0]
        if (b0 & 1) != 0 {
            pos &+= 1
            return UInt64(b0 &>> 1)
        }
        if (b0 & 2) != 0 {
            guard rem >= 2 else {
                throw OmniBufError.parse("truncated 2-byte varint at offset \(pos)")
            }
            let raw = UInt16(littleEndian: UnsafeRawPointer(p).loadUnaligned(as: UInt16.self))
            pos &+= 2
            return UInt64(raw &>> 2)
        }
        if (b0 & 4) != 0 {
            guard rem >= 4 else {
                throw OmniBufError.parse("truncated 4-byte varint at offset \(pos)")
            }
            let raw = UInt32(littleEndian: UnsafeRawPointer(p).loadUnaligned(as: UInt32.self))
            pos &+= 4
            return UInt64(raw &>> 3)
        }
        if b0 == 0 {
            guard rem >= 9 else {
                throw OmniBufError.parse("truncated 9-byte varint at offset \(pos)")
            }
            let raw = UInt64(littleEndian: UnsafeRawPointer(p.advanced(by: 1)).loadUnaligned(as: UInt64.self))
            pos &+= 9
            return raw
        }
        throw OmniBufError.parse("reserved prefix-varint byte 0x\(String(b0, radix: 16)) at offset \(pos)")
    }

    @inlinable
    @inline(__always)
    public mutating func readTag() throws -> (fieldNumber: UInt32, wireType: UInt8) {
        let tag = try readVarint()
        let fnum = tag &>> 4
        guard fnum <= WireType.maxFieldNumber else {
            throw OmniBufError.parse("field number \(fnum) exceeds maximum \(WireType.maxFieldNumber)")
        }
        return (UInt32(truncatingIfNeeded: fnum), UInt8(truncatingIfNeeded: tag & 0x0F))
    }

    // MARK: - ZigZag & Fixed Scalars

    @inlinable
    @inline(__always)
    public static func decodeZigZag(_ u: UInt64) -> Int64 {
        Int64(bitPattern: (u &>> 1) ^ (0 &- (u & 1)))
    }

    @inlinable
    @inline(__always)
    public mutating func readSint64() throws -> Int64 {
        Self.decodeZigZag(try readVarint())
    }

    @inlinable
    @inline(__always)
    public mutating func readSint32() throws -> Int32 {
        Int32(truncatingIfNeeded: Self.decodeZigZag(try readVarint()))
    }

    @inlinable
    @inline(__always)
    public mutating func readByte() throws -> UInt8 {
        guard pos < count, let b = base else {
            throw OmniBufError.parse("unexpected EOF reading byte at offset \(pos)")
        }
        let v = b[pos]
        pos &+= 1
        return v
    }

    @inlinable
    @inline(__always)
    public mutating func readBoolByte() throws -> Bool {
        let b = try readByte()
        if b == 0 { return false }
        if b == 1 { return true }
        throw OmniBufError.parse("invalid boolean byte 0x\(String(b, radix: 16)) in collection")
    }

    @inlinable
    @inline(__always)
    public mutating func readFixed32() throws -> UInt32 {
        guard count &- pos >= 4, let b = base else {
            throw OmniBufError.parse("truncated fixed32 at offset \(pos)")
        }
        let v = UInt32(littleEndian: UnsafeRawPointer(b.advanced(by: pos)).loadUnaligned(as: UInt32.self))
        pos &+= 4
        return v
    }

    @inlinable
    @inline(__always)
    public mutating func readFixed64() throws -> UInt64 {
        guard count &- pos >= 8, let b = base else {
            throw OmniBufError.parse("truncated fixed64 at offset \(pos)")
        }
        let v = UInt64(littleEndian: UnsafeRawPointer(b.advanced(by: pos)).loadUnaligned(as: UInt64.self))
        pos &+= 8
        return v
    }

    @inlinable
    @inline(__always)
    public mutating func readSfixed32() throws -> Int32 {
        Int32(bitPattern: try readFixed32())
    }

    @inlinable
    @inline(__always)
    public mutating func readSfixed64() throws -> Int64 {
        Int64(bitPattern: try readFixed64())
    }

    @inlinable
    @inline(__always)
    public mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readFixed32())
    }

    @inlinable
    @inline(__always)
    public mutating func readFloat64() throws -> Double {
        Double(bitPattern: try readFixed64())
    }

    // MARK: - Length-Prefixed Payloads

    @inlinable
    @inline(__always)
    public mutating func readLenSlice(minLen: Int = 0) throws -> UnsafeBufferPointer<UInt8> {
        let rawLen = try readVarint()
        let rem = count &- pos
        guard rawLen <= UInt64(rem) else {
            throw OmniBufError.parse("length \(rawLen) exceeds remaining \(rem) bytes at offset \(pos)")
        }
        let len = Int(rawLen)
        guard len >= minLen else {
            throw OmniBufError.parse("length \(len) is less than minimum \(minLen) at offset \(pos)")
        }
        let slice = UnsafeBufferPointer(start: base?.advanced(by: pos), count: len)
        pos &+= len
        return slice
    }

    @inlinable
    @inline(__always)
    public mutating func readString() throws -> String {
        let slice = try readLenSlice()
        guard let ptr = slice.baseAddress, !slice.isEmpty else {
            return ""
        }
        return try makeValidatedString(ptr, count: slice.count)
    }

    /// Reads a UTF-8 `String`, charging `budget` before validating or allocating the string.
    @inlinable
    @inline(__always)
    public mutating func readString(budget: inout DecodeBudget) throws -> String {
        let slice = try readLenSlice()
        try budget.addAlloc(slice.count)
        guard let ptr = slice.baseAddress, !slice.isEmpty else {
            return ""
        }
        return try makeValidatedString(ptr, count: slice.count)
    }

    @inlinable
    @inline(__always)
    public mutating func readBytes() throws -> [UInt8] {
        let slice = try readLenSlice()
        if slice.isEmpty { return [] }
        return Array(slice)
    }

    /// Reads a `[UInt8]` payload, charging `budget` before allocating the array.
    @inlinable
    @inline(__always)
    public mutating func readBytes(budget: inout DecodeBudget) throws -> [UInt8] {
        let slice = try readLenSlice()
        try budget.addAlloc(slice.count)
        if slice.isEmpty { return [] }
        return Array(slice)
    }

    // MARK: - Collection Headers

    /// Parses a `WireArray` body (already sliced to `ByteLen`) and returns `(elemType, count, bodyReader)`.
    @inlinable
    public static func parseArrayBody(
        _ body: UnsafeBufferPointer<UInt8>
    ) throws -> (elemType: UInt8, count: Int, reader: OmniBufReader) {
        var r = OmniBufReader(body)
        let elemType = try r.readByte()
        guard WireType.isValidCollectionValueType(elemType) else {
            throw OmniBufError.parse("invalid WireArray ElementType \(elemType)")
        }
        let rawCount = try r.readVarint()
        let rem = r.remaining
        if rawCount == 0 {
            guard rem == 0 else {
                throw OmniBufError.parse("empty WireArray has \(rem) trailing bytes")
            }
            return (elemType, 0, r)
        }
        let fixedWidth = WireType.fixedCollectionElementWidth(elemType)
        if fixedWidth > 0 {
            guard rem % fixedWidth == 0 && rawCount == UInt64(rem / fixedWidth) else {
                throw OmniBufError.parse("fixed-width WireArray count \(rawCount) mismatches \(rem) remaining bytes")
            }
        } else {
            guard rawCount <= UInt64(rem) else {
                throw OmniBufError.parse("WireArray count \(rawCount) exceeds \(rem) remaining bytes")
            }
        }
        return (elemType, Int(rawCount), r)
    }

    /// Parses a `WireMap` body (already sliced to `ByteLen`) and returns `(keyType, valType, count, bodyReader)`.
    @inlinable
    public static func parseMapBody(
        _ body: UnsafeBufferPointer<UInt8>
    ) throws -> (keyType: UInt8, valType: UInt8, count: Int, reader: OmniBufReader) {
        var r = OmniBufReader(body)
        let keyType = try r.readByte()
        let valType = try r.readByte()
        guard WireType.isValidMapKeyType(keyType) else {
            throw OmniBufError.parse("invalid WireMap KeyType \(keyType)")
        }
        guard WireType.isValidCollectionValueType(valType) else {
            throw OmniBufError.parse("invalid WireMap ValueType \(valType)")
        }
        let rawCount = try r.readVarint()
        let rem = r.remaining
        if rawCount == 0 {
            guard rem == 0 else {
                throw OmniBufError.parse("empty WireMap has \(rem) trailing bytes")
            }
            return (keyType, valType, 0, r)
        }
        guard rawCount <= UInt64(rem / 2) else {
            throw OmniBufError.parse("WireMap count \(rawCount) exceeds \(rem / 2) maximum entries")
        }
        return (keyType, valType, Int(rawCount), r)
    }

    // MARK: - O(1) Skip & Full Recursive Validation

    /// Skips a field value in O(1) time without scanning inner container payloads or UTF-8.
    @inlinable
    public mutating func skipValue(wireType: UInt8) throws {
        switch wireType {
        case WireType.wireUint, WireType.wireSint:
            _ = try readVarint()
        case WireType.wireBoolFalse, WireType.wireBoolTrue:
            break
        case WireType.wireFixed32, WireType.wireSfixed32, WireType.wireFloat32:
            guard remaining >= 4 else {
                throw OmniBufError.parse("truncated 4-byte scalar at offset \(pos)")
            }
            pos &+= 4
        case WireType.wireFixed64, WireType.wireSfixed64, WireType.wireFloat64:
            guard remaining >= 8 else {
                throw OmniBufError.parse("truncated 8-byte scalar at offset \(pos)")
            }
            pos &+= 8
        case WireType.wireString, WireType.wireBytes, WireType.wireSubMsg,
             WireType.wireArray, WireType.wireMap:
            _ = try readLenSlice()
        case WireType.wireExtended:
            _ = try readLenSlice(minLen: 1)
        default:
            throw OmniBufError.parse("invalid wire type \(wireType)")
        }
    }

    /// Fully validates a value at `pos` (including nested containers, Field #0, UTF-8, and depth).
    @inlinable
    public mutating func validateValue(
        wireType: UInt8,
        inCollection: Bool = false,
        depth: Int,
        maxDepth: Int = WireType.maxNestingDepth
    ) throws {
        switch wireType {
        case WireType.wireUint, WireType.wireSint:
            _ = try readVarint()
        case WireType.wireBoolFalse:
            if inCollection {
                _ = try readBoolByte()
            }
        case WireType.wireBoolTrue:
            if inCollection {
                throw OmniBufError.parse("WireBoolTrue (3) is invalid inside collections")
            }
        case WireType.wireFixed32, WireType.wireSfixed32, WireType.wireFloat32:
            guard remaining >= 4 else {
                throw OmniBufError.parse("truncated 4-byte scalar at offset \(pos)")
            }
            pos &+= 4
        case WireType.wireFixed64, WireType.wireSfixed64, WireType.wireFloat64:
            guard remaining >= 8 else {
                throw OmniBufError.parse("truncated 8-byte scalar at offset \(pos)")
            }
            pos &+= 8
        case WireType.wireString:
            let slice = try readLenSlice()
            if let ptr = slice.baseAddress, !slice.isEmpty {
                guard isValidUTF8(ptr, count: slice.count) else {
                    throw OmniBufError.parse("invalid UTF-8 in WireString")
                }
            }
        case WireType.wireBytes:
            _ = try readLenSlice()
        case WireType.wireSubMsg:
            let nextDepth = depth &+ 1
            guard nextDepth <= maxDepth else {
                throw OmniBufError.depthLimitExceeded(nextDepth)
            }
            let slice = try readLenSlice()
            try Self.validateMessage(slice, depth: nextDepth, maxDepth: maxDepth)
        case WireType.wireArray:
            let nextDepth = depth &+ 1
            guard nextDepth <= maxDepth else {
                throw OmniBufError.depthLimitExceeded(nextDepth)
            }
            let body = try readLenSlice(minLen: 2)
            let (elemType, elemCount, elemReader) = try Self.parseArrayBody(body)
            var er = elemReader
            if elemType == WireType.wireBoolFalse {
                for _ in 0..<elemCount {
                    _ = try er.readBoolByte()
                }
            } else if WireType.fixedCollectionElementWidth(elemType) > 0 {
                // Already verified exact length in parseArrayBody
                return
            } else {
                for _ in 0..<elemCount {
                    try er.validateValue(wireType: elemType, inCollection: true, depth: nextDepth, maxDepth: maxDepth)
                }
            }
            guard er.isAtEnd else {
                throw OmniBufError.parse("WireArray has \(er.remaining) trailing bytes")
            }
        case WireType.wireMap:
            let nextDepth = depth &+ 1
            guard nextDepth <= maxDepth else {
                throw OmniBufError.depthLimitExceeded(nextDepth)
            }
            let body = try readLenSlice(minLen: 3)
            let (keyType, valType, entryCount, entryReader) = try Self.parseMapBody(body)
            var mr = entryReader
            for _ in 0..<entryCount {
                try mr.validateValue(wireType: keyType, inCollection: true, depth: nextDepth, maxDepth: maxDepth)
                try mr.validateValue(wireType: valType, inCollection: true, depth: nextDepth, maxDepth: maxDepth)
            }
            guard mr.isAtEnd else {
                throw OmniBufError.parse("WireMap has \(mr.remaining) trailing bytes")
            }
        case WireType.wireExtended:
            _ = try readLenSlice(minLen: 1)
        default:
            throw OmniBufError.parse("invalid wire type \(wireType)")
        }
    }

    /// Validates an entire OmniBuf message buffer recursively.
    @inlinable
    public static func validateMessage(
        _ data: UnsafeBufferPointer<UInt8>,
        depth: Int = 0,
        maxDepth: Int = WireType.maxNestingDepth
    ) throws {
        guard depth <= maxDepth else {
            throw OmniBufError.depthLimitExceeded(depth)
        }
        var r = OmniBufReader(data)
        while !r.isAtEnd {
            let (fnum, wt) = try r.readTag()
            if fnum == 0 {
                guard wt == WireType.wireSubMsg else {
                    throw OmniBufError.parse("Field #0 must have WireSubMsg (12), got \(wt)")
                }
                let nextDepth = depth &+ 1
                guard nextDepth <= maxDepth else {
                    throw OmniBufError.depthLimitExceeded(nextDepth)
                }
                let metaSlice = try r.readLenSlice()
                _ = try SchemaMeta.validateSlice(metaSlice, depth: nextDepth, maxDepth: maxDepth)
            } else {
                try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: maxDepth)
            }
        }
    }
}
