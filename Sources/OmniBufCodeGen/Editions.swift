import SwiftProtobuf
import SwiftProtobufPluginLibrary

public struct OmniBufEditionError: Error, CustomStringConvertible, Equatable, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

private func isOptionExtendee(_ fullName: String) -> Bool {
    switch fullName {
    case "google.protobuf.FileOptions",
         "google.protobuf.MessageOptions",
         "google.protobuf.FieldOptions",
         "google.protobuf.OneofOptions",
         "google.protobuf.EnumOptions",
         "google.protobuf.EnumValueOptions",
         "google.protobuf.ExtensionRangeOptions",
         "google.protobuf.ServiceOptions",
         "google.protobuf.MethodOptions",
         "google.protobuf.FeatureSet":
        return true
    default:
        return false
    }
}

private func isZeroDefaultValue(_ rawDefault: String, for field: FieldDescriptor) -> Bool {
    switch field.type {
    case .string, .bytes:
        return rawDefault.isEmpty
    case .bool:
        return rawDefault == "false"
    case .enum:
        if let val = field.enumType?.value(named: rawDefault) {
            return val.number == 0
        }
        return Int32(rawDefault) == 0
    case .int32, .sint32, .sfixed32, .int64, .sint64, .sfixed64:
        return Int64(rawDefault) == 0
    case .uint32, .fixed32, .uint64, .fixed64:
        return UInt64(rawDefault) == 0
    case .float, .double:
        guard let d = Double(rawDefault), !d.isNaN else { return false }
        return d.bitPattern == 0
    default:
        return false
    }
}

extension OmniBufCodeGenerator {
    /// Validates that a `Google_Protobuf_Edition` value is supported (proto2, proto3, or Editions 2023/2024/2026).
    public func validateEdition(_ edition: Google_Protobuf_Edition, fileName: String = "") throws {
        if edition == .proto2 || edition == .proto3 || Self.supportedEditionRange.contains(edition) {
            return
        }
        let suffix = fileName.isEmpty ? "" : " in \(fileName)"
        throw OmniBufEditionError(
            "omnibuf: unsupported protobuf edition \(edition)\(suffix) (supported: 2023, 2024, 2026)"
        )
    }

    /// Validates edition metadata on a raw `Google_Protobuf_FileDescriptorProto` before building a `DescriptorSet`.
    public func validateEditions(_ proto: Google_Protobuf_FileDescriptorProto) throws {
        if proto.hasEdition {
            try validateEdition(proto.edition, fileName: proto.name)
            return
        }
        if proto.syntax == "editions" {
            throw OmniBufEditionError(
                "omnibuf: unsupported protobuf edition (missing edition in \(proto.name))"
            )
        }
        if !proto.syntax.isEmpty && proto.syntax != "proto2" && proto.syntax != "proto3" {
            throw OmniBufEditionError(
                "omnibuf: unsupported protobuf edition '\(proto.syntax)' in \(proto.name)"
            )
        }
    }

    /// Validates that a `FileDescriptor` uses only Protobuf Editions features supported by OmniBuf.
    public func validateEditions(_ file: FileDescriptor) throws {
        try validateEdition(file.edition, fileName: file.name)

        if file.edition == .proto2 || file.edition == .proto3 {
            func checkLegacyGroups(_ msg: Descriptor) throws {
                for f in msg.fields where f.type == .group {
                    throw OmniBufEditionError(
                        "omnibuf: legacy proto2 group fields are not supported (\(f.fullName))"
                    )
                }
                for nested in msg.messages {
                    try checkLegacyGroups(nested)
                }
            }
            for msg in file.messages {
                try checkLegacyGroups(msg)
            }
            return
        }

        for ext in file.extensions where !isOptionExtendee(ext.containingType.fullName) {
            throw OmniBufEditionError(
                "omnibuf: editions non-option extensions are not supported (\(ext.fullName))"
            )
        }

        func checkEnum(_ e: EnumDescriptor) throws {
            if e.isClosed {
                throw OmniBufEditionError(
                    "omnibuf: editions CLOSED enums are not supported (\(e.fullName))"
                )
            }
        }

        func visit(_ msg: Descriptor) throws {
            for ext in msg.extensions where !isOptionExtendee(ext.containingType.fullName) {
                throw OmniBufEditionError(
                    "omnibuf: editions non-option extensions are not supported (\(ext.fullName))"
                )
            }
            if !msg.messageExtensionRanges.isEmpty {
                throw OmniBufEditionError(
                    "omnibuf: editions extension ranges are not supported (\(msg.fullName))"
                )
            }
            for e in msg.enums {
                try checkEnum(e)
            }
            for f in msg.fields {
                if f.isRequired || f.features.fieldPresence == .legacyRequired {
                    throw OmniBufEditionError(
                        "omnibuf: editions LEGACY_REQUIRED fields are not supported (\(f.fullName))"
                    )
                }
                if f.type == .enum, let enumType = f.enumType, enumType.isClosed {
                    throw OmniBufEditionError(
                        "omnibuf: editions CLOSED enum field \(f.fullName) references closed enum \(enumType.fullName)"
                    )
                }
                if f.type == .string && f.features.utf8Validation != .verify {
                    throw OmniBufEditionError(
                        "omnibuf: editions utf8_validation = NONE is not supported (\(f.fullName))"
                    )
                }
                if f.isMap, let (kField, vField) = f.messageType?.mapKeyAndValue {
                    if kField.type == .string && (kField.features.utf8Validation != .verify || f.features.utf8Validation != .verify) {
                        throw OmniBufEditionError(
                            "omnibuf: editions utf8_validation = NONE is not supported on map key (\(f.fullName))"
                        )
                    }
                    if vField.type == .string && (vField.features.utf8Validation != .verify || f.features.utf8Validation != .verify) {
                        throw OmniBufEditionError(
                            "omnibuf: editions utf8_validation = NONE is not supported on map value (\(f.fullName))"
                        )
                    }
                    if vField.type == .enum, let enumType = vField.enumType, enumType.isClosed {
                        throw OmniBufEditionError(
                            "omnibuf: editions CLOSED enum map value \(f.fullName) references closed enum \(enumType.fullName)"
                        )
                    }
                }
                if let rawDefault = f.defaultValue, !isZeroDefaultValue(rawDefault, for: f) {
                    throw OmniBufEditionError(
                        "omnibuf: editions custom non-zero default value '\(rawDefault)' is not supported (\(f.fullName))"
                    )
                }
            }
            for nested in msg.messages {
                try visit(nested)
            }
        }

        for e in file.enums {
            try checkEnum(e)
        }
        for msg in file.messages {
            try visit(msg)
        }
    }
}
