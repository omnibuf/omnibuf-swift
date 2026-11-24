import Foundation
import OmniBuf
import OmniBufGenerated
import SwiftProtobuf

// MARK: - Benchmark Report JSON Schema

struct BenchmarkReport: Encodable {
    let language: String
    let runtime: String
    let platform: String
    let arch: String
    let cpu: String
    let workload: String
    let categories: [BenchmarkCategory]
}

struct BenchmarkCategory: Encodable {
    let id: String
    let title: String
    let unit: String
    let results: [BenchmarkResult]
}

struct BenchmarkResult: Encodable {
    let name: String
    let nsPerOp: UInt64
    let opsPerSec: UInt64
    let wireBytes: Int?
    let highlight: Bool?
    let baseline: Bool?
}

@inline(never)
func blackBox<T>(_ value: T) {
    withUnsafePointer(to: value) { ptr in
        _ = ptr
    }
}

// MARK: - Sample Workloads (Canonical PeerUpdate)

func sampleGenerated() -> PeerUpdate {
    PeerUpdate(
        asn: 64_512,
        routerId: "edge-rtr-fra01.core.backbone.net",
        active: true,
        uptimeSec: 1_849_203,
        rssiDbm: -62,
        cpuLoad: 0.42875,
        tags: ["tier1", "ebgp", "eu-central", "ixp-de-cix"],
        prefixes: [167_772_160, 172_032_000, 3_232_235_520, 2_886_729_728, 134_744_072, 134_743_040],
        location: Location(
            region: "eu-central-1",
            datacenter: "FRA-Equinix-FR5",
            city: "Frankfurt",
            rack: 42,
            latitude: 50.1109,
            longitude: 8.6821
        ),
        neighbors: [
            Neighbor(peerAsn: 3356, router: "ae0.fra1.level3.net", latencyUs: 850, established: true),
            Neighbor(peerAsn: 1299, router: "ffm-b5-link.telia.net", latencyUs: 920, established: true),
            Neighbor(peerAsn: 174, router: "be2040.ccr41.fra03.atlas.cogentco.com", latencyUs: 1120, established: true),
            Neighbor(peerAsn: 2914, router: "ae-12.r24.frnkge08.de.bb.gin.ntt.net", latencyUs: 980, established: false),
        ],
        sequence: 9_876_543_210
    )
}

func sampleStruct() -> BenchPeerUpdate {
    BenchPeerUpdate(
        asn: 64_512,
        routerId: "edge-rtr-fra01.core.backbone.net",
        active: true,
        uptimeSec: 1_849_203,
        rssiDbm: -62,
        cpuLoad: 0.42875,
        tags: ["tier1", "ebgp", "eu-central", "ixp-de-cix"],
        prefixes: [167_772_160, 172_032_000, 3_232_235_520, 2_886_729_728, 134_744_072, 134_743_040],
        location: BenchLocation(
            region: "eu-central-1",
            datacenter: "FRA-Equinix-FR5",
            city: "Frankfurt",
            rack: 42,
            latitude: 50.1109,
            longitude: 8.6821
        ),
        neighbors: [
            BenchNeighbor(peerAsn: 3356, router: "ae0.fra1.level3.net", latencyUs: 850, established: true),
            BenchNeighbor(peerAsn: 1299, router: "ffm-b5-link.telia.net", latencyUs: 920, established: true),
            BenchNeighbor(peerAsn: 174, router: "be2040.ccr41.fra03.atlas.cogentco.com", latencyUs: 1120, established: true),
            BenchNeighbor(peerAsn: 2914, router: "ae-12.r24.frnkge08.de.bb.gin.ntt.net", latencyUs: 980, established: false),
        ],
        sequence: 9_876_543_210
    )
}

func sampleSwiftProtobuf() -> BenchPBPeerUpdate {
    var m = BenchPBPeerUpdate()
    m.asn = 64_512
    m.routerID = "edge-rtr-fra01.core.backbone.net"
    m.active = true
    m.uptimeSec = 1_849_203
    m.rssiDbm = -62
    m.cpuLoad = 0.42875
    m.tags = ["tier1", "ebgp", "eu-central", "ixp-de-cix"]
    m.prefixes = [167_772_160, 172_032_000, 3_232_235_520, 2_886_729_728, 134_744_072, 134_743_040]
    var loc = BenchPBLocation()
    loc.region = "eu-central-1"
    loc.datacenter = "FRA-Equinix-FR5"
    loc.city = "Frankfurt"
    loc.rack = 42
    loc.latitude = 50.1109
    loc.longitude = 8.6821
    m.location = loc
    let nbData: [(UInt32, String, UInt32, Bool)] = [
        (3356, "ae0.fra1.level3.net", 850, true),
        (1299, "ffm-b5-link.telia.net", 920, true),
        (174, "be2040.ccr41.fra03.atlas.cogentco.com", 1120, true),
        (2914, "ae-12.r24.frnkge08.de.bb.gin.ntt.net", 980, false),
    ]
    m.neighbors = nbData.map { d in
        var n = BenchPBNeighbor()
        n.peerAsn = d.0; n.router = d.1; n.latencyUs = d.2; n.established = d.3
        return n
    }
    m.sequence = 9_876_543_210
    return m
}

