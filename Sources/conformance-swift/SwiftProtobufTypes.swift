import Foundation
import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf

// Standard SwiftProtobuf.Message definitions matching `proto/omnibuf/bench/peer.proto`
// and `proto/omnibuf/conformance/conformance.proto` for Tier 2 (`TIER_PROTOBUF_TYPES`).

struct PBLocation: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static let protoMessageName: String = "omnibuf.bench.Location"
    var region: String = ""
    var datacenter: String = ""
    var city: String = ""
    var rack: UInt32 = 0
    var latitude: Float = 0
    var longitude: Float = 0
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &self.region)
            case 2: try decoder.decodeSingularStringField(value: &self.datacenter)
            case 3: try decoder.decodeSingularStringField(value: &self.city)
            case 4: try decoder.decodeSingularUInt32Field(value: &self.rack)
            case 5: try decoder.decodeSingularFloatField(value: &self.latitude)
            case 6: try decoder.decodeSingularFloatField(value: &self.longitude)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !self.region.isEmpty { try visitor.visitSingularStringField(value: self.region, fieldNumber: 1) }
        if !self.datacenter.isEmpty { try visitor.visitSingularStringField(value: self.datacenter, fieldNumber: 2) }
        if !self.city.isEmpty { try visitor.visitSingularStringField(value: self.city, fieldNumber: 3) }
        if self.rack != 0 { try visitor.visitSingularUInt32Field(value: self.rack, fieldNumber: 4) }
        if self.latitude.bitPattern != 0 { try visitor.visitSingularFloatField(value: self.latitude, fieldNumber: 5) }
        if self.longitude.bitPattern != 0 { try visitor.visitSingularFloatField(value: self.longitude, fieldNumber: 6) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBLocation, rhs: PBLocation) -> Bool {
        lhs.region == rhs.region && lhs.datacenter == rhs.datacenter && lhs.city == rhs.city
            && lhs.rack == rhs.rack && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
            && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: "Location",
            fields: [1: "region", 2: "datacenter", 3: "city", 4: "rack", 5: "latitude", 6: "longitude"]
        )
    }
}

struct PBNeighbor: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static let protoMessageName: String = "omnibuf.bench.Neighbor"
    var peerAsn: UInt32 = 0
    var router: String = ""
    var latencyUs: UInt32 = 0
    var established: Bool = false
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularUInt32Field(value: &self.peerAsn)
            case 2: try decoder.decodeSingularStringField(value: &self.router)
            case 3: try decoder.decodeSingularUInt32Field(value: &self.latencyUs)
            case 4: try decoder.decodeSingularBoolField(value: &self.established)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if self.peerAsn != 0 { try visitor.visitSingularUInt32Field(value: self.peerAsn, fieldNumber: 1) }
        if !self.router.isEmpty { try visitor.visitSingularStringField(value: self.router, fieldNumber: 2) }
        if self.latencyUs != 0 { try visitor.visitSingularUInt32Field(value: self.latencyUs, fieldNumber: 3) }
        if self.established != false { try visitor.visitSingularBoolField(value: self.established, fieldNumber: 4) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBNeighbor, rhs: PBNeighbor) -> Bool {
        lhs.peerAsn == rhs.peerAsn && lhs.router == rhs.router
            && lhs.latencyUs == rhs.latencyUs && lhs.established == rhs.established
            && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: "Neighbor",
            fields: [1: "peer_asn", 2: "router", 3: "latency_us", 4: "established"]
        )
    }
}

