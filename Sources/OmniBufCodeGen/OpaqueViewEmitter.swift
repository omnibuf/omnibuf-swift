import SwiftProtobufPluginLibrary

extension OmniBufCodeGenerator {
    // MARK: - Lazy Opaque View & Splicer Generation

    private func opaqueReadFn(for f: FieldDescriptor) -> String {
        switch f.type {
        case .uint32: return "readUint32"
        case .uint64: return "readUint64"
        case .int32, .sint32: return "readSint32"
        case .int64, .sint64: return "readSint64"
        case .bool: return "readBool"
        case .fixed32: return "readFixed32"
        case .fixed64: return "readFixed64"
        case .sfixed32: return "readSfixed32"
        case .sfixed64: return "readSfixed64"
        case .float: return "readFloat32"
        case .double: return "readFloat64"
        case .string: return "readString"
        case .bytes: return "readBytes"
        default: return "readUint32"
        }
    }

    func emitOpaqueView(_ msg: Descriptor, into out: inout String, indent: String) {
        let name = swiftTypeName(msg)
        let opaqueName = "Opaque\(name)"
        let fields = msg.fields.sorted { $0.number < $1.number }
        let regularFields = fields.filter { $0.realContainingOneof == nil }
        let realOneofs = msg.realOneofs.filter { !$0.fields.isEmpty }
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
        for f in regularFields {
            out += "\(indent)    @usableFromInline internal var dirty_\(f.name): \(swiftFieldType(f, in: msg)) = \(defaultValue(f))\n"
        }
        for oneof in realOneofs {
            out += "\(indent)    @usableFromInline internal var dirty_oneof_\(oneof.name): \(name).\(swiftOneofEnumName(oneof))? = nil\n"
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

        // Regular field Getters & Setters
        for f in regularFields {
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
            } else if isMessageField(f) {
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
                let presenceSuffix = editionPresence(f) ? "?" : ""
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> \(enumName)\(presenceSuffix) {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name) }\n"
                if editionPresence(f) {
                    out += "\(indent)        guard withSlice({ OpaqueWire.locateLastField(in: $0, fieldNumber: \(num), expectedWireType: WireType.wireSint) }) != nil else { return nil }\n"
                }
                out += "\(indent)        return \(enumName)(rawValue: withSlice { OpaqueWire.readSint32(in: $0, fieldNumber: \(num)) }) ?? \(enumName)()\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(enumName)\(presenceSuffix)) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else if f.type == .bool && editionPresence(f) {
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> Bool? {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name) }\n"
                out += "\(indent)        guard let loc = withSlice({ OpaqueWire.locateLastField(in: $0, fieldNumber: \(num), expectedWireType: WireType.wireBoolFalse) }) else { return nil }\n"
                out += "\(indent)        return loc.wireType == WireType.wireBoolTrue\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: Bool?) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            } else {
                let readFn = opaqueReadFn(for: f)
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public func get\(pName)() -> \(swiftFieldType(f, in: msg)) {\n"
                out += "\(indent)        if \(isDirtyExpr) { return dirty_\(f.name) }\n"
                if editionPresence(f) {
                    out += "\(indent)        guard withSlice({ OpaqueWire.locateLastField(in: $0, fieldNumber: \(num), expectedWireType: \(wireTypeExpr(f))) }) != nil else { return nil }\n"
                }
                out += "\(indent)        return withSlice { OpaqueWire.\(readFn)(in: $0, fieldNumber: \(num)) }\n"
                out += "\(indent)    }\n"
                out += "\(indent)    @inlinable\n"
                out += "\(indent)    public mutating func set\(pName)(_ value: \(swiftFieldType(f, in: msg))) {\n"
                out += "\(indent)        dirty_\(f.name) = value\n"
                out += "\(indent)        \(markDirtyStmt)\n"
                out += "\(indent)    }\n"
            }
        }

