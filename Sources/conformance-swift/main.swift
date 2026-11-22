import Foundation
import OmniBuf
import OmniBufProtobuf
import SwiftProtobuf

private let maxFrameBytes = 16 * 1024 * 1024
private let wireFormatJSON: UInt32 = 2

private let tierPlugin: UInt32 = 1
private let tierProtobufTypes: UInt32 = 2
private let tierAnnotatedStruct: UInt32 = 3
private let tierBlind: UInt32 = 4

// MARK: - Conformance IPC Framing Structs

struct IPCRequest: OmniBufStruct, Sendable {
    var testName: String = ""
    var messageType: String = ""
    var tier: UInt32 = 0
    var requestedOutputFormat: UInt32 = 0
    var omnibufPayload: [UInt8] = []
    var jsonPayload: String = ""
    var selfDescribing: Bool = false
    var testOpaqueSplice: Bool = false
    var testOpaqueSpliceShrink: Bool = false

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "ConformanceRequest",
        fields: [
            Field.string(1, "test_name", \.testName),
            Field.string(2, "message_type", \.messageType),
            Field.uint32(3, "tier", \.tier),
            Field.uint32(4, "requested_output_format", \.requestedOutputFormat),
            Field.bytes(5, "omnibuf_payload", \.omnibufPayload),
            Field.string(6, "json_payload", \.jsonPayload),
            Field.bool(7, "self_describing", \.selfDescribing),
            Field.bool(8, "test_opaque_splice", \.testOpaqueSplice),
            Field.bool(9, "test_opaque_splice_shrink", \.testOpaqueSpliceShrink),
        ]
    )
}

struct IPCResponse: OmniBufStruct, Sendable {
    var parseError: String = ""
    var serializeError: String = ""
    var runtimeError: String = ""
    var skipped: String = ""
    var omnibufPayload: [UInt8] = []
    var jsonPayload: String = ""

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "ConformanceResponse",
        fields: [
            Field.string(1, "parse_error", \.parseError),
            Field.string(2, "serialize_error", \.serializeError),
            Field.string(3, "runtime_error", \.runtimeError),
            Field.string(4, "skipped", \.skipped),
            Field.bytes(5, "omnibuf_payload", \.omnibufPayload),
            Field.string(6, "json_payload", \.jsonPayload),
        ]
    )

    static func parseErr(_ msg: String) -> IPCResponse { var r = IPCResponse(); r.parseError = msg; return r }
    static func serializeErr(_ msg: String) -> IPCResponse { var r = IPCResponse(); r.serializeError = msg; return r }
    static func runtimeErr(_ msg: String) -> IPCResponse { var r = IPCResponse(); r.runtimeError = msg; return r }
    static func skippedReason(_ msg: String) -> IPCResponse { var r = IPCResponse(); r.skipped = msg; return r }
    static func wire(_ bytes: [UInt8]) -> IPCResponse { var r = IPCResponse(); r.omnibufPayload = bytes; return r }
    static func json(_ s: String) -> IPCResponse { var r = IPCResponse(); r.jsonPayload = s; return r }
}

// MARK: - Stdin / Stdout Exact I/O

private func readExact(_ count: Int, from fd: Int32) -> [UInt8]? {
    if count == 0 { return [] }
    var buf = [UInt8](repeating: 0, count: count)
    var offset = 0
    while offset < count {
        let n = buf.withUnsafeMutableBytes { raw -> Int in
            read(fd, raw.baseAddress!.advanced(by: offset), count - offset)
        }
        if n == 0 {
            return offset == 0 ? nil : nil
        }
        if n < 0 {
            if errno == EINTR { continue }
            return nil
        }
        offset += n
    }
    return buf
}

private func writeExact(_ bytes: [UInt8], to fd: Int32) -> Bool {
    var offset = 0
    let total = bytes.count
    while offset < total {
        let n = bytes.withUnsafeBytes { raw -> Int in
            write(fd, raw.baseAddress!.advanced(by: offset), total - offset)
        }
        if n < 0 {
            if errno == EINTR { continue }
            return false
        }
        offset += n
    }
    return true
}

