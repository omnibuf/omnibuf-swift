import Foundation
import OmniBuf
import SwiftProtobuf

// MARK: - Tier 3 Struct + Codable JSON Model

struct BenchLocation: OmniBufStruct, Codable, Equatable, Sendable {
    var region: String = ""
    var datacenter: String = ""
    var city: String = ""
    var rack: UInt32 = 0
    var latitude: Float = 0
    var longitude: Float = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "Location",
        fields: [
            Field.string(1, "region", \.region),
            Field.string(2, "datacenter", \.datacenter),
            Field.string(3, "city", \.city),
            Field.uint32(4, "rack", \.rack),
            Field.float32(5, "latitude", \.latitude),
            Field.float32(6, "longitude", \.longitude),
        ]
    )
}

struct BenchNeighbor: OmniBufStruct, Codable, Equatable, Sendable {
    var peerAsn: UInt32 = 0
    var router: String = ""
    var latencyUs: UInt32 = 0
    var established: Bool = false

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "Neighbor",
        fields: [
            Field.uint32(1, "peer_asn", \.peerAsn),
            Field.string(2, "router", \.router),
            Field.uint32(3, "latency_us", \.latencyUs),
            Field.bool(4, "established", \.established),
        ]
    )
}

struct BenchPeerUpdate: OmniBufStruct, Codable, Equatable, Sendable {
    var asn: UInt32 = 0
    var routerId: String = ""
    var active: Bool = false
    var uptimeSec: UInt64 = 0
    var rssiDbm: Int32 = 0
    var cpuLoad: Double = 0
    var tags: [String] = []
    var prefixes: [UInt32] = []
    var location: BenchLocation? = nil
    var neighbors: [BenchNeighbor] = []
    var sequence: UInt64 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "PeerUpdate",
        fields: [
            Field.uint32(1, "asn", \.asn),
            Field.string(2, "router_id", \.routerId),
            Field.bool(3, "active", \.active),
            Field.uint64(4, "uptime_sec", \.uptimeSec),
            Field.sint32(5, "rssi_dbm", \.rssiDbm),
            Field.float64(6, "cpu_load", \.cpuLoad),
            Field.stringArray(7, "tags", \.tags),
            Field.uint32Array(8, "prefixes", \.prefixes),
            Field.message(9, "location", \.location),
            Field.messageArray(10, "neighbors", \.neighbors),
            Field.uint64(11, "sequence", \.sequence),
        ]
    )
}

// MARK: - SwiftProtobuf Model

struct BenchPBLocation: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.region == rhs.region && lhs.datacenter == rhs.datacenter && lhs.city == rhs.city
            && lhs.rack == rhs.rack && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct BenchPBNeighbor: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.peerAsn == rhs.peerAsn && lhs.router == rhs.router
            && lhs.latencyUs == rhs.latencyUs && lhs.established == rhs.established
    }
}

struct BenchPBPeerUpdate: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable {
    static let protoMessageName: String = "omnibuf.bench.PeerUpdate"
    var asn: UInt32 = 0
    var routerID: String = ""
    var active: Bool = false
    var uptimeSec: UInt64 = 0
    var rssiDbm: Int32 = 0
    var cpuLoad: Double = 0
    var tags: [String] = []
    var prefixes: [UInt32] = []
    private var _location: BenchPBLocation? = nil
    var location: BenchPBLocation {
        get { _location ?? BenchPBLocation() }
        set { _location = newValue }
    }
    var hasLocation: Bool { _location != nil }
    var neighbors: [BenchPBNeighbor] = []
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.asn == rhs.asn && lhs.routerID == rhs.routerID && lhs.active == rhs.active
            && lhs.uptimeSec == rhs.uptimeSec && lhs.rssiDbm == rhs.rssiDbm && lhs.cpuLoad == rhs.cpuLoad
            && lhs.tags == rhs.tags && lhs.prefixes == rhs.prefixes && lhs._location == rhs._location
            && lhs.neighbors == rhs.neighbors && lhs.sequence == rhs.sequence
    }
}
