import SwiftProtobufPluginLibrary

extension OmniBufCodeGenerator {
    // MARK: - Lazy Opaque View & Splicer Generation

    func emitOpaqueView(_ msg: Descriptor, into out: inout String, indent: String) {
        let name = swiftTypeName(msg)
        let opaqueName = "Opaque\(name)"
        let fields = msg.fields.sorted { $0.number < $1.number }
        let maxFieldNum = fields.map(\.number).max() ?? 0
        let hasHighFields = fields.contains { $0.number >= 64 }

        out += "\(indent)public struct \(opaqueName): Sendable {\n"
        out += "\(indent)    public let raw: [UInt8]\n"
        out += "\(indent)    public let offset: Int\n"
        out += "\(indent)    public let length: Int\n"
        out += "\(indent)    @usableFromInline internal var dirtyMask: UInt64 = 0\n"
        if hasHighFields {
            out += "\(indent)    @usableFromInline internal var dirtyHigh: Set<UInt32> = []\n"
        }
        for f in fields {
            out += "\(indent)    @usableFromInline internal var dirty_\(f.name): \(swiftFieldType(f, in: msg)) = \(defaultValue(f))\n"
        }
        out += "\n\(indent)    @inlinable\n"
        out += "\(indent)    public init(_ raw: [UInt8]) {\n"
        out += "\(indent)        self.raw = raw\n"
        out += "\(indent)        self.offset = 0\n"
        out += "\(indent)        self.length = raw.count\n"
        out += "\(indent)    }\n\n"
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public init(raw: [UInt8], offset: Int, length: Int) {\n"
        out += "\(indent)        precondition(offset >= 0 && length >= 0 && offset <= raw.count && length <= raw.count - offset, \"\(opaqueName) slice out of bounds\")\n"
        out += "\(indent)        self.raw = raw\n"
        out += "\(indent)        self.offset = offset\n"
        out += "\(indent)        self.length = length\n"
        out += "\(indent)    }\n\n"
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    @inline(__always)\n"
        out += "\(indent)    internal func withSlice<R>(_ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {\n"
        out += "\(indent)        raw.withUnsafeBufferPointer { buf in\n"
        out += "\(indent)            body(UnsafeBufferPointer(start: buf.baseAddress?.advanced(by: offset), count: length))\n"
        out += "\(indent)        }\n"
        out += "\(indent)    }\n\n"

        // Getters & Setters
        for f in fields {
            let pName = pascalCase(f.name)
            let num = f.number
            let isDirtyExpr = num < 64 ? "(dirtyMask & (1 &<< \(num))) != 0" : "dirtyHigh.contains(\(num))"
            let markDirtyStmt = num < 64 ? "dirtyMask |= (1 &<< \(num))" : "dirtyHigh.insert(\(num))"

            if f.isMap {
                let entry = f.messageType!
                if entry.fields[0].type == .string && entry.fields[1].type == .uint64 {
                    out += "\(indent)    @inlinable\n"
                    out += "\(indent)    public func lookup\(pName)(_ key: String) -> UInt64? {\n"
                    out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name)[key] }\n"
                    out += "\(indent)        return withSlice { OpaqueWire.lookupMapStringUint64(in: $0, fieldNumber: \(num), key: key) }\n"
                    out += "\(indent)    }\n"
                }
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(swiftFieldType(f, in: msg))) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else if f.isRepeated {
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public var \(camelCaseRaw(f.name))Count: Int {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name).count }\n"
                out += "\(indent)        return withSlice { OpaqueWire.arrayCount(in: $0, fieldNumber: \(num), expectedElemType: \(wireTypeExpr(f))) }\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(swiftFieldType(f, in: msg))) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else if f.type == .message {
                let subName = swiftTypeName(f.messageType!)
                let isIndirect = isCyclicSingularField(f, in: msg)
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> Opaque\(subName) {\n"
                out += "\(indent)        if \(isDirtyExpr) {\n"
                if isIndirect {
                    out += "\(indent)            return Opaque\(subName)((try? dirty_\(f.name)?.value.marshalOmniBuf()) ?? [])\n"
                } else {
                    out += "\(indent)            return Opaque\(subName)((try? dirty_\(f.name)?.marshalOmniBuf()) ?? [])\n"
                }
                out += "\(indent)        }\n"
                out += "\(indent)        return withSlice { slice in\n"
                out += "\(indent)            guard let loc = OpaqueWire.locateSubMsgRange(in: slice, fieldNumber: \(num)) else {\n"
                out += "\(indent)                return Opaque\(subName)(raw: [], offset: 0, length: 0)\n"
                out += "\(indent)            }\n"
                out += "\(indent)            if !loc.multiple {\n"
                out += "\(indent)                return Opaque\(subName)(raw: raw, offset: offset &+ loc.start, length: loc.end &- loc.start)\n"
                out += "\(indent)            }\n"
                out += "\(indent)            return Opaque\(subName)(OpaqueWire.readMergedSubMsgBytes(in: slice, fieldNumber: \(num)))\n"
                out += "\(indent)        }\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(subName)?) {\n"
                if isIndirect {
                    out += "\(indent)        dirty_\(f.name) = value.map(Indirect.init)\n"
                } else {
                    out += "\(indent)        dirty_\(f.name) = value\n"
                }
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else if f.type == .enum {
                let enumName = swiftEnumName(f.enumType!)
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> \(enumName) {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name) }\n"
                out += "\(indent)        return \(enumName)(rawValue: withSlice { OpaqueWire.readSint32(in: $0, fieldNumber: \(num)) }) ?? \(enumName)()\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(enumName)) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else {
                let readFn: String
                switch f.type {
                case .uint32: readFn = "readUint32"
                case .uint64: readFn = "readUint64"
                case .int32, .sint32: readFn = "readSint32"
                case .int64, .sint64: readFn = "readSint64"
                case .bool: readFn = "readBool"
                case .fixed32: readFn = "readFixed32"
                case .fixed64: readFn = "readFixed64"
                case .sfixed32: readFn = "readSfixed32"
                case .sfixed64: readFn = "readSfixed64"
                case .float: readFn = "readFloat32"
                case .double: readFn = "readFloat64"
                case .string: readFn = "readString"
                case .bytes: readFn = "readBytes"
                default: readFn = "readUint32"
                }
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> \(swiftFieldType(f, in: msg)) {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name) }\n"
                out += "\(indent)        return withSlice { OpaqueWire.\(readFn)(in: $0, fieldNumber: \(num)) }\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(swiftFieldType(f, in: msg))) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            }
        }