struct PBPeerUpdate: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static let protoMessageName: String = "omnibuf.bench.PeerUpdate"
    var asn: UInt32 = 0
    var routerID: String = ""
    var active: Bool = false
    var uptimeSec: UInt64 = 0
    var rssiDbm: Int32 = 0
    var cpuLoad: Double = 0
    var tags: [String] = []
    var prefixes: [UInt32] = []
    private var _location: PBLocation? = nil
    var location: PBLocation {
        get { _location ?? PBLocation() }
        set { _location = newValue }
    }
    var hasLocation: Bool { _location != nil }
    mutating func clearLocation() { _location = nil }
    var neighbors: [PBNeighbor] = []
    var sequence: UInt64 = 0
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularUInt32Field(value: &self.asn)
            case 2: try decoder.decodeSingularStringField(value: &self.routerID)
            case 3: try decoder.decodeSingularBoolField(value: &self.active)
            case 4: try decoder.decodeSingularUInt64Field(value: &self.uptimeSec)
            case 5: try decoder.decodeSingularSInt32Field(value: &self.rssiDbm)
            case 6: try decoder.decodeSingularDoubleField(value: &self.cpuLoad)
            case 7: try decoder.decodeRepeatedStringField(value: &self.tags)
            case 8: try decoder.decodeRepeatedUInt32Field(value: &self.prefixes)
            case 9: try decoder.decodeSingularMessageField(value: &self._location)
            case 10: try decoder.decodeRepeatedMessageField(value: &self.neighbors)
            case 11: try decoder.decodeSingularUInt64Field(value: &self.sequence)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if self.asn != 0 { try visitor.visitSingularUInt32Field(value: self.asn, fieldNumber: 1) }
        if !self.routerID.isEmpty { try visitor.visitSingularStringField(value: self.routerID, fieldNumber: 2) }
        if self.active != false { try visitor.visitSingularBoolField(value: self.active, fieldNumber: 3) }
        if self.uptimeSec != 0 { try visitor.visitSingularUInt64Field(value: self.uptimeSec, fieldNumber: 4) }
        if self.rssiDbm != 0 { try visitor.visitSingularSInt32Field(value: self.rssiDbm, fieldNumber: 5) }
        if self.cpuLoad.bitPattern != 0 { try visitor.visitSingularDoubleField(value: self.cpuLoad, fieldNumber: 6) }
        if !self.tags.isEmpty { try visitor.visitRepeatedStringField(value: self.tags, fieldNumber: 7) }
        if !self.prefixes.isEmpty { try visitor.visitPackedUInt32Field(value: self.prefixes, fieldNumber: 8) }
        if let loc = self._location { try visitor.visitSingularMessageField(value: loc, fieldNumber: 9) }
        if !self.neighbors.isEmpty { try visitor.visitRepeatedMessageField(value: self.neighbors, fieldNumber: 10) }
        if self.sequence != 0 { try visitor.visitSingularUInt64Field(value: self.sequence, fieldNumber: 11) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBPeerUpdate, rhs: PBPeerUpdate) -> Bool {
        lhs.asn == rhs.asn && lhs.routerID == rhs.routerID && lhs.active == rhs.active
            && lhs.uptimeSec == rhs.uptimeSec && lhs.rssiDbm == rhs.rssiDbm && lhs.cpuLoad == rhs.cpuLoad
            && lhs.tags == rhs.tags && lhs.prefixes == rhs.prefixes && lhs._location == rhs._location
            && lhs.neighbors == rhs.neighbors && lhs.sequence == rhs.sequence
            && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: "PeerUpdate",
            fields: [
                1: "asn", 2: "router_id", 3: "active", 4: "uptime_sec", 5: "rssi_dbm",
                6: "cpu_load", 7: "tags", 8: "prefixes", 9: "location", 10: "neighbors", 11: "sequence",
            ],
            children: [9: PBLocation.omniBufSchemaMeta, 10: PBNeighbor.omniBufSchemaMeta]
        )
    }
}

struct PBAllTypesSubMsg: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static let protoMessageName: String = "omnibuf.conformance.AllTypesSubMsg"
    var id: UInt32 = 0
    var label: String = ""
    var flag: Bool = false
    var score: Int64 = 0
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularUInt32Field(value: &self.id)
            case 2: try decoder.decodeSingularStringField(value: &self.label)
            case 3: try decoder.decodeSingularBoolField(value: &self.flag)
            case 4: try decoder.decodeSingularSInt64Field(value: &self.score)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if self.id != 0 { try visitor.visitSingularUInt32Field(value: self.id, fieldNumber: 1) }
        if !self.label.isEmpty { try visitor.visitSingularStringField(value: self.label, fieldNumber: 2) }
        if self.flag != false { try visitor.visitSingularBoolField(value: self.flag, fieldNumber: 3) }
        if self.score != 0 { try visitor.visitSingularSInt64Field(value: self.score, fieldNumber: 4) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBAllTypesSubMsg, rhs: PBAllTypesSubMsg) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.flag == rhs.flag
            && lhs.score == rhs.score && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: "AllTypesSubMsg",
            fields: [1: "id", 2: "label", 3: "flag", 4: "score"]
        )
    }
}