        // Oneof Getters & Setters
        for oneof in realOneofs {
            let oneofFields = oneof.fields.sorted { $0.number < $1.number }
            let oneofPascal = pascalCase(oneof.name)
            let oneofType = "\(name).\(swiftOneofEnumName(oneof))"
            let firstNum = oneofFields[0].number
            let isOneofDirtyExpr = firstNum < 64 ? "(dirtyMask & (1 &<< \(firstNum))) != 0" : "dirtyHigh.contains(\(firstNum))"
            let candidatesLiteral = oneofFields
                .map { "(UInt32(\($0.number)), \(wireTypeExpr($0)))" }
                .joined(separator: ", ")

            out += "\(indent)    @inlinable\n"
            out += "\(indent)    public func get\(oneofPascal)() -> \(oneofType)? {\n"
            out += "\(indent)        if \(isOneofDirtyExpr) { return dirty_oneof_\(oneof.name) }\n"
            out += "\(indent)        let candidates: [(fieldNumber: UInt32, expectedWireType: UInt8)] = [\(candidatesLiteral)]\n"
            out += "\(indent)        guard let activeField = withSlice({ OpaqueWire.locateLastOneofField(in: $0, candidates: candidates) }) else { return nil }\n"
            out += "\(indent)        switch activeField {\n"
            for bf in oneofFields {
                let bCase = camelCase(bf.name)
                let num = bf.number
                out += "\(indent)        case \(num):\n"
                if isMessageField(bf) {
                    let subType = swiftTypeName(bf.messageType!)
                    let isIndirect = isCyclicSingularField(bf, in: msg)
                    out += "\(indent)            let subBytes = withSlice { OpaqueWire.readOneofSubMsgBytes(in: $0, fieldNumber: \(num), candidates: candidates) }\n"
                    out += "\(indent)            guard let sub = try? \(subType).decoded(from: subBytes) else { return nil }\n"
                    out += "\(indent)            return .\(bCase)(\(isIndirect ? "Indirect(sub)" : "sub"))\n"
                } else if bf.type == .enum {
                    let enumName = swiftEnumName(bf.enumType!)
                    out += "\(indent)            return .\(bCase)(\(enumName)(rawValue: withSlice { OpaqueWire.readSint32(in: $0, fieldNumber: \(num)) }) ?? \(enumName)())\n"
                } else {
                    let readFn = opaqueReadFn(for: bf)
                    out += "\(indent)            return .\(bCase)(withSlice { OpaqueWire.\(readFn)(in: $0, fieldNumber: \(num)) })\n"
                }
            }
            out += "\(indent)        default:\n"
            out += "\(indent)            return nil\n"
            out += "\(indent)        }\n"
            out += "\(indent)    }\n"

            out += "\(indent)    @inlinable\n"
            out += "\(indent)    public mutating func set\(oneofPascal)(_ value: \(oneofType)?) {\n"
            out += "\(indent)        dirty_oneof_\(oneof.name) = value\n"
            for bf in oneofFields {
                if bf.number < 64 {
                    out += "\(indent)        dirtyMask |= (1 &<< \(bf.number))\n"
                } else {
                    out += "\(indent)        dirtyHigh.insert(\(bf.number))\n"
                }
            }
            out += "\(indent)    }\n"

            // Per-branch convenience getters & setters
            for bf in oneofFields {
                let bPascal = pascalCase(bf.name)
                let bCase = camelCase(bf.name)
                let num = bf.number
                if isMessageField(bf) {
                    let subName = swiftTypeName(bf.messageType!)
                    let isIndirect = isCyclicSingularField(bf, in: msg)
                    out += "\(indent)    @inlinable\n"
                    out += "\(indent)    public func get\(bPascal)() -> Opaque\(subName)? {\n"
                    out += "\(indent)        if \(isOneofDirtyExpr) {\n"
                    out += "\(indent)            guard case .\(bCase)(let sub) = dirty_oneof_\(oneof.name) else { return nil }\n"
                    out += "\(indent)            return Opaque\(subName)((try? sub\(isIndirect ? ".value" : "").marshalOmniBuf()) ?? [])\n"
                    out += "\(indent)        }\n"
                    out += "\(indent)        let candidates: [(fieldNumber: UInt32, expectedWireType: UInt8)] = [\(candidatesLiteral)]\n"
                    out += "\(indent)        return withSlice { slice in\n"
                    out += "\(indent)            guard let loc = OpaqueWire.locateOneofSubMsgRange(in: slice, fieldNumber: \(num), candidates: candidates) else {\n"
                    out += "\(indent)                return nil\n"
                    out += "\(indent)            }\n"
                    out += "\(indent)            if !loc.multiple {\n"
                    out += "\(indent)                return Opaque\(subName)(raw: raw, offset: offset &+ loc.start, length: loc.end &- loc.start)\n"
                    out += "\(indent)            }\n"
                    out += "\(indent)            return Opaque\(subName)(OpaqueWire.readOneofSubMsgBytes(in: slice, fieldNumber: \(num), candidates: candidates))\n"
                    out += "\(indent)        }\n"
                    out += "\(indent)    }\n"
                    out += "\(indent)    @inlinable\n"
                    out += "\(indent)    public mutating func set\(bPascal)(_ value: \(subName)?) {\n"
                    if isIndirect {
                        out += "\(indent)        set\(oneofPascal)(value.map { .\(bCase)(Indirect($0)) })\n"
                    } else {
                        out += "\(indent)        set\(oneofPascal)(value.map { .\(bCase)($0) })\n"
                    }
                    out += "\(indent)    }\n"
                } else {
                    let baseType = swiftSingularBaseType(bf)
                    out += "\(indent)    @inlinable\n"
                    out += "\(indent)    public func get\(bPascal)() -> \(baseType)? {\n"
                    out += "\(indent)        if case .\(bCase)(let v) = get\(oneofPascal)() { return v }\n"
                    out += "\(indent)        return nil\n"
                    out += "\(indent)    }\n"
                    out += "\(indent)    @inlinable\n"
                    out += "\(indent)    public mutating func set\(bPascal)(_ value: \(baseType)) {\n"
                    out += "\(indent)        set\(oneofPascal)(.\(bCase)(value))\n"
                    out += "\(indent)    }\n"
                }
            }
        }

        // Dirty field encoder + marshal / tryMarshal
        out += "\n\(indent)    @inlinable\n"
        out += "\(indent)    internal func appendDirtyField(_ fnum: UInt32, into w: inout OmniBufWriter) throws {\n"
        out += "\(indent)        let depth = 0\n"
        out += "\(indent)        _ = depth\n"
        out += "\(indent)        switch fnum {\n"
        for f in fields {
            out += "\(indent)        case \(f.number):\n"
            if let oneof = f.realContainingOneof {
                emitEncodeOneofBranch(
                    f,
                    in: msg,
                    oneofExpr: "self.dirty_oneof_\(oneof.name)",
                    into: &out,
                    indent: indent + "            ",
                    alwaysDeterministic: true
                )
            } else {
                emitEncodeField(
                    f,
                    in: msg,
                    target: "self.dirty_\(f.name)",
                    into: &out,
                    indent: indent + "            ",
                    alwaysDeterministic: true
                )
            }
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
