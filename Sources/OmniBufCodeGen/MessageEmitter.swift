import SwiftProtobufPluginLibrary

extension OmniBufCodeGenerator {
    // MARK: - Enum Generation

    func emitEnum(_ e: EnumDescriptor, into out: inout String, indent: String) {
        let name = swiftEnumName(e)
        if isEditionsFile(e.file) {
            out += "\(indent)public enum \(name): RawRepresentable, Sendable, Equatable, Hashable {\n"
            out += "\(indent)    public typealias RawValue = Int32\n\n"
            var seenRawValues: [Int32: String] = [:]
            var canonicalCases: [(number: Int32, caseName: String)] = []
            for val in e.values {
                let caseName = camelCase(val.name)
                if let existingCase = seenRawValues[val.number] {
                    out += "\(indent)    public static let \(caseName): \(name) = .\(existingCase)\n"
                } else {
                    seenRawValues[val.number] = caseName
                    canonicalCases.append((val.number, caseName))
                    out += "\(indent)    case \(caseName)\n"
                }
            }
            out += "\(indent)    case UNRECOGNIZED(Int32)\n\n"
            let defaultCase = seenRawValues[0] ?? canonicalCases.first?.caseName ?? "UNRECOGNIZED(0)"
            if seenRawValues[0] != nil || canonicalCases.first != nil {
                out += "\(indent)    public init() { self = .\(defaultCase) }\n\n"
            } else {
                out += "\(indent)    public init() { self = .UNRECOGNIZED(0) }\n\n"
            }
            out += "\(indent)    public init?(rawValue: Int32) {\n"
            out += "\(indent)        switch rawValue {\n"
            for entry in canonicalCases {
                out += "\(indent)        case \(entry.number): self = .\(entry.caseName)\n"
            }
            out += "\(indent)        default: self = .UNRECOGNIZED(rawValue)\n"
            out += "\(indent)        }\n"
            out += "\(indent)    }\n\n"
            out += "\(indent)    public var rawValue: Int32 {\n"
            out += "\(indent)        switch self {\n"
            for entry in canonicalCases {
                out += "\(indent)        case .\(entry.caseName): return \(entry.number)\n"
            }
            out += "\(indent)        case .UNRECOGNIZED(let v): return v\n"
            out += "\(indent)        }\n"
            out += "\(indent)    }\n"
            out += "\(indent)}\n\n"
            return
        }

        out += "\(indent)public enum \(name): Int32, Sendable, Equatable, Hashable {\n"
        var seenRawValues: [Int32: String] = [:]
        for val in e.values {
            let caseName = camelCase(val.name)
            if let existingCase = seenRawValues[val.number] {
                out += "\(indent)    public static let \(caseName): \(name) = .\(existingCase)\n"
            } else {
                seenRawValues[val.number] = caseName
                out += "\(indent)    case \(caseName) = \(val.number)\n"
            }
        }
        out += "\(indent)    public init() { self = .\(camelCase(e.values.first?.name ?? "unspecified")) }\n"
        out += "\(indent)}\n\n"
    }

    // MARK: - Message Generation