// MARK: - Timing Harness

func measure(
    name: String,
    wireBytes: Int? = nil,
    highlight: Bool = false,
    baseline: Bool = false,
    _ op: () -> Void
) -> BenchmarkResult {
    let clock = ContinuousClock()
    // Warm up for 80ms
    let warmupStart = clock.now
    var warmupIters: UInt64 = 0
    while clock.now - warmupStart < .milliseconds(80) {
        for _ in 0..<64 { op() }
        warmupIters += 64
    }
    let warmupDur = clock.now - warmupStart
    let warmupNs = Double(warmupDur.components.seconds) * 1e9 + Double(warmupDur.components.attoseconds) * 1e-9
    let estNs = max(warmupNs / Double(max(warmupIters, 1)), 1.0)
    let batch = UInt64(min(max(Int(2_000_000.0 / estNs), 16), 100_000))

    // 7 independent 45ms trials, median ns/op
    var samples: [Double] = []
    samples.reserveCapacity(7)
    for _ in 0..<7 {
        let trialStart = clock.now
        var iters: UInt64 = 0
        while clock.now - trialStart < .milliseconds(45) {
            for _ in 0..<batch { op() }
            iters += batch
        }
        let d = clock.now - trialStart
        let ns = Double(d.components.seconds) * 1e9 + Double(d.components.attoseconds) * 1e-9
        samples.append(ns / Double(iters))
    }
    samples.sort()
    let medianNs = samples[samples.count / 2]
    let nsPerOp = max(UInt64(medianNs.rounded()), 1)
    let opsPerSec = UInt64((1_000_000_000.0 / medianNs).rounded())

    return BenchmarkResult(
        name: name,
        nsPerOp: nsPerOp,
        opsPerSec: opsPerSec,
        wireBytes: wireBytes,
        highlight: highlight ? true : nil,
        baseline: baseline ? true : nil
    )
}

func runShell(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

func detectRuntime() -> String {
    if let raw = runShell("/usr/bin/env", ["swift", "--version"]) {
        if let range = raw.range(of: "Apple Swift version ") {
            let tail = raw[range.upperBound...]
            if let space = tail.firstIndex(of: " ") {
                return "Swift \(tail[..<space])"
            }
        }
        if let range = raw.range(of: "Swift version ") {
            let tail = raw[range.upperBound...]
            if let space = tail.firstIndex(of: " ") {
                return "Swift \(tail[..<space])"
            }
        }
    }
    return "Swift 6"
}

func detectCPU() -> String {
    #if os(macOS)
    if let brand = runShell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]), !brand.isEmpty {
        return brand
    }
    #endif
    return "Unknown CPU"
}

