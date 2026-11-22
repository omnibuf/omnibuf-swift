/// High-performance single-pass OmniBuf binary writer backed by a raw byte buffer.
///
/// Uses an unmanaged contiguous byte buffer for zero-overhead appends, unaligned
/// little-endian word stores, and single-pass container length backpatching.
public struct OmniBufWriter: ~Copyable {
    @usableFromInline
    internal var ptr: UnsafeMutablePointer<UInt8>
    @usableFromInline
    internal var count: Int
    @usableFromInline
    internal var capacity: Int

    @inlinable
    public init(initialCapacity: Int = 256) {
        let cap = max(initialCapacity, 64)
        self.ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        self.count = 0
        self.capacity = cap
    }

    @inlinable
    deinit {
        ptr.deallocate()
    }

    /// Current number of written bytes.
    @inlinable
    public var byteCount: Int { count }

    /// Copies the written bytes into a `[UInt8]` array.
    @inlinable
    public func toBytes() -> [UInt8] {
        if count == 0 { return [] }
        return [UInt8](unsafeUninitializedCapacity: count) { dst, initializedCount in
            dst.baseAddress!.initialize(from: ptr, count: count)
            initializedCount = count
        }
    }

    /// Provides read-only access to the written bytes without copying.
    @inlinable
    public func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try body(UnsafeBufferPointer(start: ptr, count: count))
    }

    @inlinable
    @inline(__always)
    public mutating func ensureCapacity(_ extra: Int) {
        precondition(extra >= 0, "OmniBufWriter.ensureCapacity extra must be non-negative")
        let (needed, overflow) = count.addingReportingOverflow(extra)
        precondition(!overflow, "OmniBufWriter capacity overflow")
        if needed <= capacity { return }
        grow(needed: needed)
    }

    @usableFromInline
    @inline(never)
    internal mutating func grow(needed: Int) {
        var newCap = capacity
        while newCap < needed {
            if newCap > Int.max / 2 {
                newCap = needed
                break
            }
            newCap &*= 2
        }
        let newPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
        if count > 0 {
            newPtr.initialize(from: ptr, count: count)
        }
        ptr.deallocate()
        ptr = newPtr
        capacity = newCap
    }

    // MARK: - Raw Byte Primitives

    @inlinable
    @inline(__always)
    public mutating func appendByte(_ b: UInt8) {
        ensureCapacity(1)
        ptr[count] = b
        count &+= 1
    }

    @inlinable
    @inline(__always)
    public mutating func appendTwoBytes(_ b0: UInt8, _ b1: UInt8) {
        ensureCapacity(2)
        ptr[count] = b0
        ptr[count &+ 1] = b1
        count &+= 2
    }

    @inlinable
    @inline(__always)
    public mutating func appendThreeBytes(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        ensureCapacity(3)
        ptr[count] = b0
        ptr[count &+ 1] = b1
        ptr[count &+ 2] = b2
        count &+= 3
    }

    @inlinable
    @inline(__always)
    public mutating func appendFourBytes(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) {
        ensureCapacity(4)
        ptr[count] = b0
        ptr[count &+ 1] = b1
        ptr[count &+ 2] = b2
        ptr[count &+ 3] = b3
        count &+= 4
    }

    @inlinable
    @inline(__always)
    public mutating func appendRaw(_ bytes: UnsafePointer<UInt8>, count n: Int) {
        guard n > 0 else { return }
        ensureCapacity(n)
        ptr.advanced(by: count).initialize(from: bytes, count: n)
        count &+= n
    }

    @inlinable
    @inline(__always)
    public mutating func appendRaw(_ slice: UnsafeBufferPointer<UInt8>) {
        guard let base = slice.baseAddress, !slice.isEmpty else { return }
        appendRaw(base, count: slice.count)
    }

    @inlinable
    @inline(__always)
    public mutating func appendRaw(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        bytes.withUnsafeBufferPointer { buf in
            appendRaw(buf)
        }
    }

    // MARK: - Prefix-Varint (1 / 2 / 4 / 9 bytes)

    @inlinable
    @inline(__always)
    public mutating func appendVarint(_ v: UInt64) {
        ensureCapacity(9)
        let p = ptr.advanced(by: count)
        if v <= 0x7F {
            p[0] = UInt8(truncatingIfNeeded: (v &<< 1) | 1)
            count &+= 1
        } else if v <= 0x3FFF {
            let enc = UInt16(truncatingIfNeeded: (v &<< 2) | 2).littleEndian
            UnsafeMutableRawPointer(p).storeBytes(of: enc, as: UInt16.self)
            count &+= 2
        } else if v <= 0x1FFF_FFFF {
            let enc = UInt32(truncatingIfNeeded: (v &<< 3) | 4).littleEndian
            UnsafeMutableRawPointer(p).storeBytes(of: enc, as: UInt32.self)
            count &+= 4
        } else {
            p[0] = 0
            let enc = v.littleEndian
            UnsafeMutableRawPointer(p.advanced(by: 1)).storeBytes(of: enc, as: UInt64.self)
            count &+= 9
        }
    }

    @inlinable
    @inline(__always)
    public mutating func appendTag(fieldNumber: UInt32, wireType: UInt8) {
        appendVarint((UInt64(fieldNumber) &<< 4) | UInt64(wireType))
    }

    // MARK: - ZigZag Signed Integers

    @inlinable
    @inline(__always)
    public static func encodeZigZag(_ v: Int64) -> UInt64 {
        UInt64(bitPattern: (v &<< 1) ^ (v &>> 63))
    }

    @inlinable
    @inline(__always)
    public mutating func appendZigZag(_ v: Int64) {
        appendVarint(Self.encodeZigZag(v))
    }

    @inlinable
    @inline(__always)
    public mutating func appendZigZag32(_ v: Int32) {
        appendVarint(Self.encodeZigZag(Int64(v)))
    }

    // MARK: - Fixed-Width Little-Endian Numbers

    @inlinable
    @inline(__always)
    public mutating func appendFixed32(_ v: UInt32) {
        ensureCapacity(4)
        UnsafeMutableRawPointer(ptr.advanced(by: count)).storeBytes(of: v.littleEndian, as: UInt32.self)
        count &+= 4
    }

    @inlinable
    @inline(__always)
    public mutating func appendFixed64(_ v: UInt64) {
        ensureCapacity(8)
        UnsafeMutableRawPointer(ptr.advanced(by: count)).storeBytes(of: v.littleEndian, as: UInt64.self)
        count &+= 8
    }

    @inlinable
    @inline(__always)
    public mutating func appendSfixed32(_ v: Int32) {
        appendFixed32(UInt32(bitPattern: v))
    }

    @inlinable
    @inline(__always)
    public mutating func appendSfixed64(_ v: Int64) {
        appendFixed64(UInt64(bitPattern: v))
    }

    @inlinable
    @inline(__always)
    public mutating func appendFloat32(_ v: Float) {
        appendFixed32(v.bitPattern)
    }

    @inlinable
    @inline(__always)
    public mutating func appendFloat64(_ v: Double) {
        appendFixed64(v.bitPattern)
    }

    // MARK: - Strings & Bytes

    @inlinable
    @inline(__always)
    public mutating func appendString(_ s: String) {
        var str = s
        let wrote = str.withUTF8 { utf8 -> Bool in
            appendVarint(UInt64(utf8.count))
            if let base = utf8.baseAddress, !utf8.isEmpty {
                appendRaw(base, count: utf8.count)
            }
            return true
        }
        _ = wrote
    }

    @inlinable
    @inline(__always)
    public mutating func appendStringValue(_ s: String) {
        if let wrote = s.utf8.withContiguousStorageIfAvailable({ utf8 -> Bool in
            appendVarint(UInt64(utf8.count))
            if let base = utf8.baseAddress, !utf8.isEmpty {
                appendRaw(base, count: utf8.count)
            }
            return true
        }), wrote {
            return
        }
        appendString(s)
    }

    @inlinable
    @inline(__always)
    public mutating func appendBytes(_ bytes: [UInt8]) {
        appendVarint(UInt64(bytes.count))
        appendRaw(bytes)
    }

    // MARK: - Single-Pass Container Length Backpatching

    /// Reserves a 2-byte Prefix-Varint length slot and returns its offset.
    @inlinable
    @inline(__always)
    public mutating func reserveLength2() -> Int {
        let pos = count
        appendTwoBytes(0, 0)
        return pos
    }

    /// Patches the 2-byte length slot reserved at `lenPos`, widening to 4 or 9 bytes if needed.
    @inlinable
    @inline(__always)
    public mutating func backpatchLength2(at lenPos: Int) {
        let bodyLen = count &- lenPos &- 2
        if bodyLen <= 0x3FFF {
            let enc = UInt16(truncatingIfNeeded: (UInt32(bodyLen) &<< 2) | 2).littleEndian
            UnsafeMutableRawPointer(ptr.advanced(by: lenPos)).storeBytes(of: enc, as: UInt16.self)
        } else {
            backpatchLength2Slow(at: lenPos, bodyLen: bodyLen)
        }
    }

    @usableFromInline
    @inline(never)
    internal mutating func backpatchLength2Slow(at lenPos: Int, bodyLen: Int) {
        if bodyLen <= 0x1FFF_FFFF {
            ensureCapacity(2)
            let bodySrc = ptr.advanced(by: lenPos &+ 2)
            let bodyDst = ptr.advanced(by: lenPos &+ 4)
            UnsafeMutableRawPointer(bodyDst).copyMemory(from: UnsafeRawPointer(bodySrc), byteCount: bodyLen)
            let enc = UInt32(truncatingIfNeeded: (UInt64(bodyLen) &<< 3) | 4).littleEndian
            UnsafeMutableRawPointer(ptr.advanced(by: lenPos)).storeBytes(of: enc, as: UInt32.self)
            count &+= 2
        } else {
            ensureCapacity(7)
            let bodySrc = ptr.advanced(by: lenPos &+ 2)
            let bodyDst = ptr.advanced(by: lenPos &+ 9)
            UnsafeMutableRawPointer(bodyDst).copyMemory(from: UnsafeRawPointer(bodySrc), byteCount: bodyLen)
            ptr[lenPos] = 0
            let enc = UInt64(bodyLen).littleEndian
            UnsafeMutableRawPointer(ptr.advanced(by: lenPos &+ 1)).storeBytes(of: enc, as: UInt64.self)
            count &+= 7
        }
    }

    /// Reserves a 4-byte Prefix-Varint length slot (avoids shifting for containers >16 KiB).
    @inlinable
    @inline(__always)
    public mutating func reserveLength4() -> Int {
        let pos = count
        appendFourBytes(0, 0, 0, 0)
        return pos
    }

    /// Patches a 4-byte length slot reserved at `lenPos`, widening to 9 bytes if >512 MiB.
    @inlinable
    @inline(__always)
    public mutating func backpatchLength4(at lenPos: Int) {
        let bodyLen = count &- lenPos &- 4
        if bodyLen <= 0x1FFF_FFFF {
            let enc = UInt32(truncatingIfNeeded: (UInt64(bodyLen) &<< 3) | 4).littleEndian
            UnsafeMutableRawPointer(ptr.advanced(by: lenPos)).storeBytes(of: enc, as: UInt32.self)
        } else {
            ensureCapacity(5)
            let bodySrc = ptr.advanced(by: lenPos &+ 4)
            let bodyDst = ptr.advanced(by: lenPos &+ 9)
            UnsafeMutableRawPointer(bodyDst).copyMemory(from: UnsafeRawPointer(bodySrc), byteCount: bodyLen)
            ptr[lenPos] = 0
            let enc = UInt64(bodyLen).littleEndian
            UnsafeMutableRawPointer(ptr.advanced(by: lenPos &+ 1)).storeBytes(of: enc, as: UInt64.self)
            count &+= 5
        }
    }

    /// Truncates the buffer back to `newCount` (used for error rollback).
    @inlinable
    @inline(__always)
    public mutating func truncate(to newCount: Int) {
        precondition(newCount >= 0, "OmniBufWriter.truncate newCount must be non-negative")
        if newCount < count {
            count = newCount
        }
    }
}

/// Compares two strings in unsigned UTF-8 byte order (per OmniBuf v0.1 deterministic map sorting).
@inlinable
public func compareUTF8Bytes(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
}