        // Dirty field encoder + marshal / tryMarshal
        out += "\n\(indent)    @inlinable\n"
        out += "\(indent)    internal func appendDirtyField(_ fnum: UInt32, into w: inout OmniBufWriter) throws {\n"
        out += "\(indent)        let deterministic = true\n"
        out += "\(indent)        let depth = 0\n"
        out += "\(indent)        _ = deterministic\n"
        out += "\(indent)        _ = depth\n"
        out += "\(indent)        switch fnum {\n"
        for f in fields {
            out += "\(indent)        case \(f.number):\n"
            emitEncodeField(f, in: msg, target: "self.dirty_\(f.name)", into: &out, indent: indent + "            ")
        }
        out += "\(indent)        default:\n"
        out += "\(indent)            break\n"
        out += "\(indent)        }\n"
        out += "\(indent)    }\n\n"

        let cleanCond = hasHighFields ? "dirtyMask == 0 && dirtyHigh.isEmpty" : "dirtyMask == 0"
        let dirtyHighArg = hasHighFields ? ", dirtyHigh: dirtyHigh" : ""

        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func marshal() -> [UInt8] {\n"
        out += "\(indent)        if \(cleanCond) {\n"
        out += "\(indent)            if offset == 0 && length == raw.count { return raw }\n"
        out += "\(indent)            return Array(raw[offset..<(offset + length)])\n"
        out += "\(indent)        }\n"
        out += "\(indent)        var dst: [UInt8] = []\n"
        out += "\(indent)        OpaqueWire.spliceFields(into: &dst, raw: raw, offset: offset, length: length, dirtyMask: dirtyMask\(dirtyHighArg), maxField: \(maxFieldNum)) { w, fnum in\n"
        out += "\(indent)            try? self.appendDirtyField(fnum, into: &w)\n"
        out += "\(indent)        }\n"
        out += "\(indent)        return dst\n"
        out += "\(indent)    }\n\n"

        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func tryMarshal() throws -> [UInt8] {\n"
        out += "\(indent)        var dst: [UInt8] = []\n"
        out += "\(indent)        try OpaqueWire.trySpliceFields(into: &dst, raw: raw, offset: offset, length: length, dirtyMask: dirtyMask\(dirtyHighArg), maxField: \(maxFieldNum)) { w, fnum in\n"
        out += "\(indent)            try self.appendDirtyField(fnum, into: &w)\n"
        out += "\(indent)        }\n"
        out += "\(indent)        return dst\n"
        out += "\(indent)    }\n"
        out += "\(indent)}\n\n"
    }
}