// MARK: - Tier 4: Blind Inspection

private func handleBlindTier(_ req: IPCRequest) -> IPCResponse {
    if req.requestedOutputFormat == wireFormatJSON {
        do {
            let js = try decodeBlindJSON(req.omnibufPayload)
            return .json(js)
        } catch OmniBufError.serialize {
            return .json("{}")
        } catch {
            return .parseErr("\(error)")
        }
    }
    do {
        _ = try decodeBlind(req.omnibufPayload)
        return IPCResponse()
    } catch {
        return .parseErr("\(error)")
    }
}

// MARK: - Tier 1: Plugin-Generated Code + Opaque Views & Splicing

private func float32CanonicalBits(_ f: Float) -> UInt32 {
    f.isNaN ? 0x7fc0_0000 : f.bitPattern
}

private func float64CanonicalBits(_ d: Double) -> UInt64 {
    d.isNaN ? 0x7ff8_0000_0000_0000 : d.bitPattern
}

private func checkSpliceAliasedPrefix(_ packet: [UInt8]) -> String? {
    let appendDirty: (inout OmniBufWriter, UInt16) -> Void = { w, fnum in
        w.appendTag(fieldNumber: UInt32(fnum), wireType: WireType.wireUint)
        w.appendVarint(1 << 40)
    }
    let original = packet
    var spliced: [UInt8] = []
    OpaqueWire.spliceFields(into: &spliced, raw: packet, dirtyMask: 1 << 1, maxField: 2, appendDirty: appendDirty)

    for prefixLen in [0, 3, 32] {
        let prefix = [UInt8](repeating: 0xA5, count: prefixLen)
        var dst = prefix
        var want = prefix
        want.append(contentsOf: spliced)

        OpaqueWire.spliceFields(into: &dst, raw: packet, dirtyMask: 1 << 1, maxField: 2, appendDirty: appendDirty)
        if dst != want {
            return "opaque splice with \(prefixLen)-byte prefix changed prefix or output"
        }
        if packet != original {
            return "opaque splice modified source packet"
        }
    }
    return nil
}