struct PBTestAllTypes: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static let protoMessageName: String = "omnibuf.conformance.TestAllTypes"
    var f1Uint32: UInt32 = 0
    var f2Uint64: UInt64 = 0
    var f3Sint32: Int32 = 0
    var f4Sint64: Int64 = 0
    var f5Bool: Bool = false
    var f6String: String = ""
    var f7Bytes: Data = Data()
    private var _f8SubMsg: PBAllTypesSubMsg? = nil
    var f8SubMsg: PBAllTypesSubMsg {
        get { _f8SubMsg ?? PBAllTypesSubMsg() }
        set { _f8SubMsg = newValue }
    }
    var hasF8SubMsg: Bool { _f8SubMsg != nil }
    var f9StringArr: [String] = []
    var f10Uint32Arr: [UInt32] = []
    var f11SubMsgArr: [PBAllTypesSubMsg] = []
    var f12MapStrUint: [String: UInt64] = [:]
    var f13Float32: Float = 0
    var f14Float64: Double = 0
    var f15Fixed32: UInt32 = 0
    var f16Fixed64: UInt64 = 0
    var f20OverflowStr: String = ""
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularUInt32Field(value: &self.f1Uint32)
            case 2: try decoder.decodeSingularUInt64Field(value: &self.f2Uint64)
            case 3: try decoder.decodeSingularSInt32Field(value: &self.f3Sint32)
            case 4: try decoder.decodeSingularSInt64Field(value: &self.f4Sint64)
            case 5: try decoder.decodeSingularBoolField(value: &self.f5Bool)
            case 6: try decoder.decodeSingularStringField(value: &self.f6String)
            case 7: try decoder.decodeSingularBytesField(value: &self.f7Bytes)
            case 8: try decoder.decodeSingularMessageField(value: &self._f8SubMsg)
            case 9: try decoder.decodeRepeatedStringField(value: &self.f9StringArr)
            case 10: try decoder.decodeRepeatedUInt32Field(value: &self.f10Uint32Arr)
            case 11: try decoder.decodeRepeatedMessageField(value: &self.f11SubMsgArr)
            case 12: try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufUInt64>.self, value: &self.f12MapStrUint)
            case 13: try decoder.decodeSingularFloatField(value: &self.f13Float32)
            case 14: try decoder.decodeSingularDoubleField(value: &self.f14Float64)
            case 15: try decoder.decodeSingularFixed32Field(value: &self.f15Fixed32)
            case 16: try decoder.decodeSingularFixed64Field(value: &self.f16Fixed64)
            case 20: try decoder.decodeSingularStringField(value: &self.f20OverflowStr)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if self.f1Uint32 != 0 { try visitor.visitSingularUInt32Field(value: self.f1Uint32, fieldNumber: 1) }
        if self.f2Uint64 != 0 { try visitor.visitSingularUInt64Field(value: self.f2Uint64, fieldNumber: 2) }
        if self.f3Sint32 != 0 { try visitor.visitSingularSInt32Field(value: self.f3Sint32, fieldNumber: 3) }
        if self.f4Sint64 != 0 { try visitor.visitSingularSInt64Field(value: self.f4Sint64, fieldNumber: 4) }
        if self.f5Bool != false { try visitor.visitSingularBoolField(value: self.f5Bool, fieldNumber: 5) }
        if !self.f6String.isEmpty { try visitor.visitSingularStringField(value: self.f6String, fieldNumber: 6) }
        if !self.f7Bytes.isEmpty { try visitor.visitSingularBytesField(value: self.f7Bytes, fieldNumber: 7) }
        if let v = self._f8SubMsg { try visitor.visitSingularMessageField(value: v, fieldNumber: 8) }
        if !self.f9StringArr.isEmpty { try visitor.visitRepeatedStringField(value: self.f9StringArr, fieldNumber: 9) }
        if !self.f10Uint32Arr.isEmpty { try visitor.visitPackedUInt32Field(value: self.f10Uint32Arr, fieldNumber: 10) }
        if !self.f11SubMsgArr.isEmpty { try visitor.visitRepeatedMessageField(value: self.f11SubMsgArr, fieldNumber: 11) }
        if !self.f12MapStrUint.isEmpty {
            try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufUInt64>.self, value: self.f12MapStrUint, fieldNumber: 12)
        }
        if self.f13Float32.bitPattern != 0 { try visitor.visitSingularFloatField(value: self.f13Float32, fieldNumber: 13) }
        if self.f14Float64.bitPattern != 0 { try visitor.visitSingularDoubleField(value: self.f14Float64, fieldNumber: 14) }
        if self.f15Fixed32 != 0 { try visitor.visitSingularFixed32Field(value: self.f15Fixed32, fieldNumber: 15) }
        if self.f16Fixed64 != 0 { try visitor.visitSingularFixed64Field(value: self.f16Fixed64, fieldNumber: 16) }
        if !self.f20OverflowStr.isEmpty { try visitor.visitSingularStringField(value: self.f20OverflowStr, fieldNumber: 20) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBTestAllTypes, rhs: PBTestAllTypes) -> Bool {
        lhs.f1Uint32 == rhs.f1Uint32 && lhs.f2Uint64 == rhs.f2Uint64
            && lhs.f3Sint32 == rhs.f3Sint32 && lhs.f4Sint64 == rhs.f4Sint64
            && lhs.f5Bool == rhs.f5Bool && lhs.f6String == rhs.f6String
            && lhs.f7Bytes == rhs.f7Bytes && lhs._f8SubMsg == rhs._f8SubMsg
            && lhs.f9StringArr == rhs.f9StringArr && lhs.f10Uint32Arr == rhs.f10Uint32Arr
            && lhs.f11SubMsgArr == rhs.f11SubMsgArr && lhs.f12MapStrUint == rhs.f12MapStrUint
            && lhs.f13Float32 == rhs.f13Float32 && lhs.f14Float64 == rhs.f14Float64
            && lhs.f15Fixed32 == rhs.f15Fixed32 && lhs.f16Fixed64 == rhs.f16Fixed64
            && lhs.f20OverflowStr == rhs.f20OverflowStr && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: "TestAllTypes",
            fields: [
                1: "f1_uint32", 2: "f2_uint64", 3: "f3_sint32", 4: "f4_sint64", 5: "f5_bool",
                6: "f6_string", 7: "f7_bytes", 8: "f8_sub_msg", 9: "f9_string_arr", 10: "f10_uint32_arr",
                11: "f11_sub_msg_arr", 12: "f12_map_str_uint", 13: "f13_float32", 14: "f14_float64",
                15: "f15_fixed32", 16: "f16_fixed64", 20: "f20_overflow_str",
            ],
            children: [8: PBAllTypesSubMsg.omniBufSchemaMeta, 11: PBAllTypesSubMsg.omniBufSchemaMeta]
        )
    }
}

