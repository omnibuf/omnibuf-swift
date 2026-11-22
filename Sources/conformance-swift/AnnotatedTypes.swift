import OmniBuf

// Tier 3: Native Swift Structs using `OmniBufStruct` declarative schema mapping.

struct AnnotatedLocation: OmniBufStruct, Equatable, Sendable {
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

struct AnnotatedNeighbor: OmniBufStruct, Equatable, Sendable {
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

struct AnnotatedPeerUpdate: OmniBufStruct, Equatable, Sendable {
    var asn: UInt32 = 0
    var routerId: String = ""
    var active: Bool = false
    var uptimeSec: UInt64 = 0
    var rssiDbm: Int32 = 0
    var cpuLoad: Double = 0
    var tags: [String] = []
    var prefixes: [UInt32] = []
    var location: AnnotatedLocation? = nil
    var neighbors: [AnnotatedNeighbor] = []
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

struct AnnotatedAllTypesSubMsg: OmniBufStruct, Equatable, Sendable {
    var id: UInt32 = 0
    var label: String = ""
    var flag: Bool = false
    var score: Int64 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "AllTypesSubMsg",
        fields: [
            Field.uint32(1, "id", \.id),
            Field.string(2, "label", \.label),
            Field.bool(3, "flag", \.flag),
            Field.sint64(4, "score", \.score),
        ]
    )
}

struct AnnotatedTestAllTypes: OmniBufStruct, Equatable, Sendable {
    var f1Uint32: UInt32 = 0
    var f2Uint64: UInt64 = 0
    var f3Sint32: Int32 = 0
    var f4Sint64: Int64 = 0
    var f5Bool: Bool = false
    var f6String: String = ""
    var f7Bytes: [UInt8] = []
    var f8SubMsg: AnnotatedAllTypesSubMsg? = nil
    var f9StringArr: [String] = []
    var f10Uint32Arr: [UInt32] = []
    var f11SubMsgArr: [AnnotatedAllTypesSubMsg] = []
    var f12MapStrUint: [String: UInt64] = [:]
    var f13Float32: Float = 0
    var f14Float64: Double = 0
    var f15Fixed32: UInt32 = 0
    var f16Fixed64: UInt64 = 0
    var f20OverflowStr: String = ""

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "TestAllTypes",
        fields: [
            Field.uint32(1, "f1_uint32", \.f1Uint32),
            Field.uint64(2, "f2_uint64", \.f2Uint64),
            Field.sint32(3, "f3_sint32", \.f3Sint32),
            Field.sint64(4, "f4_sint64", \.f4Sint64),
            Field.bool(5, "f5_bool", \.f5Bool),
            Field.string(6, "f6_string", \.f6String),
            Field.bytes(7, "f7_bytes", \.f7Bytes),
            Field.message(8, "f8_sub_msg", \.f8SubMsg),
            Field.stringArray(9, "f9_string_arr", \.f9StringArr),
            Field.uint32Array(10, "f10_uint32_arr", \.f10Uint32Arr),
            Field.messageArray(11, "f11_sub_msg_arr", \.f11SubMsgArr),
            Field.mapStringUint64(12, "f12_map_str_uint", \.f12MapStrUint),
            Field.float32(13, "f13_float32", \.f13Float32),
            Field.float64(14, "f14_float64", \.f14Float64),
            Field.fixed32(15, "f15_fixed32", \.f15Fixed32),
            Field.fixed64(16, "f16_fixed64", \.f16Fixed64),
            Field.string(20, "f20_overflow_str", \.f20OverflowStr),
        ]
    )
}

struct AnnotatedTreeNode: OmniBufStruct, Equatable, Sendable {
    var id: UInt32 = 0
    var name: String = ""
    var weight: Int64 = 0
    var primary: Indirect<AnnotatedTreeNode>? = nil
    var children: [AnnotatedTreeNode] = []
    var branches: [AnnotatedTreeNode] = []
    var labels: [String: UInt64] = [:]

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "TreeNode",
        fields: [
            Field.uint32(1, "id", \.id),
            Field.string(2, "name", \.name),
            Field.sint64(3, "weight", \.weight),
            Field.indirectMessage(4, "primary", \.primary),
            Field.messageArray(5, "children", \.children, omitEmpty: false),
            Field.messageArray(6, "branches", \.branches, omitEmpty: false),
            Field.mapStringUint64(7, "labels", \.labels, omitEmpty: false),
        ]
    )
}

struct AnnotatedNestedNIC: OmniBufStruct, Equatable, Sendable {
    var ifIndex: UInt32 = 0
    var mac: String = ""
    var ips: [UInt32] = []

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "NestedNIC",
        fields: [
            Field.uint32(1, "if_index", \.ifIndex),
            Field.string(2, "mac", \.mac),
            Field.uint32Array(3, "ips", \.ips),
        ]
    )
}

struct AnnotatedNestedServer: OmniBufStruct, Equatable, Sendable {
    var serverId: UInt32 = 0
    var hostname: String = ""
    var nics: [AnnotatedNestedNIC] = []

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "NestedServer",
        fields: [
            Field.uint32(1, "server_id", \.serverId),
            Field.string(2, "hostname", \.hostname),
            Field.messageArray(3, "nics", \.nics),
        ]
    )
}

struct AnnotatedNestedRack: OmniBufStruct, Equatable, Sendable {
    var rackId: UInt32 = 0
    var zone: String = ""
    var servers: [AnnotatedNestedServer] = []

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "NestedRack",
        fields: [
            Field.uint32(1, "rack_id", \.rackId),
            Field.string(2, "zone", \.zone),
            Field.messageArray(3, "servers", \.servers),
        ]
    )
}

struct AnnotatedNestedCluster: OmniBufStruct, Equatable, Sendable {
    var clusterName: String = ""
    var racks: [AnnotatedNestedRack] = []
    var epoch: UInt64 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "NestedCluster",
        fields: [
            Field.string(1, "cluster_name", \.clusterName),
            Field.messageArray(2, "racks", \.racks),
            Field.uint64(3, "epoch", \.epoch),
        ]
    )
}