private func handlePluginTier(_ req: IPCRequest) -> IPCResponse {
    switch req.messageType {
    case "omnibuf.bench.PeerUpdate":
        if req.testOpaqueSplice || req.testOpaqueSpliceShrink {
            var probe = OpaquePeerUpdate(req.omnibufPayload)
            probe.setSequence(probe.getSequence() &+ 1)
            do {
                _ = try probe.tryMarshal()
            } catch {
                return .parseErr("\(error)")
            }
        }
        var msg = PeerUpdate(
            asn: 999_999,
            routerId: "stale-router",
            active: true,
            uptimeSec: 123,
            rssiDbm: -42,
            cpuLoad: 1.5,
            tags: ["stale-tag"],
            prefixes: [999],
            location: Location(region: "stale", datacenter: "stale-dc", city: "stale-city", rack: 999, latitude: 1.0, longitude: 2.0),
            neighbors: [Neighbor(peerAsn: 999, router: "stale-neighbor", latencyUs: 10, established: true)],
            sequence: 999_999
        )
        do {
            try msg.decodeOmniBuf(from: req.omnibufPayload)
        } catch {
            return .parseErr("\(error)")
        }
        if req.testOpaqueSplice || req.testOpaqueSpliceShrink {
            if let err = checkSpliceAliasedPrefix(req.omnibufPayload) {
                return .runtimeErr(err)
            }
        }

        var op = OpaquePeerUpdate(req.omnibufPayload)
        let wantCity = msg.location?.city ?? ""
        if op.getAsn() != msg.asn
            || op.getRouterId() != msg.routerId
            || op.getActive() != msg.active
            || op.getUptimeSec() != msg.uptimeSec
            || op.getRssiDbm() != msg.rssiDbm
            || float64CanonicalBits(op.getCpuLoad()) != float64CanonicalBits(msg.cpuLoad)
            || op.tagsCount != msg.tags.count
            || op.prefixesCount != msg.prefixes.count
            || op.getLocation().getCity() != wantCity
            || op.neighborsCount != msg.neighbors.count
            || op.getSequence() != msg.sequence
        {
            return .parseErr("opaque PeerUpdate getter mismatch with decoded struct")
        }

        if req.testOpaqueSplice {
            let nextActive = !op.getActive()
            let nextSeq = op.getSequence() &+ 1
            op.setAsn(1_000_000)
            op.setRouterId(String(repeating: "edge-rtr-fra01-", count: 20))
            op.setActive(nextActive)
            op.setUptimeSec(UInt64.max)
            op.setRssiDbm(-1_000_000)
            op.setCpuLoad(99.875)
            op.setTags(["tag-grow-a", "tag-grow-b", String(repeating: "long-tag-", count: 20)])
            op.setPrefixes([100_000, 200_000, 300_000, 400_000, 500_000, 600_000])
            op.setLocation(Location(
                region: "eu-central-grown",
                datacenter: String(repeating: "fra-dc-", count: 25),
                city: "Berlin",
                rack: 999_999,
                latitude: 52.52,
                longitude: 13.405
            ))
            op.setSequence(nextSeq)
            do {
                return .wire(try op.tryMarshal())
            } catch {
                return .serializeErr("\(error)")
            }
        }

        if req.testOpaqueSpliceShrink {
            op.setAsn(1)
            op.setRouterId("r")
            op.setActive(false)
            op.setUptimeSec(5)
            op.setRssiDbm(-1)
            op.setCpuLoad(0.5)
            op.setTags(["t"])
            op.setPrefixes([1])
            op.setLocation(Location(region: "r", datacenter: "d", city: "c", rack: 1, latitude: 1.0, longitude: 2.0))
            op.setSequence(2)
            do {
                return .wire(try op.tryMarshal())
            } catch {
                return .serializeErr("\(error)")
            }
        }

        do {
            let out = try msg.encodeOmniBuf(options: EncodeOptions(deterministic: true, selfDescribing: req.selfDescribing))
            return .wire(out)
        } catch {
            return .serializeErr("\(error)")
        }

    case "omnibuf.conformance.TestAllTypes":
        if req.testOpaqueSplice || req.testOpaqueSpliceShrink {
            var probe = OpaqueTestAllTypes(req.omnibufPayload)
            probe.setF1Uint32(probe.getF1Uint32() &+ 1)
            do {
                _ = try probe.tryMarshal()
            } catch {
                return .parseErr("\(error)")
            }
        }
        var msg = TestAllTypes(
            f1Uint32: 999_999,
            f5Bool: true,
            f6String: "stale-str",
            f7Bytes: [0xFF],
            f8SubMsg: AllTypesSubMsg(id: 999, label: "stale-sub", flag: true, score: -999),
            f9StringArr: ["stale"],
            f10Uint32Arr: [999],
            f11SubMsgArr: [AllTypesSubMsg(id: 999, label: "stale-elem", flag: false, score: 0)],
            f12MapStrUint: ["stale": 999],
            f20OverflowStr: "stale-overflow"
        )
        do {
            try msg.decodeOmniBuf(from: req.omnibufPayload)
        } catch {
            return .parseErr("\(error)")
        }
        if req.testOpaqueSplice || req.testOpaqueSpliceShrink {
            if let err = checkSpliceAliasedPrefix(req.omnibufPayload) {
                return .runtimeErr(err)
            }
        }

        var op = OpaqueTestAllTypes(req.omnibufPayload)
        _ = op.lookupF12MapStrUint("k")
        let wantSub = msg.f8SubMsg ?? AllTypesSubMsg()
        let opSub = op.getF8SubMsg()
        if op.getF1Uint32() != msg.f1Uint32
            || op.getF2Uint64() != msg.f2Uint64
            || op.getF3Sint32() != msg.f3Sint32
            || op.getF4Sint64() != msg.f4Sint64
            || op.getF5Bool() != msg.f5Bool
            || op.getF6String() != msg.f6String
            || op.getF7Bytes() != msg.f7Bytes
            || opSub.getId() != wantSub.id
            || opSub.getLabel() != wantSub.label
            || opSub.getFlag() != wantSub.flag
            || opSub.getScore() != wantSub.score
            || op.f9StringArrCount != msg.f9StringArr.count
            || op.f10Uint32ArrCount != msg.f10Uint32Arr.count
            || op.f11SubMsgArrCount != msg.f11SubMsgArr.count
            || float32CanonicalBits(op.getF13Float32()) != float32CanonicalBits(msg.f13Float32)
            || float64CanonicalBits(op.getF14Float64()) != float64CanonicalBits(msg.f14Float64)
            || op.getF15Fixed32() != msg.f15Fixed32
            || op.getF16Fixed64() != msg.f16Fixed64
            || op.getF20OverflowStr() != msg.f20OverflowStr
        {
            return .parseErr("opaque TestAllTypes getter mismatch with decoded struct")
        }

        if req.testOpaqueSplice {
            let nextBool = !op.getF5Bool()
            op.setF1Uint32(1_000_000)
            op.setF2Uint64(UInt64.max)
            op.setF3Sint32(-1_000_000)
            op.setF4Sint64(Int64.min)
            op.setF5Bool(nextBool)
            op.setF6String(String(repeating: "grown-str-", count: 30))
            var bytes260: [UInt8] = []
            bytes260.reserveCapacity(260)
            for _ in 0..<130 { bytes260.append(0xAB); bytes260.append(0xCD) }
            op.setF7Bytes(bytes260)
            op.setF8SubMsg(AllTypesSubMsg(id: 888_888, label: String(repeating: "sub-grown-", count: 20), flag: true, score: -999_999_999))
            op.setF9StringArr(["arr-grow-1", "arr-grow-2", String(repeating: "arr-grow-3-", count: 15)])
            op.setF10Uint32Arr([100_000, 200_000, 300_000, 400_000, 500_000])
            op.setF11SubMsgArr([
                AllTypesSubMsg(id: 100_001, label: String(repeating: "elem0-", count: 25), flag: true, score: -500_000),
                AllTypesSubMsg(id: 100_002, label: "elem1-grown", flag: false, score: 500_000),
            ])
            op.setF12MapStrUint(["k1": 1_000_000, "k2": UInt64.max, "k3_long_key": 424_242])
            op.setF13Float32(-1234.5)
            op.setF14Float64(3.141592653589793)
            op.setF15Fixed32(0xDEAD_BEEF)
            op.setF16Fixed64(0xCAFE_BABE_DEAD_BEEF)
            op.setF20OverflowStr(String(repeating: "overflow20-", count: 20))
            do {
                return .wire(try op.tryMarshal())
            } catch {
                return .serializeErr("\(error)")
            }
        }

        if req.testOpaqueSpliceShrink {
            op.setF1Uint32(1)
            op.setF2Uint64(2)
            op.setF3Sint32(-1)
            op.setF4Sint64(-2)
            op.setF5Bool(false)
            op.setF6String("s")
            op.setF7Bytes([0x01])
            op.setF8SubMsg(AllTypesSubMsg(id: 1, label: "x", flag: false, score: -1))
            op.setF9StringArr(["a"])
            op.setF10Uint32Arr([7])
            op.setF11SubMsgArr([AllTypesSubMsg(id: 1, label: "e", flag: true, score: 1)])
            op.setF12MapStrUint(["k": 1])
            op.setF13Float32(0.5)
            op.setF14Float64(-0.25)
            op.setF15Fixed32(7)
            op.setF16Fixed64(9)
            op.setF20OverflowStr("z")
            do {
                return .wire(try op.tryMarshal())
            } catch {
                return .serializeErr("\(error)")
            }
        }

        do {
            let out = try msg.encodeOmniBuf(options: EncodeOptions(deterministic: true, selfDescribing: req.selfDescribing))
            return .wire(out)
        } catch {
            return .serializeErr("\(error)")
        }

    default:
        return .skippedReason("plugin tier generated for PeerUpdate and TestAllTypes")
    }
}