    func emitMessage(_ msg: Descriptor, into out: inout String, indent: String) {
        if msg.options.mapEntry { return }

        for nested in msg.messages where !nested.options.mapEntry {
            emitMessage(nested, into: &out, indent: indent)
        }
        for nestedEnum in msg.enums {
            emitEnum(nestedEnum, into: &out, indent: indent)
        }

        let name = swiftTypeName(msg)
        let fields = msg.fields.sorted { $0.number < $1.number }
        let regularFields = fields.filter { $0.realContainingOneof == nil }
        let realOneofs = msg.realOneofs.filter { !$0.fields.isEmpty }

        // Struct declaration
        out += "\(indent)public struct \(name): OmniBufMessage, Equatable, Sendable {\n"

        // Nested OneOf enums
        for oneof in realOneofs {
            let enumName = swiftOneofEnumName(oneof)
            out += "\(indent)    public enum \(enumName): Equatable, Sendable {\n"
            for bf in oneof.fields.sorted(by: { $0.number < $1.number }) {
                out += "\(indent)        case \(camelCase(bf.name))(\(swiftOneofCasePayloadType(bf, in: msg)))\n"
            }
            out += "\(indent)    }\n\n"
        }

        for f in regularFields {
            out += "\(indent)    public var \(camelCase(f.name)): \(swiftFieldType(f, in: msg))\n"
        }
        for oneof in realOneofs {
            out += "\(indent)    public var \(camelCase(oneof.name)): \(swiftOneofEnumName(oneof))?\n"
        }

        let initParams: [(name: String, type: String, defaultExpr: String)] =
            regularFields.map { (camelCase($0.name), swiftFieldType($0, in: msg), defaultValue($0)) }
            + realOneofs.map { (camelCase($0.name), "\(swiftOneofEnumName($0))?", "nil") }

        if initParams.isEmpty {
            out += "\n\(indent)    public init() {}\n\n"
        } else {
            out += "\n\(indent)    public init(\n"
            for (i, param) in initParams.enumerated() {
                let comma = i + 1 < initParams.count ? "," : ""
                out += "\(indent)        \(param.name): \(param.type) = \(param.defaultExpr)\(comma)\n"
            }
            out += "\(indent)    ) {\n"
            for param in initParams {
                out += "\(indent)        self.\(param.name) = \(param.name)\n"
            }
            out += "\(indent)    }\n\n"
            out += "\(indent)    public init() {\n"
            out += "\(indent)        self.init(\(initParams[0].name): \(initParams[0].defaultExpr))\n"
            out += "\(indent)    }\n\n"
        }

        // Single-pass O(N) depth-bounded size hint for initial OmniBufWriter capacity
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public var estimatedOmniBufSize: Int {\n"
        out += "\(indent)        estimatedOmniBufSize(depth: 0)\n"
        out += "\(indent)    }\n\n"
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func estimatedOmniBufSize(depth: Int) -> Int {\n"
        var sizeBody = ""
        for f in regularFields {
            let p = camelCase(f.name)
            if f.isMap {
                sizeBody += "\(indent)        n &+= \(p).count &* 24\n"
            } else if f.isRepeated {
                if f.type == .string {
                    sizeBody += "\(indent)        for s in \(p) { n &+= s.utf8.count &+ 4 }\n"
                } else if f.type == .bytes {
                    sizeBody += "\(indent)        for b in \(p) { n &+= b.count &+ 4 }\n"
                } else if isMessageField(f) {
                    sizeBody += "\(indent)        if depth < WireType.maxNestingDepth {\n"
                    sizeBody += "\(indent)            for m in \(p) { n &+= m.estimatedOmniBufSize(depth: depth &+ 1) &+ 4 }\n"
                    sizeBody += "\(indent)        } else {\n"
                    sizeBody += "\(indent)            n &+= \(p).count &* 16\n"
                    sizeBody += "\(indent)        }\n"
                } else {
                    sizeBody += "\(indent)        n &+= \(p).count &* 8\n"
                }
            } else if f.type == .string {
                if editionPresence(f) {
                    sizeBody += "\(indent)        if let v = \(p) { n &+= v.utf8.count }\n"
                } else {
                    sizeBody += "\(indent)        n &+= \(p).utf8.count\n"
                }
            } else if f.type == .bytes {
                if editionPresence(f) {
                    sizeBody += "\(indent)        if let v = \(p) { n &+= v.count }\n"
                } else {
                    sizeBody += "\(indent)        n &+= \(p).count\n"
                }
            } else if isMessageField(f) {
                if isCyclicSingularField(f, in: msg) {
                    sizeBody += "\(indent)        if let box = \(p), depth < WireType.maxNestingDepth { n &+= box.value.estimatedOmniBufSize(depth: depth &+ 1) &+ 4 }\n"
                } else {
                    sizeBody += "\(indent)        if let m = \(p), depth < WireType.maxNestingDepth { n &+= m.estimatedOmniBufSize(depth: depth &+ 1) &+ 4 }\n"
                }
            }
        }
        for oneof in realOneofs {
            let sizedBranches = oneof.fields.filter { $0.type == .string || $0.type == .bytes || isMessageField($0) }
            if !sizedBranches.isEmpty {
                sizeBody += "\(indent)        switch \(camelCase(oneof.name)) {\n"
                for bf in sizedBranches.sorted(by: { $0.number < $1.number }) {
                    let c = camelCase(bf.name)
                    if bf.type == .string {
                        sizeBody += "\(indent)        case .\(c)(let v): n &+= v.utf8.count\n"
                    } else if bf.type == .bytes {
                        sizeBody += "\(indent)        case .\(c)(let v): n &+= v.count\n"
                    } else if isMessageField(bf) {
                        if isCyclicSingularField(bf, in: msg) {
                            sizeBody += "\(indent)        case .\(c)(let box): if depth < WireType.maxNestingDepth { n &+= box.value.estimatedOmniBufSize(depth: depth &+ 1) &+ 4 }\n"
                        } else {
                            sizeBody += "\(indent)        case .\(c)(let m): if depth < WireType.maxNestingDepth { n &+= m.estimatedOmniBufSize(depth: depth &+ 1) &+ 4 }\n"
                        }
                    }
                }
                sizeBody += "\(indent)        default: break\n"
                sizeBody += "\(indent)        }\n"
            }
        }
        let baseSize = max(fields.count * 4, 16)
        if sizeBody.isEmpty {
            out += "\(indent)        return \(baseSize)\n"
        } else {
            out += "\(indent)        var n = \(baseSize)\n"
            out += sizeBody
            out += "\(indent)        return n\n"
        }
        out += "\(indent)    }\n\n"

        // Fast marshalOmniBuf() convenience
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func marshalOmniBuf() throws -> [UInt8] {\n"
        out += "\(indent)        var w = OmniBufWriter(initialCapacity: max(256, estimatedOmniBufSize))\n"
        out += "\(indent)        try encodeOmniBufBodyFast(into: &w, deterministic: true, depth: 0)\n"
        out += "\(indent)        return w.toBytes()\n"
        out += "\(indent)    }\n\n"

        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func encodeOmniBufBody(into writer: inout OmniBufWriter, options: EncodeOptions) throws {\n"
        out += "\(indent)        try encodeOmniBufBodyFast(into: &writer, deterministic: options.deterministic, depth: 0)\n"
        out += "\(indent)    }\n\n"

        // Fast single-pass encoder with nesting depth limit (canonical field number order)
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public func encodeOmniBufBodyFast(into w: inout OmniBufWriter, deterministic: Bool, depth: Int = 0) throws {\n"
        out += "\(indent)        guard depth <= WireType.maxNestingDepth else {\n"
        out += "\(indent)            throw OmniBufError.depthLimitExceeded(depth)\n"
        out += "\(indent)        }\n"
        for f in fields {
            if let oneof = f.realContainingOneof {
                emitEncodeOneofBranch(f, in: msg, oneofExpr: "self.\(camelCase(oneof.name))", into: &out, indent: indent + "        ")
            } else {
                emitEncodeField(f, in: msg, target: "self.\(camelCase(f.name))", into: &out, indent: indent + "        ")
            }
        }
        out += "\(indent)    }\n\n"

        // Fast decoder (merge mode)
        out += "\(indent)    @inlinable\n"
        out += "\(indent)    public mutating func mergeOmniBuf(from data: UnsafeBufferPointer<UInt8>, depth: Int, budget: inout DecodeBudget) throws {\n"
        out += "\(indent)        guard depth <= budget.maxDepth else {\n"
        out += "\(indent)            throw OmniBufError.depthLimitExceeded(depth)\n"
        out += "\(indent)        }\n"
        out += "\(indent)        var r = OmniBufReader(data)\n"
        out += "\(indent)        while !r.isAtEnd {\n"
        out += "\(indent)            let (fnum, wt) = try r.readTag()\n"
        out += "\(indent)            switch fnum {\n"
        out += "\(indent)            case 0:\n"
        out += "\(indent)                guard wt == WireType.wireSubMsg else {\n"
        out += "\(indent)                    throw OmniBufError.parse(\"Field #0 must have WireSubMsg (12), got \\(wt)\")\n"
        out += "\(indent)                }\n"
        out += "\(indent)                let slice = try r.readLenSlice()\n"
        out += "\(indent)                try SchemaMeta.validateSlice(slice, depth: depth &+ 1, budget: &budget)\n"
        for f in fields {
            if let oneof = f.realContainingOneof {
                emitDecodeOneofBranch(f, in: msg, oneof: oneof, into: &out, indent: indent + "            ")
            } else {
                emitDecodeField(f, in: msg, into: &out, indent: indent + "            ")
            }
        }
        out += "\(indent)            default:\n"
        out += "\(indent)                try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
        out += "\(indent)            }\n"
        out += "\(indent)        }\n"
        out += "\(indent)    }\n\n"

        // Field #0 SchemaMeta (cycle-safe for self- and mutually-recursive messages)
        out += "\(indent)    public static var omniBufSchemaMeta: SchemaMeta {\n"
        out += "\(indent)        var visited: Set<String> = []\n"
        out += "\(indent)        return buildOmniBufSchemaMeta(visited: &visited)\n"
        out += "\(indent)    }\n\n"
        out += "\(indent)    public static func buildOmniBufSchemaMeta(visited: inout Set<String>) -> SchemaMeta {\n"
        out += "\(indent)        \(fields.isEmpty ? "let" : "var") fields: [UInt32: String] = [:]\n"
        var hasChildMeta = false
        for f in fields {
            if f.isMap {
                let vField = f.messageType!.fields[1]
                if isMessageField(vField) {
                    hasChildMeta = true
                }
            } else if isMessageField(f) {
                hasChildMeta = true
            }
        }
        out += "\(indent)        \(hasChildMeta ? "var" : "let") children: [UInt32: SchemaMeta] = [:]\n"
        if hasChildMeta {
            out += "\(indent)        let typeKey = \"\(msg.fullName)\"\n"
            out += "\(indent)        let inserted = visited.insert(typeKey).inserted\n"
            out += "\(indent)        defer { if inserted { visited.remove(typeKey) } }\n"
        }
        for f in fields {
            out += "\(indent)        fields[\(f.number)] = \"\(f.name)\"\n"
            if f.isMap {
                let vField = f.messageType!.fields[1]
                if isMessageField(vField) {
                    out += "\(indent)        if inserted { children[\(f.number)] = \(swiftTypeName(vField.messageType!)).buildOmniBufSchemaMeta(visited: &visited) }\n"
                }
            } else if isMessageField(f) {
                out += "\(indent)        if inserted { children[\(f.number)] = \(swiftTypeName(f.messageType!)).buildOmniBufSchemaMeta(visited: &visited) }\n"
            }
        }
        out += "\(indent)        return SchemaMeta(typeName: \"\(msg.name)\", fields: fields, children: children)\n"
        out += "\(indent)    }\n"
        out += "\(indent)}\n\n"

        // Lazy Opaque View & Wire Splicer
        emitOpaqueView(msg, into: &out, indent: indent)
    }

    // MARK: - Oneof Field Encoding & Decoding

    func emitEncodeOneofBranch(
        _ f: FieldDescriptor,
        in owner: Descriptor,
        oneofExpr: String,
        into out: inout String,
        indent: String,
        alwaysDeterministic: Bool = false
    ) {
        let num = f.number
        let caseName = camelCase(f.name)
        let detExpr = alwaysDeterministic ? "true" : "deterministic"
        out += "\(indent)if case .\(caseName)(let value) = \(oneofExpr) {\n"
        if isMessageField(f) {
            let isIndirect = isCyclicSingularField(f, in: owner)
            out += "\(indent)    let nextDepth = depth &+ 1\n"
            out += "\(indent)    guard nextDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(nextDepth) }\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireSubMsg)\n"
            out += "\(indent)    let lenPos = w.reserveLength2()\n"
            out += "\(indent)    try value\(isIndirect ? ".value" : "").encodeOmniBufBodyFast(into: &w, deterministic: \(detExpr), depth: nextDepth)\n"
            out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
        } else if f.type == .bool {
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: value ? WireType.wireBoolTrue : WireType.wireBoolFalse)\n"
        } else {
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: \(wireTypeExpr(f)))\n"
            emitAppendScalar(f, expr: "value", into: &out, indent: indent + "    ", alwaysDeterministic: alwaysDeterministic)
        }
        out += "\(indent)}\n"
    }

    func emitDecodeOneofBranch(
        _ f: FieldDescriptor,
        in owner: Descriptor,
        oneof: OneofDescriptor,
        into out: inout String,
        indent: String
    ) {
        let oneofProp = camelCase(oneof.name)
        let caseName = camelCase(f.name)
        out += "\(indent)case \(f.number):\n"
        if f.type == .bool {
            out += "\(indent)    if wt == WireType.wireBoolFalse {\n"
            out += "\(indent)        self.\(oneofProp) = .\(caseName)(false)\n"
            out += "\(indent)    } else if wt == WireType.wireBoolTrue {\n"
            out += "\(indent)        self.\(oneofProp) = .\(caseName)(true)\n"
            out += "\(indent)    } else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)    }\n"
            return
        }
        if isMessageField(f) {
            let subType = swiftTypeName(f.messageType!)
            let isIndirect = isCyclicSingularField(f, in: owner)
            out += "\(indent)    guard wt == WireType.wireSubMsg else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)        continue\n"
            out += "\(indent)    }\n"
            out += "\(indent)    let nextDepth = depth &+ 1\n"
            out += "\(indent)    guard nextDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(nextDepth) }\n"
            out += "\(indent)    let slice = try r.readLenSlice()\n"
            out += "\(indent)    var sub: \(subType)\n"
            out += "\(indent)    if case .\(caseName)(let existing) = self.\(oneofProp) {\n"
            out += "\(indent)        sub = existing\(isIndirect ? ".value" : "")\n"
            out += "\(indent)    } else {\n"
            out += "\(indent)        sub = \(subType)()\n"
            out += "\(indent)    }\n"
            out += "\(indent)    try sub.mergeOmniBuf(from: slice, depth: nextDepth, budget: &budget)\n"
            out += "\(indent)    self.\(oneofProp) = .\(caseName)(\(isIndirect ? "Indirect(sub)" : "sub"))\n"
            return
        }
        out += "\(indent)    guard wt == \(wireTypeExpr(f)) else {\n"
        out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
        out += "\(indent)        continue\n"
        out += "\(indent)    }\n"
        out += "\(indent)    self.\(oneofProp) = .\(caseName)(\(readScalarExpr(f, reader: "r")))\n"
    }

    // MARK: - Field Encoding & Decoding

    func emitEncodeField(
        _ f: FieldDescriptor,
        in owner: Descriptor,
        target: String,
        into out: inout String,
        indent: String,
        alwaysDeterministic: Bool = false
    ) {
        let num = f.number
        let detExpr = alwaysDeterministic ? "true" : "deterministic"
        if editionPresence(f) {
            out += "\(indent)if let value = \(target) {\n"
            if f.type == .bool {
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: value ? WireType.wireBoolTrue : WireType.wireBoolFalse)\n"
            } else {
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: \(wireTypeExpr(f)))\n"
                emitAppendScalar(f, expr: "value", into: &out, indent: indent + "    ", alwaysDeterministic: alwaysDeterministic)
            }
            out += "\(indent)}\n"
            return
        }
        if f.isMap {
            let entry = f.messageType!
            let kField = entry.fields[0]
            let vField = entry.fields[1]
            out += "\(indent)if !\(target).isEmpty {\n"
            out += "\(indent)    let mapDepth = depth &+ 1\n"
            out += "\(indent)    guard mapDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(mapDepth) }\n"
            if isMessageField(vField) {
                out += "\(indent)    let valDepth = mapDepth &+ 1\n"
                out += "\(indent)    guard valDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(valDepth) }\n"
            }
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireMap)\n"
            out += "\(indent)    let lenPos = w.reserveLength2()\n"
            out += "\(indent)    w.appendTwoBytes(\(wireTypeExpr(kField)), \(wireTypeExpr(vField)))\n"
            out += "\(indent)    w.appendVarint(UInt64(\(target).count))\n"
            let sortedKeysExpr: String
            if kField.type == .string {
                sortedKeysExpr = "\(target).keys.sorted(by: compareUTF8Bytes)"
            } else if kField.type == .bool {
                sortedKeysExpr = "\(target).keys.sorted(by: { !$0 && $1 })"
            } else {
                sortedKeysExpr = "\(target).keys.sorted()"
            }
            if alwaysDeterministic {
                out += "\(indent)    for k in \(sortedKeysExpr) {\n"
                if kField.type == .string {
                    out += "\(indent)        w.appendStringValue(k)\n"
                } else {
                    emitAppendScalar(kField, expr: "k", into: &out, indent: indent + "        ", alwaysDeterministic: true)
                }
                emitAppendScalar(vField, expr: "\(target)[k]!", into: &out, indent: indent + "        ", alwaysDeterministic: true)
                out += "\(indent)    }\n"
            } else {
                out += "\(indent)    if deterministic {\n"
                out += "\(indent)        for k in \(sortedKeysExpr) {\n"
                if kField.type == .string {
                    out += "\(indent)            w.appendStringValue(k)\n"
                } else {
                    emitAppendScalar(kField, expr: "k", into: &out, indent: indent + "            ")
                }
                emitAppendScalar(vField, expr: "\(target)[k]!", into: &out, indent: indent + "            ")
                out += "\(indent)        }\n"
                out += "\(indent)    } else {\n"
                out += "\(indent)        for (k, v) in \(target) {\n"
                if kField.type == .string {
                    out += "\(indent)            w.appendStringValue(k)\n"
                } else {
                    emitAppendScalar(kField, expr: "k", into: &out, indent: indent + "            ")
                }
                emitAppendScalar(vField, expr: "v", into: &out, indent: indent + "            ")
                out += "\(indent)        }\n"
                out += "\(indent)    }\n"
            }
            out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
            out += "\(indent)}\n"
            return
        }

        if f.isRepeated {
            out += "\(indent)if !\(target).isEmpty {\n"
            out += "\(indent)    let arrDepth = depth &+ 1\n"
            out += "\(indent)    guard arrDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(arrDepth) }\n"
            if isMessageField(f) {
                out += "\(indent)    let elemDepth = arrDepth &+ 1\n"
                out += "\(indent)    guard elemDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(elemDepth) }\n"
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireArray)\n"
                out += "\(indent)    let lenPos = w.reserveLength2()\n"
                out += "\(indent)    w.appendByte(\(wireTypeExpr(f)))\n"
                out += "\(indent)    w.appendVarint(UInt64(\(target).count))\n"
                out += "\(indent)    for elem in \(target) {\n"
                out += "\(indent)        let elemLenPos = w.reserveLength2()\n"
                out += "\(indent)        try elem.encodeOmniBufBodyFast(into: &w, deterministic: \(detExpr), depth: elemDepth)\n"
                out += "\(indent)        w.backpatchLength2(at: elemLenPos)\n"
                out += "\(indent)    }\n"
                out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
            } else {
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireArray)\n"
                out += "\(indent)    let lenPos = w.reserveLength2()\n"
                out += "\(indent)    w.appendByte(\(wireTypeExpr(f)))\n"
                out += "\(indent)    w.appendVarint(UInt64(\(target).count))\n"
                out += "\(indent)    for elem in \(target) {\n"
                emitAppendScalar(f, expr: "elem", into: &out, indent: indent + "        ", alwaysDeterministic: alwaysDeterministic)
                out += "\(indent)    }\n"
                out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
            }
            out += "\(indent)}\n"
            return
        }

        if isMessageField(f) {
            let isIndirect = isCyclicSingularField(f, in: owner)
            if isIndirect {
                out += "\(indent)if let box = \(target) {\n"
                out += "\(indent)    let nextDepth = depth &+ 1\n"
                out += "\(indent)    guard nextDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(nextDepth) }\n"
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireSubMsg)\n"
                out += "\(indent)    let lenPos = w.reserveLength2()\n"
                out += "\(indent)    try box.value.encodeOmniBufBodyFast(into: &w, deterministic: \(detExpr), depth: nextDepth)\n"
                out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
                out += "\(indent)}\n"
            } else {
                out += "\(indent)if let sub = \(target) {\n"
                out += "\(indent)    let nextDepth = depth &+ 1\n"
                out += "\(indent)    guard nextDepth <= WireType.maxNestingDepth else { throw OmniBufError.depthLimitExceeded(nextDepth) }\n"
                out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireSubMsg)\n"
                out += "\(indent)    let lenPos = w.reserveLength2()\n"
                out += "\(indent)    try sub.encodeOmniBufBodyFast(into: &w, deterministic: \(detExpr), depth: nextDepth)\n"
                out += "\(indent)    w.backpatchLength2(at: lenPos)\n"
                out += "\(indent)}\n"
            }
            return
        }

        switch f.type {
        case .enum:
            out += "\(indent)if \(target).rawValue != 0 {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireSint)\n"
            out += "\(indent)    w.appendZigZag32(\(target).rawValue)\n"
            out += "\(indent)}\n"
        case .bool:
            out += "\(indent)if \(target) {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireBoolTrue)\n"
            out += "\(indent)}\n"
        case .string:
            out += "\(indent)if !\(target).isEmpty {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireString)\n"
            out += "\(indent)    w.appendStringValue(\(target))\n"
            out += "\(indent)}\n"
        case .bytes:
            out += "\(indent)if !\(target).isEmpty {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireBytes)\n"
            out += "\(indent)    w.appendBytes(\(target))\n"
            out += "\(indent)}\n"
        case .float:
            out += "\(indent)if \(target).bitPattern != 0 {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireFloat32)\n"
            out += "\(indent)    w.appendFloat32(\(target))\n"
            out += "\(indent)}\n"
        case .double:
            out += "\(indent)if \(target).bitPattern != 0 {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: WireType.wireFloat64)\n"
            out += "\(indent)    w.appendFloat64(\(target))\n"
            out += "\(indent)}\n"
        default:
            out += "\(indent)if \(target) != 0 {\n"
            out += "\(indent)    w.appendTag(fieldNumber: \(num), wireType: \(wireTypeExpr(f)))\n"
            emitAppendScalar(f, expr: target, into: &out, indent: indent + "    ", alwaysDeterministic: alwaysDeterministic)
            out += "\(indent)}\n"
        }
    }

    func emitAppendScalar(
        _ f: FieldDescriptor,
        expr: String,
        into out: inout String,
        indent: String,
        alwaysDeterministic: Bool = false
    ) {
        if isMessageField(f) {
            let detExpr = alwaysDeterministic ? "true" : "deterministic"
            out += "\(indent)let subLenPos = w.reserveLength2()\n"
            out += "\(indent)try \(expr).encodeOmniBufBodyFast(into: &w, deterministic: \(detExpr), depth: valDepth)\n"
            out += "\(indent)w.backpatchLength2(at: subLenPos)\n"
            return
        }
        switch f.type {
        case .uint32: out += "\(indent)w.appendVarint(UInt64(\(expr)))\n"
        case .uint64: out += "\(indent)w.appendVarint(\(expr))\n"
        case .int32, .sint32: out += "\(indent)w.appendZigZag32(\(expr))\n"
        case .enum: out += "\(indent)w.appendZigZag32(\(expr).rawValue)\n"
        case .int64, .sint64: out += "\(indent)w.appendZigZag(\(expr))\n"
        case .bool: out += "\(indent)w.appendByte(\(expr) ? 1 : 0)\n"
        case .fixed32: out += "\(indent)w.appendFixed32(\(expr))\n"
        case .fixed64: out += "\(indent)w.appendFixed64(\(expr))\n"
        case .sfixed32: out += "\(indent)w.appendSfixed32(\(expr))\n"
        case .sfixed64: out += "\(indent)w.appendSfixed64(\(expr))\n"
        case .float: out += "\(indent)w.appendFloat32(\(expr))\n"
        case .double: out += "\(indent)w.appendFloat64(\(expr))\n"
        case .string: out += "\(indent)w.appendStringValue(\(expr))\n"
        case .bytes: out += "\(indent)w.appendBytes(\(expr))\n"
        default: break
        }
    }

    func emitDecodeField(_ f: FieldDescriptor, in owner: Descriptor, into out: inout String, indent: String) {
        let p = camelCase(f.name)
        out += "\(indent)case \(f.number):\n"
        if f.isMap {
            let entry = f.messageType!
            let kField = entry.fields[0]
            let vField = entry.fields[1]
            out += "\(indent)    guard wt == WireType.wireMap else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)        continue\n"
            out += "\(indent)    }\n"
            out += "\(indent)    let mapDepth = depth &+ 1\n"
            out += "\(indent)    guard mapDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(mapDepth) }\n"
            out += "\(indent)    let body = try r.readLenSlice(minLen: 3)\n"
            out += "\(indent)    let (keyWT, valWT, count, mr0) = try OmniBufReader.parseMapBody(body)\n"
            out += "\(indent)    guard keyWT == \(wireTypeExpr(kField)) && valWT == \(wireTypeExpr(vField)) else {\n"
            out += "\(indent)        throw OmniBufError.parse(\"field \(f.number) map type mismatch\")\n"
            out += "\(indent)    }\n"
            out += "\(indent)    try budget.addElements(count)\n"
            out += "\(indent)    try budget.addAlloc(count: count, elementBytes: 32)\n"
            out += "\(indent)    var mr = mr0\n"
            out += "\(indent)    for _ in 0..<count {\n"
            out += "\(indent)        let k = \(readScalarExpr(kField, reader: "mr"))\n"
            if isMessageField(vField) {
                out += "\(indent)        let valDepth = mapDepth &+ 1\n"
                out += "\(indent)        guard valDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(valDepth) }\n"
                out += "\(indent)        let slice = try mr.readLenSlice()\n"
                out += "\(indent)        var v = \(swiftTypeName(vField.messageType!))()\n"
                out += "\(indent)        try v.mergeOmniBuf(from: slice, depth: valDepth, budget: &budget)\n"
            } else {
                out += "\(indent)        let v = \(readScalarExpr(vField, reader: "mr"))\n"
            }
            out += "\(indent)        self.\(p)[k] = v\n"
            out += "\(indent)    }\n"
            out += "\(indent)    guard mr.isAtEnd else { throw OmniBufError.parse(\"WireMap trailing bytes\") }\n"
            return
        }

        if f.isRepeated {
            let elemType = swiftSingularBaseType(f)
            let elemBytesExpr = isMessageField(f)
                ? "max(MemoryLayout<\(elemType)>.stride, 16)"
                : "max(MemoryLayout<\(elemType)>.stride, 1)"
            out += "\(indent)    guard wt == WireType.wireArray else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)        continue\n"
            out += "\(indent)    }\n"
            out += "\(indent)    let arrDepth = depth &+ 1\n"
            out += "\(indent)    guard arrDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(arrDepth) }\n"
            out += "\(indent)    let body = try r.readLenSlice(minLen: 2)\n"
            out += "\(indent)    let (elemWT, count, er0) = try OmniBufReader.parseArrayBody(body)\n"
            out += "\(indent)    guard elemWT == \(wireTypeExpr(f)) else {\n"
            out += "\(indent)        throw OmniBufError.parse(\"field \(f.number) array element type mismatch\")\n"
            out += "\(indent)    }\n"
            out += "\(indent)    try budget.addElements(count)\n"
            out += "\(indent)    try budget.addAlloc(count: count, elementBytes: \(elemBytesExpr))\n"
            out += "\(indent)    let (newCap, capOverflow) = self.\(p).count.addingReportingOverflow(count)\n"
            out += "\(indent)    if capOverflow { throw OmniBufError.allocationLimitExceeded(\"array capacity overflow\") }\n"
            out += "\(indent)    var er = er0\n"
            out += "\(indent)    self.\(p).reserveCapacity(newCap)\n"
            out += "\(indent)    for _ in 0..<count {\n"
            if isMessageField(f) {
                out += "\(indent)        let elemDepth = arrDepth &+ 1\n"
                out += "\(indent)        guard elemDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(elemDepth) }\n"
                out += "\(indent)        let slice = try er.readLenSlice()\n"
                out += "\(indent)        var elem = \(swiftTypeName(f.messageType!))()\n"
                out += "\(indent)        try elem.mergeOmniBuf(from: slice, depth: elemDepth, budget: &budget)\n"
                out += "\(indent)        self.\(p).append(elem)\n"
            } else {
                out += "\(indent)        let elem = \(readScalarExpr(f, reader: "er"))\n"
                out += "\(indent)        self.\(p).append(elem)\n"
            }
            out += "\(indent)    }\n"
            out += "\(indent)    guard er.isAtEnd else { throw OmniBufError.parse(\"WireArray trailing bytes\") }\n"
            return
        }

        if f.type == .bool {
            out += "\(indent)    if wt == WireType.wireBoolFalse {\n"
            out += "\(indent)        self.\(p) = false\n"
            out += "\(indent)    } else if wt == WireType.wireBoolTrue {\n"
            out += "\(indent)        self.\(p) = true\n"
            out += "\(indent)    } else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)    }\n"
            return
        }

        if isMessageField(f) {
            let subType = swiftTypeName(f.messageType!)
            let isIndirect = isCyclicSingularField(f, in: owner)
            out += "\(indent)    guard wt == WireType.wireSubMsg else {\n"
            out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
            out += "\(indent)        continue\n"
            out += "\(indent)    }\n"
            out += "\(indent)    let nextDepth = depth &+ 1\n"
            out += "\(indent)    guard nextDepth <= budget.maxDepth else { throw OmniBufError.depthLimitExceeded(nextDepth) }\n"
            out += "\(indent)    let slice = try r.readLenSlice()\n"
            if isIndirect {
                out += "\(indent)    var sub = self.\(p)?.value ?? \(subType)()\n"
                out += "\(indent)    try sub.mergeOmniBuf(from: slice, depth: nextDepth, budget: &budget)\n"
                out += "\(indent)    self.\(p) = Indirect(sub)\n"
            } else {
                out += "\(indent)    var sub = self.\(p) ?? \(subType)()\n"
                out += "\(indent)    try sub.mergeOmniBuf(from: slice, depth: nextDepth, budget: &budget)\n"
                out += "\(indent)    self.\(p) = sub\n"
            }
            return
        }

        out += "\(indent)    guard wt == \(wireTypeExpr(f)) else {\n"
        out += "\(indent)        try r.validateValue(wireType: wt, inCollection: false, depth: depth, maxDepth: budget.maxDepth)\n"
        out += "\(indent)        continue\n"
        out += "\(indent)    }\n"
        out += "\(indent)    self.\(p) = \(readScalarExpr(f, reader: "r"))\n"
    }
}