// MARK: - Protobuf Editions 2023 / 2024 / 2026 Tier 2 Reference Models

protocol PBEditionsTag: Sendable {
    static var childProtoMessageName: String { get }
    static var childTypeName: String { get }
    static var payloadProtoMessageName: String { get }
    static var payloadTypeName: String { get }
}

enum PBEditions2023Tag: PBEditionsTag {
    static let childProtoMessageName = "omnibuf.conformance.Editions2023Child"
    static let childTypeName = "Editions2023Child"
    static let payloadProtoMessageName = "omnibuf.conformance.TestEditions2023"
    static let payloadTypeName = "TestEditions2023"
}

enum PBEditions2024Tag: PBEditionsTag {
    static let childProtoMessageName = "omnibuf.conformance.Editions2024Child"
    static let childTypeName = "Editions2024Child"
    static let payloadProtoMessageName = "omnibuf.conformance.TestEditions2024"
    static let payloadTypeName = "TestEditions2024"
}

enum PBEditions2026Tag: PBEditionsTag {
    static let childProtoMessageName = "omnibuf.conformance.Editions2026Child"
    static let childTypeName = "Editions2026Child"
    static let payloadProtoMessageName = "omnibuf.conformance.TestEditions2026"
    static let payloadTypeName = "TestEditions2026"
}