// MARK: - Tier 2: SwiftProtobuf.Message Integration

private func handleProtobufTypesTier(_ req: IPCRequest) -> IPCResponse {
    let opts = EncodeOptions(deterministic: true, selfDescribing: req.selfDescribing)
    switch req.messageType {
    case "omnibuf.bench.PeerUpdate":
        var msg = PBPeerUpdate()
        msg.asn = 999_999
        msg.routerID = "stale-router"
        msg.active = true
        msg.uptimeSec = 55
        msg.rssiDbm = -12
        msg.cpuLoad = 42.0
        msg.tags = ["stale"]
        msg.prefixes = [999]
        var loc = PBLocation()
        loc.region = "stale"
        loc.datacenter = "stale"
        loc.city = "stale"
        loc.rack = 999
        msg.location = loc
        var nb = PBNeighbor()
        nb.peerAsn = 999
        nb.router = "stale"
        msg.neighbors = [nb]
        msg.sequence = 999
        do {
            try OmniBufProtobuf.decode(into: &msg, from: req.omnibufPayload)
        } catch {
            return .parseErr("\(error)")
        }
        do {
            return .wire(try OmniBufProtobuf.encode(msg, options: opts))
        } catch {
            return .serializeErr("\(error)")
        }

    case "omnibuf.conformance.TestAllTypes":
        var msg = PBTestAllTypes()
        msg.f1Uint32 = 999_999
        msg.f5Bool = true
        msg.f6String = "stale"
        msg.f7Bytes = Data([0xAA])
        var sub = PBAllTypesSubMsg()
        sub.id = 999
        sub.label = "stale"
        msg.f8SubMsg = sub
        msg.f9StringArr = ["stale"]
        msg.f10Uint32Arr = [999]
        msg.f11SubMsgArr = [sub]
        msg.f12MapStrUint = ["stale": 999]
        msg.f20OverflowStr = "stale"
        do {
            try OmniBufProtobuf.decode(into: &msg, from: req.omnibufPayload)
        } catch {
            return .parseErr("\(error)")
        }
        do {
            return .wire(try OmniBufProtobuf.encode(msg, options: opts))
        } catch {
            return .serializeErr("\(error)")
        }

    default:
        return .skippedReason("protobuf types tier generated for PeerUpdate and TestAllTypes")
    }
}

