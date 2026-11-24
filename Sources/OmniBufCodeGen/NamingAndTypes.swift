import SwiftProtobufPluginLibrary

extension OmniBufCodeGenerator {
    // MARK: - Naming & Cycle Helpers

    func swiftTypeName(_ descriptor: Descriptor) -> String {
        var parts: [String] = [descriptor.name]
        var cur = descriptor.containingType
        while let parent = cur {
            parts.append(parent.name)
            cur = parent.containingType
        }
        return parts.reversed().joined(separator: "_")
    }

    func swiftEnumName(_ descriptor: EnumDescriptor) -> String {
        var parts: [String] = [descriptor.name]
        var cur = descriptor.containingType
        while let parent = cur {
            parts.append(parent.name)
            cur = parent.containingType
        }
        return parts.reversed().joined(separator: "_")
    }

    func isCyclicSingularField(_ field: FieldDescriptor, in owner: Descriptor) -> Bool {
        guard !field.isRepeated && !field.isMap && field.type == .message,
              let target = field.messageType else {
            return false
        }
        var visited: Set<String> = []
        var stack: [Descriptor] = [target]
        while let cur = stack.popLast() {
            if cur.fullName == owner.fullName {
                return true
            }
            guard visited.insert(cur.fullName).inserted else { continue }
            for f in cur.fields where !f.isRepeated && !f.isMap && f.type == .message {
                if let next = f.messageType {
                    stack.append(next)
                }
            }
        }
        return false
    }

    func camelCaseRaw(_ snake: String) -> String {
        let leadingUnderscores = snake.prefix(while: { $0 == "_" })
        let parts = snake.split(separator: "_")
        guard let first = parts.first else {
            return snake.isEmpty ? "_" : snake
        }
        var res = String(leadingUnderscores) + first.lowercased()
        for p in parts.dropFirst() {
            res += p.prefix(1).uppercased() + p.dropFirst().lowercased()
        }
        if let firstChar = res.first, firstChar.isNumber {
            res = "_" + res
        }
        return res
    }

    func camelCase(_ snake: String) -> String {
        escapeKeyword(camelCaseRaw(snake))
    }

    func pascalCase(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        guard !parts.isEmpty else { return snake }
        return parts.map { part in
            part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }.joined()
    }

    func escapeKeyword(_ name: String) -> String {
        let keywords: Set<String> = [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
            "import", "init", "inout", "internal", "let", "open", "operator", "private",
            "protocol", "Protocol", "public", "static", "struct", "subscript", "typealias", "var",
            "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
            "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
            "as", "Any", "any", "some", "none", "async", "await", "Type", "catch", "false",
            "is", "nil", "rethrows", "super", "self", "Self", "throw", "throws", "true", "try",
            "precedencegroup", "borrowing", "consuming", "nonisolated", "isolated", "actor",
            "macro", "package", "description",
        ]
        return keywords.contains(name) ? "`\(name)`" : name
    }

    // MARK: - Field Type Mapping

    func swiftFieldType(_ field: FieldDescriptor, in owner: Descriptor) -> String {
        if field.isMap {
            let entry = field.messageType!
            let kType = swiftScalarType(entry.fields[0])
            let vField = entry.fields[1]
            let vType = swiftSingularBaseType(vField)
            return "[\(kType): \(vType)]"
        }
        if field.isRepeated {
            return "[\(swiftSingularBaseType(field))]"
        }
        if field.type == .message {
            let base = swiftTypeName(field.messageType!)
            return isCyclicSingularField(field, in: owner) ? "Indirect<\(base)>?" : "\(base)?"
        }
        return swiftSingularBaseType(field)
    }

    func swiftSingularBaseType(_ field: FieldDescriptor) -> String {
        if field.type == .message {
            return swiftTypeName(field.messageType!)
        }
        if field.type == .enum {
            return swiftEnumName(field.enumType!)
        }
        return swiftScalarType(field)
    }

    func swiftScalarType(_ field: FieldDescriptor) -> String {
        switch field.type {
        case .uint32, .fixed32: return "UInt32"
        case .uint64, .fixed64: return "UInt64"
        case .int32, .sint32, .sfixed32: return "Int32"
        case .int64, .sint64, .sfixed64: return "Int64"
        case .bool: return "Bool"
        case .float: return "Float"
        case .double: return "Double"
        case .string: return "String"
        case .bytes: return "[UInt8]"
        default: return "Int32"
        }
    }

    func defaultValue(_ field: FieldDescriptor) -> String {
        if field.isMap { return "[:]" }
        if field.isRepeated { return "[]" }
        switch field.type {
        case .message: return "nil"
        case .enum: return "\(swiftEnumName(field.enumType!))()"
        case .bool: return "false"
        case .string: return "\"\""
        case .bytes: return "[]"
        case .float, .double: return "0"
        default: return "0"
        }
    }

    func wireTypeExpr(_ field: FieldDescriptor) -> String {
        switch field.type {
        case .uint32, .uint64: return "WireType.wireUint"
        case .int32, .int64, .sint32, .sint64, .enum: return "WireType.wireSint"
        case .bool: return "WireType.wireBoolFalse"
        case .fixed32: return "WireType.wireFixed32"
        case .fixed64: return "WireType.wireFixed64"
        case .sfixed32: return "WireType.wireSfixed32"
        case .sfixed64: return "WireType.wireSfixed64"
        case .float: return "WireType.wireFloat32"
        case .double: return "WireType.wireFloat64"
        case .string: return "WireType.wireString"
        case .bytes: return "WireType.wireBytes"
        case .message: return "WireType.wireSubMsg"
        default: return "WireType.wireUint"
        }
    }

    func readScalarExpr(_ f: FieldDescriptor, reader: String) -> String {
        switch f.type {
        case .uint32: return "UInt32(truncatingIfNeeded: try \(reader).readVarint())"
        case .uint64: return "try \(reader).readVarint()"
        case .int32, .sint32: return "try \(reader).readSint32()"
        case .enum:
            let enumType = swiftEnumName(f.enumType!)
            return "\(enumType)(rawValue: try \(reader).readSint32()) ?? \(enumType)()"
        case .int64, .sint64: return "try \(reader).readSint64()"
        case .bool: return "try \(reader).readBoolByte()"
        case .fixed32: return "try \(reader).readFixed32()"
        case .fixed64: return "try \(reader).readFixed64()"
        case .sfixed32: return "try \(reader).readSfixed32()"
        case .sfixed64: return "try \(reader).readSfixed64()"
        case .float: return "try \(reader).readFloat32()"
        case .double: return "try \(reader).readFloat64()"
        case .string: return "try \(reader).readString(budget: &budget)"
        case .bytes: return "try \(reader).readBytes(budget: &budget)"
        default: return "try \(reader).readSint32()"
        }
    }
}