enum PBEditionsStatus: SwiftProtobuf.Enum, Equatable, Hashable, Sendable {
    typealias RawValue = Int
    case unspecified
    case active
    case paused
    case UNRECOGNIZED(Int)

    init() { self = .unspecified }

    init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .active
        case 2: self = .paused
        default: self = .UNRECOGNIZED(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .unspecified: return 0
        case .active: return 1
        case .paused: return 2
        case .UNRECOGNIZED(let v): return v
        }
    }
}

struct PBEditionsChild<Tag: PBEditionsTag>: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static var protoMessageName: String { Tag.childProtoMessageName }

    var _id: Int32? = nil
    var _note: String? = nil
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    init(id: Int32? = nil, note: String? = nil) {
        self._id = id
        self._note = note
    }

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt32Field(value: &self._id)
            case 2: try decoder.decodeSingularStringField(value: &self._note)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if let v = self._id { try visitor.visitSingularInt32Field(value: v, fieldNumber: 1) }
        if let v = self._note { try visitor.visitSingularStringField(value: v, fieldNumber: 2) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._id == rhs._id && lhs._note == rhs._note && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        SchemaMeta(
            typeName: Tag.childTypeName,
            fields: [1: "id", 2: "note"]
        )
    }
}

struct PBTestEditions<Tag: PBEditionsTag>: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable, OmniBufSchemaMetaProviding {
    static var protoMessageName: String { Tag.payloadProtoMessageName }

    enum OneOf_Choice: Equatable, Sendable {
        case choiceInt(Int32)
        case choiceText(String)
        case choiceFlag(Bool)
        case choiceChild(PBEditionsChild<Tag>)
    }