// MARK: - Tier 3: Native Swift Annotated Structs

private func roundTripAnnotated<M: OmniBufMessage>(_ payload: [UInt8], _ msg: inout M, _ opts: EncodeOptions) -> IPCResponse {
    do {
        try msg.decodeOmniBuf(from: payload)
    } catch {
        return .parseErr("\(error)")
    }
    do {
        return .wire(try msg.encodeOmniBuf(options: opts))
    } catch {
        return .serializeErr("\(error)")
    }
}

private func handleAnnotatedStructTier(_ req: IPCRequest) -> IPCResponse {
    let opts = EncodeOptions(deterministic: true, selfDescribing: req.selfDescribing)
    switch req.messageType {
    case "omnibuf.bench.PeerUpdate":
        var msg = AnnotatedPeerUpdate(
            asn: 999_999, routerId: "stale-router", active: true, uptimeSec: 123,
            rssiDbm: -70, cpuLoad: 12.5, tags: ["stale-tag"], prefixes: [999],
            location: AnnotatedLocation(region: "stale", datacenter: "stale", city: "stale", rack: 999, latitude: 1, longitude: 2),
            neighbors: [AnnotatedNeighbor(peerAsn: 999, router: "stale", latencyUs: 5, established: true)],
            sequence: 999_999
        )
        return roundTripAnnotated(req.omnibufPayload, &msg, opts)

    case "omnibuf.conformance.TreeNode":
        var msg = AnnotatedTreeNode(
            id: 999, name: "stale-root", weight: -999,
            primary: Indirect(AnnotatedTreeNode(id: 888, name: "stale-primary")),
            children: [AnnotatedTreeNode(id: 777, name: "stale-child")],
            branches: [AnnotatedTreeNode(id: 666, name: "stale-branch")],
            labels: ["stale": 1]
        )
        return roundTripAnnotated(req.omnibufPayload, &msg, opts)

    case "omnibuf.conformance.NestedCluster":
        var msg = AnnotatedNestedCluster(
            clusterName: "stale-cluster",
            racks: [AnnotatedNestedRack(
                rackId: 999, zone: "stale-zone",
                servers: [AnnotatedNestedServer(
                    serverId: 999, hostname: "stale-host",
                    nics: [AnnotatedNestedNIC(ifIndex: 99, mac: "ff:ff:ff:ff:ff:ff", ips: [123])]
                )]
            )],
            epoch: 999
        )
        return roundTripAnnotated(req.omnibufPayload, &msg, opts)

    default:
        var msg = AnnotatedTestAllTypes(
            f1Uint32: 999_999, f5Bool: true, f6String: "stale-str", f7Bytes: [0xFF],
            f8SubMsg: AnnotatedAllTypesSubMsg(id: 999, label: "stale-sub", flag: true, score: -999),
            f9StringArr: ["stale"], f10Uint32Arr: [999],
            f11SubMsgArr: [AnnotatedAllTypesSubMsg(id: 999, label: "stale-elem")],
            f12MapStrUint: ["stale": 999], f20OverflowStr: "stale-overflow"
        )
        return roundTripAnnotated(req.omnibufPayload, &msg, opts)
    }
}