func padLeft(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

func padRight(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func printCategory(_ cat: BenchmarkCategory) {
    let baseNs = Double(cat.results.first(where: { $0.baseline == true })?.nsPerOp ?? 1)
    print("\n=== \(cat.title) ===")
    print("\(padRight("Codec", 28)) \(padLeft("ns/op", 10)) \(padLeft("ops/sec", 14)) \(padLeft("wire (B)", 10)) \(padLeft("vs OmniBuf", 10))")
    print(String(repeating: "-", count: 76))
    for r in cat.results {
        let wireCol = r.wireBytes.map { String($0) } ?? "-"
        let ratio = Double(r.nsPerOp) / baseNs
        let rel = r.baseline == true ? "1.00x" : String(format: "%.2fx", ratio)
        print("\(padRight(r.name, 28)) \(padLeft(String(r.nsPerOp), 10)) \(padLeft(String(r.opsPerSec), 14)) \(padLeft(wireCol, 10)) \(padLeft(rel, 10))")
    }
}

// MARK: - Main

func runBenchmarks() throws {
    let genMsg = sampleGenerated()
    let structMsg = sampleStruct()
    let pbMsg = sampleSwiftProtobuf()

    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()

    let omnibufBytes = genMsg.marshalOmniBuf()
    let structBytes = try structMsg.encodeOmniBuf()
    let pbData = try pbMsg.serializedData()
    let jsonData = try jsonEncoder.encode(structMsg)

    precondition(omnibufBytes.count == 365 || omnibufBytes.count == 366, "OmniBuf SamplePeerUpdate wire size unexpected: \(omnibufBytes.count)")
    precondition(structBytes == omnibufBytes, "Struct schema wire output must match generated output")
    precondition(pbData.count == 341, "SwiftProtobuf SamplePeerUpdate wire size must be 341B, got \(pbData.count)")

    // Verify round-trips
    let checkGen = try PeerUpdate.decoded(from: omnibufBytes)
    precondition(checkGen == genMsg)
    let checkStruct = try BenchPeerUpdate.decoded(from: structBytes)
    precondition(checkStruct == structMsg)
    let checkPB = try BenchPBPeerUpdate(serializedBytes: pbData)
    precondition(checkPB == pbMsg)
    let checkJSON = try jsonDecoder.decode(BenchPeerUpdate.self, from: jsonData)
    precondition(checkJSON == structMsg)
    precondition(OpaquePeerUpdate(omnibufBytes).getLocation().getCity() == "Frankfurt")

    // Category 5: Large Embedded Message Encode (>16 KiB submessage + cascading array shift)
    let shiftDC = String(repeating: "d", count: 20_480)
    let shiftRtr = String(repeating: "n", count: 18_432)

    var genShift = genMsg
    genShift.location?.datacenter = shiftDC
    genShift.neighbors[0].router = shiftRtr
    let genShiftBytes = genShift.marshalOmniBuf()

    var structShift = structMsg
    structShift.location?.datacenter = shiftDC
    structShift.neighbors[0].router = shiftRtr
    let structShiftBytes = try structShift.encodeOmniBuf()

    var pbShift = pbMsg
    pbShift.location.datacenter = shiftDC
    pbShift.neighbors[0].router = shiftRtr
    let pbShiftData = try pbShift.serializedData()
    let jsonShiftData = try jsonEncoder.encode(structShift)
    precondition(genShiftBytes == structShiftBytes)

    // Category 6: Embedded Message Growth (32 neighbors trailing location -> >16 KiB growth)
    var routingGen = genMsg
    routingGen.neighbors = (0..<8).flatMap { _ in genMsg.neighbors }
    let routingOmniBuf = routingGen.marshalOmniBuf()

    var routingPB = pbMsg
    routingPB.neighbors = (0..<8).flatMap { _ in pbMsg.neighbors }
    let routingPBData = try routingPB.serializedData()

    var routingStruct = structMsg
    routingStruct.neighbors = (0..<8).flatMap { _ in structMsg.neighbors }
    let routingJSONData = try jsonEncoder.encode(routingStruct)

    let grownDC = String(repeating: "d", count: 20_480)

    let runtime = detectRuntime()
    #if os(macOS)
    let platform = "darwin"
    #elseif os(Linux)
    let platform = "linux"
    #else
    let platform = "unknown"
    #endif
    #if arch(arm64)
    let arch = "arm64"
    #elseif arch(x86_64)
    let arch = "amd64"
    #else
    let arch = "unknown"
    #endif
    let cpu = detectCPU()

    print("OmniBuf Swift Benchmark Suite")
    print("Runtime: \(runtime) | Platform: \(platform)/\(arch) | CPU: \(cpu)")

    // 1. Full Message Encode Speed
    let encodeResults = [
        measure(name: "OmniBuf (Generated)", wireBytes: omnibufBytes.count, highlight: true, baseline: true) {
            blackBox(genMsg.marshalOmniBuf())
        },
        measure(name: "OmniBuf (Struct Schema)", wireBytes: structBytes.count, highlight: true) {
            blackBox(try! structMsg.encodeOmniBuf())
        },
        measure(name: "SwiftProtobuf", wireBytes: pbData.count) {
            blackBox(try! pbMsg.serializedData())
        },
        measure(name: "JSONEncoder", wireBytes: jsonData.count) {
            blackBox(try! jsonEncoder.encode(structMsg))
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    // 2. Full Message Decode Speed
    let decodeResults = [
        measure(name: "OmniBuf (Generated)", highlight: true, baseline: true) {
            let m = try! PeerUpdate.decoded(from: omnibufBytes)
            blackBox(m.sequence)
        },
        measure(name: "OmniBuf (Struct Schema)", highlight: true) {
            let m = try! BenchPeerUpdate.decoded(from: structBytes)
            blackBox(m.sequence)
        },
        measure(name: "SwiftProtobuf") {
            let m = try! BenchPBPeerUpdate(serializedBytes: pbData)
            blackBox(m.sequence)
        },
        measure(name: "JSONDecoder") {
            let m = try! jsonDecoder.decode(BenchPeerUpdate.self, from: jsonData)
            blackBox(m.sequence)
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    // 3. Read a Single Nested Field
    let lookupResults = [
        measure(name: "OmniBuf (Generated)", highlight: true, baseline: true) {
            let city = OpaquePeerUpdate(omnibufBytes).getLocation().getCity()
            precondition(city == "Frankfurt")
            blackBox(city)
        },
        measure(name: "SwiftProtobuf") {
            let m = try! BenchPBPeerUpdate(serializedBytes: pbData)
            precondition(m.location.city == "Frankfurt")
            blackBox(m.location.city)
        },
        measure(name: "JSONDecoder") {
            let m = try! jsonDecoder.decode(BenchPeerUpdate.self, from: jsonData)
            precondition(m.location?.city == "Frankfurt")
            blackBox(m.location?.city)
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    // 4. Selective Single-Field Mutation
    let mutateResults = [
        measure(name: "OmniBuf (Generated)", highlight: true, baseline: true) {
            var view = OpaquePeerUpdate(omnibufBytes)
            precondition(view.getLocation().getCity() == "Frankfurt")
            view.setSequence(view.getSequence() &+ 1)
            blackBox(view.marshal())
        },
        measure(name: "SwiftProtobuf") {
            var m = try! BenchPBPeerUpdate(serializedBytes: pbData)
            precondition(m.location.city == "Frankfurt")
            m.sequence &+= 1
            blackBox(try! m.serializedData())
        },
        measure(name: "JSONEncoder / JSONDecoder") {
            var m = try! jsonDecoder.decode(BenchPeerUpdate.self, from: jsonData)
            precondition(m.location?.city == "Frankfurt")
            m.sequence &+= 1
            blackBox(try! jsonEncoder.encode(m))
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    // 5. Large Embedded Message Encode
    let encodeShiftResults = [
        measure(name: "OmniBuf (Generated)", wireBytes: genShiftBytes.count, highlight: true, baseline: true) {
            blackBox(genShift.marshalOmniBuf())
        },
        measure(name: "OmniBuf (Struct Schema)", wireBytes: structShiftBytes.count, highlight: true) {
            blackBox(try! structShift.encodeOmniBuf())
        },
        measure(name: "SwiftProtobuf", wireBytes: pbShiftData.count) {
            blackBox(try! pbShift.serializedData())
        },
        measure(name: "JSONEncoder", wireBytes: jsonShiftData.count) {
            blackBox(try! jsonEncoder.encode(structShift))
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    // 6. Embedded Message Growth
    let mutateGrowResults = [
        measure(name: "OmniBuf (Generated)", highlight: true, baseline: true) {
            var view = OpaquePeerUpdate(routingOmniBuf)
            let lv = view.getLocation()
            view.setLocation(Location(
                region: lv.getRegion(),
                datacenter: grownDC,
                city: lv.getCity(),
                rack: lv.getRack(),
                latitude: lv.getLatitude(),
                longitude: lv.getLongitude()
            ))
            blackBox(view.marshal())
        },
        measure(name: "SwiftProtobuf") {
            var m = try! BenchPBPeerUpdate(serializedBytes: routingPBData)
            m.location.datacenter = grownDC
            blackBox(try! m.serializedData())
        },
        measure(name: "JSONEncoder / JSONDecoder") {
            var m = try! jsonDecoder.decode(BenchPeerUpdate.self, from: routingJSONData)
            m.location?.datacenter = grownDC
            blackBox(try! jsonEncoder.encode(m))
        },
    ].sorted { $0.nsPerOp < $1.nsPerOp }

    let categories = [
        BenchmarkCategory(id: "encode", title: "Full Message Encode Speed", unit: "ns", results: encodeResults),
        BenchmarkCategory(id: "decode", title: "Full Message Decode Speed", unit: "ns", results: decodeResults),
        BenchmarkCategory(id: "lookup_city", title: "Read a Single Nested Field", unit: "ns", results: lookupResults),
        BenchmarkCategory(id: "mutate_sequence", title: "Selective Single-Field Mutation", unit: "ns", results: mutateResults),
        BenchmarkCategory(id: "encode_nested_shift", title: "Large Embedded Message Encode", unit: "ns", results: encodeShiftResults),
        BenchmarkCategory(id: "mutate_embedded_grow", title: "Embedded Message Growth", unit: "ns", results: mutateGrowResults),
    ]

    for cat in categories {
        printCategory(cat)
    }

    let report = BenchmarkReport(
        language: "swift",
        runtime: runtime,
        platform: platform,
        arch: arch,
        cpu: cpu,
        workload: "PeerUpdate",
        categories: categories
    )

    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("testdata")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let outFile = outDir.appendingPathComponent("benchmarks.json")
    let reportEnc = JSONEncoder()
    reportEnc.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try reportEnc.encode(report)
    data.append(0x0A)
    try data.write(to: outFile)
    print("\nWrote benchmark report to \(outFile.path)")
}

try runBenchmarks()