    var _explicitInt: Int32? = nil
    var _explicitBool: Bool? = nil
    var _explicitString: String? = nil
    var _explicitBytes: Data? = nil
    var _explicitDouble: Double? = nil
    var _status: PBEditionsStatus? = nil
    var implicitCount: Int32 = 0
    var implicitFlag: Bool = false
    var _child: PBEditionsChild<Tag>? = nil
    var _delimitedChild: PBEditionsChild<Tag>? = nil
    var packedVals: [Int32] = []
    var expandedVals: [Int32] = []
    var scores: [String: Int32] = [:]
    var choice: OneOf_Choice? = nil
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt32Field(value: &self._explicitInt)
            case 2: try decoder.decodeSingularBoolField(value: &self._explicitBool)
            case 3: try decoder.decodeSingularStringField(value: &self._explicitString)
            case 4: try decoder.decodeSingularBytesField(value: &self._explicitBytes)
            case 5: try decoder.decodeSingularDoubleField(value: &self._explicitDouble)
            case 6: try decoder.decodeSingularEnumField(value: &self._status)
            case 7: try decoder.decodeSingularInt32Field(value: &self.implicitCount)
            case 8: try decoder.decodeSingularBoolField(value: &self.implicitFlag)
            case 9: try decoder.decodeSingularMessageField(value: &self._child)
            case 10: try decoder.decodeSingularGroupField(value: &self._delimitedChild)
            case 11: try decoder.decodeRepeatedInt32Field(value: &self.packedVals)
            case 12: try decoder.decodeRepeatedInt32Field(value: &self.expandedVals)
            case 13:
                try decoder.decodeMapField(
                    fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufInt32>.self,
                    value: &self.scores
                )
            case 14:
                var v: Int32?
                try decoder.decodeSingularInt32Field(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .choiceInt(v)
                }
            case 15:
                var v: String?
                try decoder.decodeSingularStringField(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .choiceText(v)
                }
            case 16:
                var v: Bool?
                try decoder.decodeSingularBoolField(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .choiceFlag(v)
                }
            case 17:
                var v: PBEditionsChild<Tag>?
                var hadOneofValue = false
                if let current = self.choice {
                    hadOneofValue = true
                    if case .choiceChild(let m) = current { v = m }
                }
                try decoder.decodeSingularMessageField(value: &v)
                if let v = v {
                    if hadOneofValue { try decoder.handleConflictingOneOf() }
                    self.choice = .choiceChild(v)
                }
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if let v = self._explicitInt { try visitor.visitSingularInt32Field(value: v, fieldNumber: 1) }
        if let v = self._explicitBool { try visitor.visitSingularBoolField(value: v, fieldNumber: 2) }
        if let v = self._explicitString { try visitor.visitSingularStringField(value: v, fieldNumber: 3) }
        if let v = self._explicitBytes { try visitor.visitSingularBytesField(value: v, fieldNumber: 4) }
        if let v = self._explicitDouble { try visitor.visitSingularDoubleField(value: v, fieldNumber: 5) }
        if let v = self._status { try visitor.visitSingularEnumField(value: v, fieldNumber: 6) }
        if self.implicitCount != 0 { try visitor.visitSingularInt32Field(value: self.implicitCount, fieldNumber: 7) }
        if self.implicitFlag != false { try visitor.visitSingularBoolField(value: self.implicitFlag, fieldNumber: 8) }
        if let v = self._child { try visitor.visitSingularMessageField(value: v, fieldNumber: 9) }
        if let v = self._delimitedChild { try visitor.visitSingularGroupField(value: v, fieldNumber: 10) }
        if !self.packedVals.isEmpty { try visitor.visitPackedInt32Field(value: self.packedVals, fieldNumber: 11) }
        if !self.expandedVals.isEmpty { try visitor.visitRepeatedInt32Field(value: self.expandedVals, fieldNumber: 12) }
        if !self.scores.isEmpty {
            try visitor.visitMapField(
                fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufInt32>.self,
                value: self.scores,
                fieldNumber: 13
            )
        }
        switch self.choice {
        case .choiceInt(let v)?: try visitor.visitSingularInt32Field(value: v, fieldNumber: 14)
        case .choiceText(let v)?: try visitor.visitSingularStringField(value: v, fieldNumber: 15)
        case .choiceFlag(let v)?: try visitor.visitSingularBoolField(value: v, fieldNumber: 16)
        case .choiceChild(let v)?: try visitor.visitSingularMessageField(value: v, fieldNumber: 17)
        case nil: break
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._explicitInt == rhs._explicitInt
            && lhs._explicitBool == rhs._explicitBool
            && lhs._explicitString == rhs._explicitString
            && lhs._explicitBytes == rhs._explicitBytes
            && lhs._explicitDouble == rhs._explicitDouble
            && lhs._status == rhs._status
            && lhs.implicitCount == rhs.implicitCount
            && lhs.implicitFlag == rhs.implicitFlag
            && lhs._child == rhs._child
            && lhs._delimitedChild == rhs._delimitedChild
            && lhs.packedVals == rhs.packedVals
            && lhs.expandedVals == rhs.expandedVals
            && lhs.scores == rhs.scores
            && lhs.choice == rhs.choice
            && lhs.unknownFields == rhs.unknownFields
    }

    static var omniBufSchemaMeta: SchemaMeta {
        let childMeta = PBEditionsChild<Tag>.omniBufSchemaMeta
        return SchemaMeta(
            typeName: Tag.payloadTypeName,
            fields: [
                1: "explicit_int", 2: "explicit_bool", 3: "explicit_string", 4: "explicit_bytes",
                5: "explicit_double", 6: "status", 7: "implicit_count", 8: "implicit_flag",
                9: "child", 10: "delimited_child", 11: "packed_vals", 12: "expanded_vals",
                13: "scores", 14: "choice_int", 15: "choice_text", 16: "choice_flag", 17: "choice_child",
            ],
            children: [9: childMeta, 10: childMeta, 17: childMeta]
        )
    }
}

typealias PBTestEditions2023 = PBTestEditions<PBEditions2023Tag>
typealias PBTestEditions2024 = PBTestEditions<PBEditions2024Tag>
typealias PBTestEditions2026 = PBTestEditions<PBEditions2026Tag>