// MARK: - Main Frame Loop

func runConformanceLoop() {
    let stdinFD = FileHandle.standardInput.fileDescriptor
    let stdoutFD = FileHandle.standardOutput.fileDescriptor

    while true {
        guard let lenBytes = readExact(4, from: stdinFD) else {
            break
        }
        let size = Int(UInt32(lenBytes[0])
            | (UInt32(lenBytes[1]) << 8)
            | (UInt32(lenBytes[2]) << 16)
            | (UInt32(lenBytes[3]) << 24))
        if size > maxFrameBytes {
            fputs("conformance-swift: frame size \(size) exceeds limit\n", stderr)
            exit(1)
        }
        let payload: [UInt8]
        if size == 0 {
            payload = []
        } else {
            guard let p = readExact(size, from: stdinFD) else {
                fputs("conformance-swift: unexpected EOF reading frame payload\n", stderr)
                exit(1)
            }
            payload = p
        }

        let req: IPCRequest
        do {
            req = try IPCRequest.decoded(from: payload)
        } catch {
            fputs("conformance-swift: failed to decode ConformanceRequest: \(error)\n", stderr)
            exit(1)
        }

        let resp: IPCResponse
        switch req.tier {
        case tierBlind:
            resp = handleBlindTier(req)
        case tierPlugin:
            resp = handlePluginTier(req)
        case tierProtobufTypes:
            resp = handleProtobufTypesTier(req)
        case tierAnnotatedStruct:
            resp = handleAnnotatedStructTier(req)
        default:
            resp = .runtimeErr("unsupported tier: \(req.tier)")
        }

        let outBytes: [UInt8]
        do {
            outBytes = try resp.encodeOmniBuf()
        } catch {
            fputs("conformance-swift: failed to encode ConformanceResponse: \(error)\n", stderr)
            exit(1)
        }

        let outLen = UInt32(outBytes.count)
        let header: [UInt8] = [
            UInt8(outLen & 0xFF),
            UInt8((outLen >> 8) & 0xFF),
            UInt8((outLen >> 16) & 0xFF),
            UInt8((outLen >> 24) & 0xFF),
        ]
        if !writeExact(header, to: stdoutFD) || !writeExact(outBytes, to: stdoutFD) {
            fputs("conformance-swift: failed to write frame\n", stderr)
            exit(1)
        }
    }
}

runConformanceLoop()
