import Foundation
import OmniBuf
import OmniBufCodeGen
import OmniBufProtobuf
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import Testing

// MARK: - Tier 2 SwiftProtobuf Editions 2026 Reference Types

private enum PBE26Status: SwiftProtobuf.Enum, Equatable, Hashable, Sendable {
    typealias RawValue = Int
    case unspecified
    case active
    case UNRECOGNIZED(Int)

    init() { self = .unspecified }

    init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .active
        default: self = .UNRECOGNIZED(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .unspecified: return 0
        case .active: return 1
        case .UNRECOGNIZED(let v): return v
        }
    }
}

private struct PBE26Child: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable {
    static let protoMessageName: String = "test.e26.E26Child"

    var _id: Int32? = nil
    var _label: String? = nil
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    init(id: Int32? = nil, label: String? = nil) {
        self._id = id
        self._label = label
    }

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt32Field(value: &self._id)
            case 2: try decoder.decodeSingularStringField(value: &self._label)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if let v = self._id { try visitor.visitSingularInt32Field(value: v, fieldNumber: 1) }
        if let v = self._label { try visitor.visitSingularStringField(value: v, fieldNumber: 2) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBE26Child, rhs: PBE26Child) -> Bool {
        lhs._id == rhs._id && lhs._label == rhs._label && lhs.unknownFields == rhs.unknownFields
    }
}

private struct PBE26Payload: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, @unchecked Sendable, Equatable {
    static let protoMessageName: String = "test.e26.E26Payload"

    enum OneOf_Choice: Equatable, Sendable {
        case code(Int32)
        case flag(Bool)
        case text(String)
        case delimitedBranch(PBE26Child)
    }

    var _count: Int32? = nil
    var _enabled: Bool? = nil
    var _name: String? = nil
    var _raw: Data? = nil
    var _ratio: Double? = nil
    var _status: PBE26Status? = nil
    var implicitTag: String = ""
    var _delimitedChild: PBE26Child? = nil
    var delimitedList: [PBE26Child] = []
    var packedNums: [Int32] = []
    var expandedNums: [Int32] = []
    var scores: [String: Int32] = [:]
    var childrenByKey: [String: PBE26Child] = [:]
    var choice: OneOf_Choice? = nil
    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt32Field(value: &self._count)
            case 2: try decoder.decodeSingularBoolField(value: &self._enabled)
            case 3: try decoder.decodeSingularStringField(value: &self._name)
            case 4: try decoder.decodeSingularBytesField(value: &self._raw)
            case 5: try decoder.decodeSingularDoubleField(value: &self._ratio)
            case 6: try decoder.decodeSingularEnumField(value: &self._status)
            case 7: try decoder.decodeSingularStringField(value: &self.implicitTag)
            case 8: try decoder.decodeSingularGroupField(value: &self._delimitedChild)
            case 9: try decoder.decodeRepeatedGroupField(value: &self.delimitedList)
            case 10: try decoder.decodeRepeatedInt32Field(value: &self.packedNums)
            case 11: try decoder.decodeRepeatedInt32Field(value: &self.expandedNums)
            case 12:
                try decoder.decodeMapField(
                    fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufInt32>.self,
                    value: &self.scores
                )
            case 13:
                try decoder.decodeMapField(
                    fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufString, PBE26Child>.self,
                    value: &self.childrenByKey
                )
            case 14:
                var v: Int32?
                try decoder.decodeSingularInt32Field(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .code(v)
                }
            case 15:
                var v: Bool?
                try decoder.decodeSingularBoolField(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .flag(v)
                }
            case 16:
                var v: String?
                try decoder.decodeSingularStringField(value: &v)
                if let v = v {
                    if self.choice != nil { try decoder.handleConflictingOneOf() }
                    self.choice = .text(v)
                }
            case 17:
                var v: PBE26Child?
                var hadOneofValue = false
                if let current = self.choice {
                    hadOneofValue = true
                    if case .delimitedBranch(let m) = current { v = m }
                }
                try decoder.decodeSingularGroupField(value: &v)
                if let v = v {
                    if hadOneofValue { try decoder.handleConflictingOneOf() }
                    self.choice = .delimitedBranch(v)
                }
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if let v = self._count { try visitor.visitSingularInt32Field(value: v, fieldNumber: 1) }
        if let v = self._enabled { try visitor.visitSingularBoolField(value: v, fieldNumber: 2) }
        if let v = self._name { try visitor.visitSingularStringField(value: v, fieldNumber: 3) }
        if let v = self._raw { try visitor.visitSingularBytesField(value: v, fieldNumber: 4) }
        if let v = self._ratio { try visitor.visitSingularDoubleField(value: v, fieldNumber: 5) }
        if let v = self._status { try visitor.visitSingularEnumField(value: v, fieldNumber: 6) }
        if !self.implicitTag.isEmpty { try visitor.visitSingularStringField(value: self.implicitTag, fieldNumber: 7) }
        if let v = self._delimitedChild { try visitor.visitSingularGroupField(value: v, fieldNumber: 8) }
        if !self.delimitedList.isEmpty { try visitor.visitRepeatedGroupField(value: self.delimitedList, fieldNumber: 9) }
        if !self.packedNums.isEmpty { try visitor.visitPackedInt32Field(value: self.packedNums, fieldNumber: 10) }
        if !self.expandedNums.isEmpty { try visitor.visitRepeatedInt32Field(value: self.expandedNums, fieldNumber: 11) }
        if !self.scores.isEmpty {
            try visitor.visitMapField(
                fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString, SwiftProtobuf.ProtobufInt32>.self,
                value: self.scores,
                fieldNumber: 12
            )
        }
        if !self.childrenByKey.isEmpty {
            try visitor.visitMapField(
                fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufString, PBE26Child>.self,
                value: self.childrenByKey,
                fieldNumber: 13
            )
        }
        switch self.choice {
        case .code(let v)?: try visitor.visitSingularInt32Field(value: v, fieldNumber: 14)
        case .flag(let v)?: try visitor.visitSingularBoolField(value: v, fieldNumber: 15)
        case .text(let v)?: try visitor.visitSingularStringField(value: v, fieldNumber: 16)
        case .delimitedBranch(let v)?: try visitor.visitSingularGroupField(value: v, fieldNumber: 17)
        case nil: break
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: PBE26Payload, rhs: PBE26Payload) -> Bool {
        lhs._count == rhs._count
            && lhs._enabled == rhs._enabled
            && lhs._name == rhs._name
            && lhs._raw == rhs._raw
            && lhs._ratio == rhs._ratio
            && lhs._status == rhs._status
            && lhs.implicitTag == rhs.implicitTag
            && lhs._delimitedChild == rhs._delimitedChild
            && lhs.delimitedList == rhs.delimitedList
            && lhs.packedNums == rhs.packedNums
            && lhs.expandedNums == rhs.expandedNums
            && lhs.scores == rhs.scores
            && lhs.childrenByKey == rhs.childrenByKey
            && lhs.choice == rhs.choice
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - Test Harness Helpers

private struct ToolFailure: Error, CustomStringConvertible {
    let description: String
}

private enum EditionsTestHarness {
    static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static func findExecutable(_ name: String) -> String? {
        var searchDirs: [String] = []
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchDirs.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        searchDirs.append(contentsOf: [
            "\(home)/.local/share/mise/shims",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ])
        for dir in searchDirs {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func findBuiltPlugin() -> URL? {
        let fm = FileManager.default
        let candidates = [
            repoRoot.appendingPathComponent(".build/debug/protoc-gen-omnibuf-swift"),
            repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/protoc-gen-omnibuf-swift"),
            repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/protoc-gen-omnibuf-swift"),
            repoRoot.appendingPathComponent(".build/aarch64-unknown-linux-gnu/debug/protoc-gen-omnibuf-swift"),
            repoRoot.appendingPathComponent(".build/release/protoc-gen-omnibuf-swift"),
        ]
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    static func run(
        _ executable: String,
        args: [String],
        cwd: URL? = nil
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let tmpOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnibuf-out-\(UUID().uuidString)")
        let tmpErr = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnibuf-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmpOut.path, contents: nil)
        FileManager.default.createFile(atPath: tmpErr.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: tmpOut)
            try? FileManager.default.removeItem(at: tmpErr)
        }

        let outHandle = try FileHandle(forWritingTo: tmpOut)
        let errHandle = try FileHandle(forWritingTo: tmpErr)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        if let cwd = cwd {
            proc.currentDirectoryURL = cwd
        }
        proc.standardOutput = outHandle
        proc.standardError = errHandle
        try proc.run()
        proc.waitUntilExit()
        try outHandle.close()
        try errHandle.close()

        let stdout = (try? String(contentsOf: tmpOut, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: tmpErr, encoding: .utf8)) ?? ""
        return (proc.terminationStatus, stdout, stderr)
    }

    static func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnibuf-editions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    static func compileProtosToDescriptorSet(
        protos: [String: String],
        targets: [String],
        in dir: URL
    ) throws -> DescriptorSet {
        guard let protoc = findExecutable("protoc") else {
            throw ToolFailure(description: "protoc not found in PATH")
        }
        for (relPath, content) in protos {
            let fileURL = dir.appendingPathComponent(relPath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        let descOut = dir.appendingPathComponent("descriptor_set.pb")
        var args = [
            "-I", dir.path,
            "--include_imports",
            "--descriptor_set_out=\(descOut.path)",
        ]
        args.append(contentsOf: targets.map { dir.appendingPathComponent($0).path })
        let res = try run(protoc, args: args)
        guard res.exitCode == 0 else {
            throw ToolFailure(description: "protoc failed (exit \(res.exitCode)):\n\(res.stderr)")
        }
        let data = try Data(contentsOf: descOut)
        let fds = try Google_Protobuf_FileDescriptorSet(serializedBytes: data)
        return DescriptorSet(proto: fds)
    }

    static func compileAndRunGeneratedSwift(
        generatedFiles: [(fileName: String, contents: String)],
        driverSource: String,
        in dir: URL
    ) throws {
        guard let swiftc = findExecutable("swiftc") else {
            throw ToolFailure(description: "swiftc not found in PATH")
        }
        let omniBufDir = repoRoot.appendingPathComponent("Sources/OmniBuf")
        let omniBufSources = try FileManager.default
            .contentsOfDirectory(at: omniBufDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(\.path)

        let libOut = dir.appendingPathComponent("libOmniBuf.a")
        let modOut = dir.appendingPathComponent("OmniBuf.swiftmodule")
        var libArgs = [
            "-swift-version", "6",
            "-emit-library", "-static",
            "-emit-module",
            "-emit-module-path", modOut.path,
            "-module-name", "OmniBuf",
            "-parse-as-library",
            "-o", libOut.path,
        ]
        libArgs.append(contentsOf: omniBufSources)
        let libRes = try run(swiftc, args: libArgs)
        guard libRes.exitCode == 0 else {
            throw ToolFailure(description: "swiftc OmniBuf build failed:\n\(libRes.stderr)")
        }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        var appSources: [String] = []
        for (i, file) in generatedFiles.enumerated() {
            let safeName = "gen_\(i)_\(URL(fileURLWithPath: file.fileName).lastPathComponent)"
            let outURL = appDir.appendingPathComponent(safeName)
            try file.contents.write(to: outURL, atomically: true, encoding: .utf8)
            appSources.append(outURL.path)
        }
        let mainURL = appDir.appendingPathComponent("main.swift")
        try driverSource.write(to: mainURL, atomically: true, encoding: .utf8)
        appSources.append(mainURL.path)

        let driverBin = dir.appendingPathComponent("editions_driver")
        var appArgs = [
            "-swift-version", "6",
            "-warnings-as-errors",
            "-I", dir.path,
            "-L", dir.path,
            "-lOmniBuf",
            "-o", driverBin.path,
        ]
        appArgs.append(contentsOf: appSources)
        let appRes = try run(swiftc, args: appArgs)
        guard appRes.exitCode == 0 else {
            throw ToolFailure(description: "swiftc generated code failed:\n\(appRes.stderr)")
        }

        let runRes = try run(driverBin.path, args: [])
        guard runRes.exitCode == 0 else {
            throw ToolFailure(
                description: "editions_driver failed (exit \(runRes.exitCode)):\nstdout:\n\(runRes.stdout)\nstderr:\n\(runRes.stderr)"
            )
        }
    }

    static func swiftByteArrayLiteral(_ bytes: [UInt8]) -> String {
        "[" + bytes.map { String($0) }.joined(separator: ", ") + "]"
    }
}

// MARK: - Editions 2023, 2024, and 2026 Test Suite

@Suite("Protobuf Editions 2023/2024/2026 Support Tests")
struct EditionsTests {
    @Test("Generator advertises Editions 2023..2026 support")
    func testSupportedEditionMetadata() {
        #expect(OmniBufCodeGenerator.supportedFeatures == [.supportsEditions])
        #expect(OmniBufCodeGenerator.supportedEditionRange == .edition2023 ... .edition2026)
    }

    @Test("Edition 2023 E2E: protoc + plugin + swiftc compile and run (presence, overrides, oneof, DELIMITED, open enum, Opaque)")
    func testEdition2023EndToEnd() throws {
        let protoSource = """
            edition = "2023";
            package test.e23;

            option features.json_format = ALLOW;

            enum Status {
              option allow_alias = true;
              STATUS_UNSPECIFIED = 0;
              STATUS_OK = 1;
              STATUS_GOOD = 1;
            }

            message Child {
              int32 id = 1 [default = 0];
              string note = 2 [default = ""];
            }

            message RecursiveOneof {
              oneof node {
                int32 leaf = 1;
                RecursiveOneof branch = 2;
              }
            }

            message E23AllFeatures {
              int32 f_int32 = 1 [default = 0];
              int64 f_int64 = 2;
              uint32 f_uint32 = 3;
              uint64 f_uint64 = 4;
              sint32 f_sint32 = 5;
              sint64 f_sint64 = 6;
              fixed32 f_fixed32 = 7;
              fixed64 f_fixed64 = 8;
              sfixed32 f_sfixed32 = 9;
              sfixed64 f_sfixed64 = 10;
              float f_float = 11 [default = 0.0];
              double f_double = 12;
              bool f_bool = 13 [default = false];
              string f_string = 14 [default = ""];
              bytes f_bytes = 15;
              Status f_status = 16 [default = STATUS_UNSPECIFIED];

              Child regular_child = 17;
              Child delimited_child = 18 [features.message_encoding = DELIMITED];
              repeated Child delimited_list = 19 [features.message_encoding = DELIMITED];

              repeated int32 packed_ints = 20 [features.repeated_field_encoding = PACKED];
              repeated int32 expanded_ints = 21 [features.repeated_field_encoding = EXPANDED];
              repeated string tags = 22;
              repeated Status statuses = 23;

              map<string, int32> scores = 24;
              map<string, Child> child_map = 25;
              map<int32, Status> status_map = 26;

              oneof payload {
                int32 p_int = 30;
                bool p_bool = 31;
                string p_str = 32;
                bytes p_bytes = 33;
                Status p_status = 34;
                Child p_child = 35;
                Child p_delimited = 36 [features.message_encoding = DELIMITED];
              }

              oneof high_choice {
                int32 hi_num = 70;
                string hi_str = 71;
              }

              int32 high_explicit = 80;
            }
            """

        let implicitProtoSource = """
            edition = "2023";
            package test.e23imp;

            option features.field_presence = IMPLICIT;

            message ImplicitContainer {
              int32 imp_num = 1;
              string imp_text = 2;
              bool imp_flag = 3;
              int32 explicit_override = 4 [features.field_presence = EXPLICIT];
              string explicit_str = 5 [features.field_presence = EXPLICIT];

              message ExplicitNested {
                int32 val = 1 [features.field_presence = EXPLICIT];
                bool active = 2 [features.field_presence = EXPLICIT];
              }
              ExplicitNested nested = 6;
            }
            """

        try EditionsTestHarness.withTempDir { dir in
            let descriptorSet = try EditionsTestHarness.compileProtosToDescriptorSet(
                protos: [
                    "e23.proto": protoSource,
                    "e23_implicit.proto": implicitProtoSource,
                ],
                targets: ["e23.proto", "e23_implicit.proto"],
                in: dir
            )
            let targetFiles = descriptorSet.files.filter { $0.name == "e23.proto" || $0.name == "e23_implicit.proto" }
            let generator = OmniBufCodeGenerator()
            let generated = try generator.generate(files: targetFiles)
            #expect(generated.count == 2)

            // Also verify real protoc --plugin invocation produces byte-identical Swift source
            if let plugin = EditionsTestHarness.findBuiltPlugin(),
               let protoc = EditionsTestHarness.findExecutable("protoc") {
                let pluginOut = dir.appendingPathComponent("plugin_out")
                try FileManager.default.createDirectory(at: pluginOut, withIntermediateDirectories: true)
                let res = try EditionsTestHarness.run(protoc, args: [
                    "--plugin=protoc-gen-omnibuf-swift=\(plugin.path)",
                    "--omnibuf-swift_out=\(pluginOut.path)",
                    "-I", dir.path,
                    dir.appendingPathComponent("e23.proto").path,
                ])
                #expect(res.exitCode == 0, "protoc plugin failed: \(res.stderr)")
                let pluginSwift = try String(
                    contentsOf: pluginOut.appendingPathComponent("e23.omnibuf.swift"),
                    encoding: .utf8
                )
                let e23Gen = try #require(generated.first { $0.fileName == "e23.omnibuf.swift" })
                #expect(pluginSwift == e23Gen.contents)
            }

            let driver = """
                import Foundation
                import OmniBuf

                func check(_ cond: Bool, _ msg: String, line: UInt = #line) {
                    if !cond {
                        FileHandle.standardError.write(Data("FAIL line \\(line): \\(msg)\\n".utf8))
                        exit(1)
                    }
                }

                // 1. Default absent message encodes to 0 bytes
                let absent = E23AllFeatures()
                let absentBytes = try absent.encodeOmniBuf()
                check(absentBytes.isEmpty, "absent Editions message must encode to empty bytes")
                let absentDecoded = try E23AllFeatures.decoded(from: absentBytes)
                check(absentDecoded == absent, "absent round-trip mismatch")
                check(absentDecoded.fInt32 == nil && absentDecoded.fBool == nil && absentDecoded.fString == nil && absentDecoded.fBytes == nil && absentDecoded.fStatus == nil, "absent fields must decode as nil")

                // 2. Explicit zero / false / empty / enum(0) values emit wire bytes and preserve presence
                var explicitZero = E23AllFeatures()
                explicitZero.fInt32 = 0
                explicitZero.fInt64 = 0
                explicitZero.fUint32 = 0
                explicitZero.fUint64 = 0
                explicitZero.fSint32 = 0
                explicitZero.fSint64 = 0
                explicitZero.fFixed32 = 0
                explicitZero.fFixed64 = 0
                explicitZero.fSfixed32 = 0
                explicitZero.fSfixed64 = 0
                explicitZero.fFloat = 0.0
                explicitZero.fDouble = 0.0
                explicitZero.fBool = false
                explicitZero.fString = ""
                explicitZero.fBytes = []
                explicitZero.fStatus = .statusUnspecified
                explicitZero.highExplicit = 0

                let zeroBytes = try explicitZero.encodeOmniBuf()
                check(!zeroBytes.isEmpty, "explicit zero message must emit non-empty wire bytes")
                check(zeroBytes != absentBytes, "explicit zero wire bytes must differ from absent")

                let zeroDecoded = try E23AllFeatures.decoded(from: zeroBytes)
                check(zeroDecoded == explicitZero, "explicit zero round-trip mismatch")
                check(zeroDecoded.fInt32 == 0, "fInt32 must be Optional(0)")
                check(zeroDecoded.fFloat == 0.0, "fFloat must be Optional(0.0)")
                check(zeroDecoded.fDouble == 0.0, "fDouble must be Optional(0.0)")
                check(zeroDecoded.fBool == false, "fBool must be Optional(false)")
                check(zeroDecoded.fString == "", "fString must be Optional(\\\"\\\")")
                check(zeroDecoded.fBytes == [], "fBytes must be Optional([])")
                check(zeroDecoded.fStatus == .statusUnspecified, "fStatus must be Optional(.statusUnspecified)")
                check(zeroDecoded.highExplicit == 0, "highExplicit must be Optional(0)")

                // Merge semantics: omitted field keeps old value; explicit zero overwrites old value
                var mergeTarget = E23AllFeatures(fInt32: 42, fBool: true, fString: "keep")
                try mergeTarget.mergeOmniBuf(from: try E23AllFeatures(fInt32: 0, fBool: false).encodeOmniBuf())
                check(mergeTarget.fInt32 == 0, "merge explicit 0 must overwrite 42")
                check(mergeTarget.fBool == false, "merge explicit false must overwrite true")
                check(mergeTarget.fString == "keep", "merge omitted string must preserve existing value")

                // 3. Inherited IMPLICIT -> EXPLICIT feature overrides
                let impEmpty = ImplicitContainer(impNum: 0, impText: "", impFlag: false, explicitOverride: nil, explicitStr: nil, nested: nil)
                check((try impEmpty.encodeOmniBuf()).isEmpty, "implicit zero fields must omit on wire")
                let impWithExplicit = ImplicitContainer(
                    impNum: 0,
                    impText: "",
                    impFlag: false,
                    explicitOverride: 0,
                    explicitStr: "",
                    nested: ImplicitContainer_ExplicitNested(val: 0, active: false)
                )
                let impBytes = try impWithExplicit.encodeOmniBuf()
                check(!impBytes.isEmpty, "explicit overrides inside implicit message must encode")
                let impDecoded = try ImplicitContainer.decoded(from: impBytes)
                check(impDecoded == impWithExplicit, "ImplicitContainer round-trip mismatch")
                check(impDecoded.explicitOverride == 0 && impDecoded.explicitStr == "", "field EXPLICIT overrides must round-trip")
                check(impDecoded.nested?.val == 0 && impDecoded.nested?.active == false, "nested EXPLICIT message must round-trip")

                // 4. Open enums (alias + unknown values round-trip via UNRECOGNIZED)
                check(Status.statusGood == .statusOk, "enum alias must match canonical case")
                var enumMsg = E23AllFeatures(
                    fStatus: .UNRECOGNIZED(99),
                    statuses: [.statusUnspecified, .statusOk, .UNRECOGNIZED(-7)],
                    statusMap: [1: .UNRECOGNIZED(42)]
                )
                let enumBytes = try enumMsg.encodeOmniBuf()
                let enumDecoded = try E23AllFeatures.decoded(from: enumBytes)
                check(enumDecoded == enumMsg, "open enum UNRECOGNIZED round-trip failed")
                check(enumDecoded.fStatus == .UNRECOGNIZED(99), "singular UNRECOGNIZED(99) mismatch")
                let opEnum = OpaqueE23AllFeatures(enumBytes)
                check(opEnum.getFStatus() == .UNRECOGNIZED(99), "Opaque open enum UNRECOGNIZED(99) mismatch")

                // 5. Repeated (PACKED & EXPANDED), Maps, DELIMITED singular & repeated, SchemaMeta
                var full = E23AllFeatures()
                full.regularChild = Child(id: 1, note: "reg")
                full.delimitedChild = Child(id: 0, note: "")
                full.delimitedList = [Child(id: 10, note: "a"), Child(id: 20, note: "b")]
                full.packedInts = [1, -2, 3]
                full.expandedInts = [4, -5, 6]
                full.tags = ["x", "y"]
                full.scores = ["alpha": 1, "beta": -2]
                full.childMap = ["k1": Child(id: 7, note: "mapped")]
                full.payload = .pDelimited(Child(id: 99, note: "oneof-delim"))
                let fullBytes = try full.encodeOmniBuf()
                let fullDecoded = try E23AllFeatures.decoded(from: fullBytes)
                check(fullDecoded == full, "full Editions 2023 message round-trip failed")
                let meta = E23AllFeatures.omniBufSchemaMeta
                check(meta.children[18]?.typeName == "Child", "DELIMITED singular child missing from SchemaMeta")
                check(meta.children[19]?.typeName == "Child", "DELIMITED repeated child missing from SchemaMeta")
                check(meta.children[36]?.typeName == "Child", "DELIMITED oneof child missing from SchemaMeta")

                // 6. Oneof: zero/false/empty/enum(0)/UNRECOGNIZED + branch switching + message merge + cyclic Indirect
                let oneofZeroCases: [E23AllFeatures.OneOf_Payload] = [
                    .pInt(0),
                    .pBool(false),
                    .pStr(""),
                    .pBytes([]),
                    .pStatus(.statusUnspecified),
                    .pStatus(.UNRECOGNIZED(77)),
                    .pChild(Child()),
                    .pDelimited(Child(id: 0, note: "")),
                ]
                for c in oneofZeroCases {
                    let m = E23AllFeatures(payload: c)
                    let b = try m.encodeOmniBuf()
                    check(!b.isEmpty, "active oneof branch must emit non-empty bytes: \\(c)")
                    let dec = try E23AllFeatures.decoded(from: b)
                    check(dec.payload == c, "oneof branch round-trip failed for \\(c)")
                }

                // Concatenated wire bytes with branch A then branch B: last wins
                let branchA = try E23AllFeatures(payload: .pInt(123)).encodeOmniBuf()
                let branchB = try E23AllFeatures(payload: .pBool(false)).encodeOmniBuf()
                let switched = try E23AllFeatures.decoded(from: branchA + branchB)
                check(switched.payload == .pBool(false), "oneof last branch must win on decode")

                // Same-branch message merge vs intervening different branch reset
                let msgPart1 = try E23AllFeatures(payload: .pChild(Child(id: 11, note: nil))).encodeOmniBuf()
                let msgPart2 = try E23AllFeatures(payload: .pChild(Child(id: nil, note: "merged"))).encodeOmniBuf()
                let mergedOneof = try E23AllFeatures.decoded(from: msgPart1 + msgPart2)
                check(mergedOneof.payload == .pChild(Child(id: 11, note: "merged")), "same-branch oneof message must merge")
                let resetOneof = try E23AllFeatures.decoded(from: msgPart1 + branchA + msgPart2)
                check(resetOneof.payload == .pChild(Child(id: nil, note: "merged")), "intervening oneof branch must reset message")

                // Cyclic oneof (Indirect)
                let tree = RecursiveOneof(node: .branch(Indirect(RecursiveOneof(node: .leaf(42)))))
                let treeDecoded = try RecursiveOneof.decoded(from: try tree.encodeOmniBuf())
                check(treeDecoded == tree, "cyclic oneof Indirect round-trip failed")

                // 7. Opaque* view: absent vs present-zero vs wire-type mismatch + mutations & splicing
                var opAbsent = OpaqueE23AllFeatures(absentBytes)
                check(opAbsent.getFInt32() == nil, "Opaque absent int32 must be nil")
                check(opAbsent.getFBool() == nil, "Opaque absent bool must be nil")
                check(opAbsent.getFString() == nil, "Opaque absent string must be nil")
                check(opAbsent.getFBytes() == nil, "Opaque absent bytes must be nil")
                check(opAbsent.getFStatus() == nil, "Opaque absent enum must be nil")
                check(opAbsent.getPayload() == nil, "Opaque absent oneof must be nil")

                let opZero = OpaqueE23AllFeatures(zeroBytes)
                check(opZero.getFInt32() == 0, "Opaque present-zero int32 must be Optional(0)")
                check(opZero.getFBool() == false, "Opaque present-false bool must be Optional(false)")
                check(opZero.getFString() == "", "Opaque present-empty string must be Optional(\\\"\\\")")
                check(opZero.getFBytes() == [], "Opaque present-empty bytes must be Optional([])")
                check(opZero.getFStatus() == .statusUnspecified, "Opaque present-zero enum must be Optional(.statusUnspecified)")
                check(opZero.getHighExplicit() == 0, "Opaque high field present-zero must be Optional(0)")

                // Mismatched wire type must NOT report present in Opaque view!
                var wrongWT = OmniBufWriter()
                wrongWT.appendTag(fieldNumber: 1, wireType: WireType.wireString)
                wrongWT.appendStringValue("not-an-int")
                wrongWT.appendTag(fieldNumber: 13, wireType: WireType.wireUint)
                wrongWT.appendVarint(1)
                wrongWT.appendTag(fieldNumber: 16, wireType: WireType.wireString)
                wrongWT.appendStringValue("not-an-enum")
                let opWrong = OpaqueE23AllFeatures(wrongWT.toBytes())
                check(opWrong.getFInt32() == nil, "Opaque mismatched wire type on int32 must return nil")
                check(opWrong.getFBool() == nil, "Opaque mismatched wire type on bool must return nil")
                check(opWrong.getFStatus() == nil, "Opaque mismatched wire type on enum must return nil")

                // Opaque mutations: absent -> explicit zero/false/empty, present -> nil
                opAbsent.setFInt32(0)
                opAbsent.setFBool(false)
                opAbsent.setFString("")
                opAbsent.setFBytes([])
                opAbsent.setHighExplicit(0)
                let mutatedToZero = try opAbsent.tryMarshal()
                let decodedMutZero = try E23AllFeatures.decoded(from: mutatedToZero)
                check(decodedMutZero.fInt32 == 0 && decodedMutZero.fBool == false && decodedMutZero.fString == "" && decodedMutZero.fBytes == [] && decodedMutZero.highExplicit == 0, "Opaque set explicit zero/false/empty failed")

                var opClear = OpaqueE23AllFeatures(zeroBytes)
                opClear.setFInt32(nil)
                opClear.setFBool(nil)
                opClear.setFString(nil)
                opClear.setHighExplicit(nil)
                let clearedDecoded = try E23AllFeatures.decoded(from: try opClear.tryMarshal())
                check(clearedDecoded.fInt32 == nil && clearedDecoded.fBool == nil && clearedDecoded.fString == nil && clearedDecoded.highExplicit == nil, "Opaque clear to nil failed")
                check(clearedDecoded.fInt64 == 0 && clearedDecoded.fBytes == [], "Opaque untouched fields must remain intact")

                // Opaque oneof: multi-branch read (last wins), switching, clearing, DELIMITED subview, high fields
                let opMulti = OpaqueE23AllFeatures(branchA + branchB)
                check(opMulti.getPayload() == .pBool(false), "Opaque oneof last-winning branch failed")
                check(opMulti.getPBool() == false && opMulti.getPInt() == nil, "Opaque oneof per-branch getter failed")

                var opSwitch = OpaqueE23AllFeatures(fullBytes)
                check(opSwitch.getDelimitedChild().getId() == 0 && opSwitch.getDelimitedChild().getNote() == "", "Opaque DELIMITED child zero-copy view failed")
                check(opSwitch.getPDelimited()?.getId() == 99, "Opaque oneof DELIMITED branch getter failed")
                opSwitch.setPInt(0)
                check(opSwitch.getPayload() == .pInt(0) && opSwitch.getPDelimited() == nil, "Opaque dirty oneof switch failed")
                let switchedBytes = try opSwitch.tryMarshal()
                let switchedStruct = try E23AllFeatures.decoded(from: switchedBytes)
                check(switchedStruct.payload == .pInt(0), "Opaque marshaled oneof switch failed")

                var opClearOneof = OpaqueE23AllFeatures(switchedBytes)
                opClearOneof.setPayload(nil)
                let clearedOneofStruct = try E23AllFeatures.decoded(from: try opClearOneof.tryMarshal())
                check(clearedOneofStruct.payload == nil, "Opaque clear oneof to nil failed")

                // High-field oneof (>= 64) switching & clearing via dirtyHigh
                var opHi = OpaqueE23AllFeatures(try E23AllFeatures(highChoice: .hiNum(7)).encodeOmniBuf())
                check(opHi.getHiNum() == 7 && opHi.getHiStr() == nil, "Opaque high oneof read failed")
                opHi.setHiStr("")
                let hiSwitched = try E23AllFeatures.decoded(from: try opHi.tryMarshal())
                check(hiSwitched.highChoice == .hiStr(""), "Opaque high oneof switch to empty string failed")
                var opHiClear = OpaqueE23AllFeatures(try hiSwitched.encodeOmniBuf())
                opHiClear.setHighChoice(nil)
                check((try E23AllFeatures.decoded(from: try opHiClear.tryMarshal())).highChoice == nil, "Opaque high oneof clear failed")

                print("E23_OK")
                """

            try EditionsTestHarness.compileAndRunGeneratedSwift(
                generatedFiles: generated,
                driverSource: driver,
                in: dir
            )
        }
    }

    @Test("Edition 2024 E2E: strict visibility, style, file IMPLICIT + field EXPLICIT overrides")
    func testEdition2024EndToEnd() throws {
        let protoSource = """
            edition = "2024";
            package test.e24;

            option features.enforce_naming_style = STYLE2024;
            option features.default_symbol_visibility = STRICT;
            option features.field_presence = IMPLICIT;
            option features.json_format = LEGACY_BEST_EFFORT;

            export enum Kind {
              KIND_UNSPECIFIED = 0;
              KIND_EVENT = 1;
            }

            local message Detail {
              int32 code = 1 [features.field_presence = EXPLICIT];
              string summary = 2 [features.field_presence = EXPLICIT];
            }

            export message Record {
              int32 id = 1 [features.field_presence = EXPLICIT];
              string implicit_label = 2;
              Detail detail = 3 [features.message_encoding = DELIMITED];
              Kind kind = 4 [features.field_presence = EXPLICIT];
              repeated int32 values = 5 [features.repeated_field_encoding = EXPANDED];
              map<string, int32> counts = 6;

              oneof result {
                bool ok = 7;
                string err_msg = 8;
              }
            }
            """

        try EditionsTestHarness.withTempDir { dir in
            let descriptorSet = try EditionsTestHarness.compileProtosToDescriptorSet(
                protos: ["e24.proto": protoSource],
                targets: ["e24.proto"],
                in: dir
            )
            let generator = OmniBufCodeGenerator()
            let generated = try generator.generate(files: descriptorSet.files.filter { $0.name == "e24.proto" })

            let driver = """
                import Foundation
                import OmniBuf

                func check(_ cond: Bool, _ msg: String, line: UInt = #line) {
                    if !cond {
                        FileHandle.standardError.write(Data("FAIL line \\(line): \\(msg)\\n".utf8))
                        exit(1)
                    }
                }

                let empty = Record()
                check((try empty.encodeOmniBuf()).isEmpty, "empty Record must encode to []")

                var rec = Record(
                    id: 0,
                    implicitLabel: "",
                    detail: Detail(code: 0, summary: ""),
                    kind: .UNRECOGNIZED(55),
                    values: [10, 20, -30],
                    counts: ["a": 1, "b": 2],
                    result: .ok(false)
                )
                let bytes = try rec.encodeOmniBuf()
                let dec = try Record.decoded(from: bytes)
                check(dec == rec, "Edition 2024 Record round-trip failed")
                check(dec.id == 0 && dec.implicitLabel.isEmpty, "EXPLICIT id and IMPLICIT label mismatch")
                check(dec.detail?.code == 0 && dec.detail?.summary == "", "local DELIMITED Detail mismatch")
                check(dec.kind == .UNRECOGNIZED(55), "Edition 2024 open enum UNRECOGNIZED mismatch")
                check(dec.result == .ok(false), "Edition 2024 oneof false mismatch")

                var op = OpaqueRecord(bytes)
                check(op.getId() == 0 && op.getOk() == false && op.getErrMsg() == nil, "OpaqueRecord getters failed")
                op.setErrMsg("")
                let switched = try Record.decoded(from: try op.tryMarshal())
                check(switched.result == .errMsg(""), "OpaqueRecord oneof switch failed")

                print("E24_OK")
                """

            try EditionsTestHarness.compileAndRunGeneratedSwift(
                generatedFiles: generated,
                driverSource: driver,
                in: dir
            )
        }
    }

    @Test("Edition 2026 E2E + Tier 2 OmniBufProtobuf reflection byte-for-byte wire equivalence")
    func testEdition2026AndTier2ReflectionEquivalence() throws {
        let protoSource = """
            edition = "2026";
            package test.e26;

            option features.default_symbol_visibility = STRICT;

            export enum E26Status {
              E26_STATUS_UNSPECIFIED = 0;
              E26_STATUS_ACTIVE = 1;
            }

            export message E26Child {
              option features.enforce_proto_limits = PROTO_LIMITS2026;
              int32 id = 1;
              string label = 2;
            }

            export message E26Payload {
              option features.enforce_proto_limits = PROTO_LIMITS2026;
              int32 count = 1;
              bool enabled = 2;
              string name = 3;
              bytes raw = 4;
              double ratio = 5;
              E26Status status = 6;
              string implicit_tag = 7 [features.field_presence = IMPLICIT];
              E26Child delimited_child = 8 [features.message_encoding = DELIMITED];
              repeated E26Child delimited_list = 9 [features.message_encoding = DELIMITED];
              repeated int32 packed_nums = 10 [features.repeated_field_encoding = PACKED];
              repeated int32 expanded_nums = 11 [features.repeated_field_encoding = EXPANDED];
              map<string, int32> scores = 12;
              map<string, E26Child> children_by_key = 13;

              oneof choice {
                int32 code = 14;
                bool flag = 15;
                string text = 16;
                E26Child delimited_branch = 17 [features.message_encoding = DELIMITED];
              }
            }
            """

        // Build 3 Tier 2 SwiftProtobuf Editions 2026 messages and verify Tier 2 round-trip first!
        let pbEmpty = PBE26Payload()
        let pbEmptyBytes = try OmniBufProtobuf.encode(pbEmpty)
        #expect(pbEmptyBytes.isEmpty)
        #expect(try OmniBufProtobuf.decode(PBE26Payload.self, from: pbEmptyBytes) == pbEmpty)

        var pbZero = PBE26Payload()
        pbZero._count = 0
        pbZero._enabled = false
        pbZero._name = ""
        pbZero._raw = Data()
        pbZero._ratio = 0.0
        pbZero._status = .unspecified
        pbZero.implicitTag = ""
        pbZero.choice = .flag(false)
        let pbZeroBytes = try OmniBufProtobuf.encode(pbZero)
        #expect(!pbZeroBytes.isEmpty)
        let pbZeroDecoded = try OmniBufProtobuf.decode(PBE26Payload.self, from: pbZeroBytes)
        #expect(pbZeroDecoded == pbZero)
        #expect(pbZeroDecoded._count == 0)
        #expect(pbZeroDecoded._enabled == false)
        #expect(pbZeroDecoded._name == "")
        #expect(pbZeroDecoded._raw == Data())
        #expect(pbZeroDecoded._ratio == 0.0)
        #expect(pbZeroDecoded._status == .unspecified)
        #expect(pbZeroDecoded.choice == .flag(false))

        var pbFull = PBE26Payload()
        pbFull._count = -42
        pbFull._enabled = true
        pbFull._name = "edition-2026"
        pbFull._raw = Data([0xDE, 0xAD, 0xBE, 0xEF])
        pbFull._ratio = 3.5
        pbFull._status = .UNRECOGNIZED(77)
        pbFull.implicitTag = "imp-2026"
        pbFull._delimitedChild = PBE26Child(id: 0, label: "")
        pbFull.delimitedList = [PBE26Child(id: 1, label: "first"), PBE26Child(id: 2, label: "second")]
        pbFull.packedNums = [1, -2, 3]
        pbFull.expandedNums = [4, -5, 6]
        pbFull.scores = ["b": 2, "a": 1]
        pbFull.childrenByKey = ["c": PBE26Child(id: 9, label: "mapped")]
        pbFull.choice = .delimitedBranch(PBE26Child(id: 100, label: "branch"))
        let pbFullBytes = try OmniBufProtobuf.encode(pbFull)
        let pbFullDecoded = try OmniBufProtobuf.decode(PBE26Payload.self, from: pbFullBytes)
        #expect(pbFullDecoded == pbFull)
        #expect(pbFullDecoded._status == .UNRECOGNIZED(77))

        // Verify Tier 2 oneof conflict / last-branch-wins on merge
        var pbBranch1 = PBE26Payload()
        pbBranch1.choice = .code(123)
        var pbBranch2 = PBE26Payload()
        pbBranch2.choice = .text("")
        let mergedBytes = try OmniBufProtobuf.encode(pbBranch1) + OmniBufProtobuf.encode(pbBranch2)
        let pbSwitched = try OmniBufProtobuf.decode(PBE26Payload.self, from: mergedBytes)
        #expect(pbSwitched.choice == .text(""))

        // Now generate Tier 1 Swift code from real protoc 36.2 Edition 2026 schema and prove byte-for-byte equivalence!
        try EditionsTestHarness.withTempDir { dir in
            let descriptorSet = try EditionsTestHarness.compileProtosToDescriptorSet(
                protos: ["e26.proto": protoSource],
                targets: ["e26.proto"],
                in: dir
            )
            let generator = OmniBufCodeGenerator()
            let generated = try generator.generate(files: descriptorSet.files.filter { $0.name == "e26.proto" })

            let zeroHex = EditionsTestHarness.swiftByteArrayLiteral(pbZeroBytes)
            let fullHex = EditionsTestHarness.swiftByteArrayLiteral(pbFullBytes)

            let driver = """
                import Foundation
                import OmniBuf

                func check(_ cond: Bool, _ msg: String, line: UInt = #line) {
                    if !cond {
                        FileHandle.standardError.write(Data("FAIL line \\(line): \\(msg)\\n".utf8))
                        exit(1)
                    }
                }

                // 1. Empty equivalence
                let t1Empty = E26Payload()
                check((try t1Empty.encodeOmniBuf()).isEmpty, "Tier 1 Edition 2026 empty must be []")

                // 2. Explicit-zero Tier 1 <-> Tier 2 byte-for-byte equivalence
                let tier2ZeroBytes: [UInt8] = \(zeroHex)
                let t1Zero = E26Payload(
                    count: 0,
                    enabled: false,
                    name: "",
                    raw: [],
                    ratio: 0.0,
                    status: .e26StatusUnspecified,
                    implicitTag: "",
                    choice: .flag(false)
                )
                let t1ZeroBytes = try t1Zero.encodeOmniBuf()
                check(t1ZeroBytes == tier2ZeroBytes, "Tier 1 vs Tier 2 explicit-zero wire bytes diverged")
                check((try E26Payload.decoded(from: tier2ZeroBytes)) == t1Zero, "Tier 1 failed to decode Tier 2 explicit-zero bytes")

                // 3. Full Editions 2026 Tier 1 <-> Tier 2 byte-for-byte equivalence (incl. DELIMITED, open enum, oneof, maps, arrays)
                let tier2FullBytes: [UInt8] = \(fullHex)
                let t1Full = E26Payload(
                    count: -42,
                    enabled: true,
                    name: "edition-2026",
                    raw: [0xDE, 0xAD, 0xBE, 0xEF],
                    ratio: 3.5,
                    status: .UNRECOGNIZED(77),
                    implicitTag: "imp-2026",
                    delimitedChild: E26Child(id: 0, label: ""),
                    delimitedList: [E26Child(id: 1, label: "first"), E26Child(id: 2, label: "second")],
                    packedNums: [1, -2, 3],
                    expandedNums: [4, -5, 6],
                    scores: ["b": 2, "a": 1],
                    childrenByKey: ["c": E26Child(id: 9, label: "mapped")],
                    choice: .delimitedBranch(E26Child(id: 100, label: "branch"))
                )
                let t1FullBytes = try t1Full.encodeOmniBuf()
                check(t1FullBytes == tier2FullBytes, "Tier 1 vs Tier 2 full Edition 2026 wire bytes diverged")
                check((try E26Payload.decoded(from: tier2FullBytes)) == t1Full, "Tier 1 failed to decode Tier 2 full bytes")

                // Verify OpaqueE26Payload on Tier 2 bytes
                var op = OpaqueE26Payload(tier2FullBytes)
                check(op.getCount() == -42 && op.getStatus() == .UNRECOGNIZED(77), "OpaqueE26Payload scalar/enum mismatch")
                check(op.getDelimitedChild().getId() == 0 && op.getDelimitedChild().getLabel() == "", "OpaqueE26Payload DELIMITED child mismatch")
                check(op.delimitedListCount == 2 && op.packedNumsCount == 3 && op.expandedNumsCount == 3, "OpaqueE26Payload repeated counts mismatch")
                check(op.getDelimitedBranch()?.getId() == 100, "OpaqueE26Payload oneof DELIMITED branch mismatch")
                op.setCode(0)
                let mutated = try E26Payload.decoded(from: try op.tryMarshal())
                check(mutated.choice == .code(0), "OpaqueE26Payload switch to code(0) failed")

                print("E26_OK")
                """

            try EditionsTestHarness.compileAndRunGeneratedSwift(
                generatedFiles: generated,
                driverSource: driver,
                in: dir
            )
        }
    }

    @Test("Unsupported editions and forbidden Editions features are rejected consistently")
    func testEditionsRejections() throws {
        let generator = OmniBufCodeGenerator()

        // 1. Unsupported editions (0 / unknown, legacy, unstable, test-only, max, missing edition)
        for badEdition in [
            Google_Protobuf_Edition.unknown,
            Google_Protobuf_Edition.legacy,
            Google_Protobuf_Edition.unstable,
            Google_Protobuf_Edition.edition1TestOnly,
            Google_Protobuf_Edition.edition99999TestOnly,
            Google_Protobuf_Edition.max,
        ] {
            var rawProto = Google_Protobuf_FileDescriptorProto()
            rawProto.name = "bad_edition.proto"
            rawProto.syntax = "editions"
            rawProto.edition = badEdition
            do {
                try generator.validateEditions(rawProto)
                Issue.record("expected rejection for edition \(badEdition)")
            } catch {
                #expect("\(error)".contains("unsupported protobuf edition"))
            }
        }

        // Unknown wire edition number (2099) decoded into FileDescriptorProto (goes into unknownFields, hasEdition == false)
        do {
            // Wire bytes: field 1 (name) = "future.proto", field 12 (syntax) = "editions", field 14 (edition) = 2099
            var wire: [UInt8] = []
            // field 1 (len-delim): 0x0A, 12, "future.proto"
            wire.append(contentsOf: [0x0A, 12])
            wire.append(contentsOf: "future.proto".utf8)
            // field 12 (len-delim): (12 << 3) | 2 = 0x62, 8, "editions"
            wire.append(contentsOf: [0x62, 8])
            wire.append(contentsOf: "editions".utf8)
            // field 14 (varint): (14 << 3) | 0 = 0x70, 2099 = (0xB3, 0x10)
            wire.append(contentsOf: [0x70, 0xB3, 0x10])
            let futureProto = try Google_Protobuf_FileDescriptorProto(serializedBytes: wire)
            try generator.validateEditions(futureProto)
            Issue.record("expected rejection for unknown future edition 2099")
        } catch {
            #expect("\(error)".contains("unsupported protobuf edition"))
        }

        // Missing edition with syntax = "editions"
        do {
            var missingEdition = Google_Protobuf_FileDescriptorProto()
            missingEdition.name = "missing.proto"
            missingEdition.syntax = "editions"
            try generator.validateEditions(missingEdition)
            Issue.record("expected rejection for syntax=editions with missing edition")
        } catch {
            #expect("\(error)".contains("unsupported protobuf edition"))
        }

        // EDITION_UNSTABLE through real DescriptorSet + generate(files:)
        do {
            var unstableProto = Google_Protobuf_FileDescriptorProto()
            unstableProto.name = "unstable.proto"
            unstableProto.syntax = "editions"
            unstableProto.edition = .unstable
            let ds = DescriptorSet(protos: [unstableProto])
            _ = try generator.generate(files: ds.files)
            Issue.record("expected generate(files:) to reject EDITION_UNSTABLE")
        } catch {
            #expect("\(error)".contains("unsupported protobuf edition"))
        }

        // Helper to compile a single real .proto via protoc and assert OmniBufCodeGenerator rejects it
        func assertRejected(
            protos: [String: String],
            target: String,
            expectedSubstring: String,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws {
            try EditionsTestHarness.withTempDir { dir in
                let ds = try EditionsTestHarness.compileProtosToDescriptorSet(
                    protos: protos,
                    targets: [target],
                    in: dir
                )
                let targetFiles = ds.files.filter { $0.name == target }
                #expect(targetFiles.count == 1, sourceLocation: sourceLocation)
                do {
                    _ = try generator.generate(files: targetFiles)
                    Issue.record("expected rejection containing '\(expectedSubstring)' for \(target)", sourceLocation: sourceLocation)
                } catch {
                    #expect(
                        "\(error)".contains(expectedSubstring),
                        "expected '\(expectedSubstring)' in '\(error)'",
                        sourceLocation: sourceLocation
                    )
                }
            }
        }

        // 2. CLOSED enums: file-level, enum-level, nested, and cross-file (field & map value)
        try assertRejected(
            protos: [
                "closed_file.proto": """
                edition = "2023";
                package neg;
                option features.enum_type = CLOSED;
                enum E { E_ZERO = 0; }
                """,
            ],
            target: "closed_file.proto",
            expectedSubstring: "CLOSED"
        )
        try assertRejected(
            protos: [
                "closed_nested.proto": """
                edition = "2024";
                package neg;
                message M {
                  enum Inner {
                    option features.enum_type = CLOSED;
                    INNER_UNSPECIFIED = 0;
                  }
                  Inner x = 1;
                }
                """,
            ],
            target: "closed_nested.proto",
            expectedSubstring: "CLOSED"
        )
        try assertRejected(
            protos: [
                "legacy_enum.proto": """
                syntax = "proto2";
                package legacy;
                enum ClosedLegacy { CLOSED_ZERO = 0; }
                """,
                "uses_closed.proto": """
                edition = "2026";
                package neg;
                import "legacy_enum.proto";
                message UsesClosed {
                  legacy.ClosedLegacy e = 1;
                }
                """,
            ],
            target: "uses_closed.proto",
            expectedSubstring: "CLOSED"
        )
        try assertRejected(
            protos: [
                "legacy_enum.proto": """
                syntax = "proto2";
                package legacy;
                enum ClosedLegacy { CLOSED_ZERO = 0; }
                """,
                "uses_closed_map.proto": """
                edition = "2026";
                package neg;
                import "legacy_enum.proto";
                message UsesClosedMap {
                  map<string, legacy.ClosedLegacy> m = 1;
                }
                """,
            ],
            target: "uses_closed_map.proto",
            expectedSubstring: "CLOSED"
        )

        // 3. LEGACY_REQUIRED (top-level field in Edition 2023 and nested message field in Edition 2026)
        try assertRejected(
            protos: [
                "req_field.proto": """
                edition = "2023";
                package neg;
                message M {
                  int32 x = 1 [features.field_presence = LEGACY_REQUIRED];
                }
                """,
            ],
            target: "req_field.proto",
            expectedSubstring: "LEGACY_REQUIRED"
        )
        try assertRejected(
            protos: [
                "req_nested.proto": """
                edition = "2026";
                package neg;
                message Outer {
                  message Inner {
                    string s = 1 [features.field_presence = LEGACY_REQUIRED];
                  }
                  Inner inner = 1;
                }
                """,
            ],
            target: "req_nested.proto",
            expectedSubstring: "LEGACY_REQUIRED"
        )

        // 4. utf8_validation = NONE (singular string, repeated string, map<string, int32>, map<int32, string>)
        try assertRejected(
            protos: [
                "utf8_field.proto": """
                edition = "2023";
                package neg;
                message M {
                  string s = 1 [features.utf8_validation = NONE];
                }
                """,
            ],
            target: "utf8_field.proto",
            expectedSubstring: "utf8_validation = NONE"
        )
        try assertRejected(
            protos: [
                "utf8_repeated.proto": """
                edition = "2024";
                package neg;
                message M {
                  repeated string items = 1 [features.utf8_validation = NONE];
                }
                """,
            ],
            target: "utf8_repeated.proto",
            expectedSubstring: "utf8_validation = NONE"
        )
        try assertRejected(
            protos: [
                "utf8_map_key.proto": """
                edition = "2023";
                package neg;
                option features.utf8_validation = NONE;
                message M {
                  map<string, int32> labels = 1;
                }
                """,
            ],
            target: "utf8_map_key.proto",
            expectedSubstring: "utf8_validation = NONE"
        )
        try assertRejected(
            protos: [
                "utf8_map_val.proto": """
                edition = "2026";
                package neg;
                option features.utf8_validation = NONE;
                message M {
                  map<int32, string> names = 1;
                }
                """,
            ],
            target: "utf8_map_val.proto",
            expectedSubstring: "utf8_validation = NONE"
        )

        // File-level utf8_validation = NONE with NO string fields is allowed
        try EditionsTestHarness.withTempDir { dir in
            let ds = try EditionsTestHarness.compileProtosToDescriptorSet(
                protos: [
                    "utf8_no_strings.proto": """
                    edition = "2023";
                    package ok;
                    option features.utf8_validation = NONE;
                    message NoStrings {
                      int32 n = 1;
                      bytes raw = 2;
                    }
                    """,
                ],
                targets: ["utf8_no_strings.proto"],
                in: dir
            )
            let out = try generator.generate(files: ds.files.filter { $0.name == "utf8_no_strings.proto" })
            #expect(out.count == 1)
        }

        // 5. Custom non-zero defaults
        for (name, fieldDecl) in [
            ("def_int.proto", "int32 x = 1 [default = 42];"),
            ("def_bool.proto", "bool b = 1 [default = true];"),
            ("def_str.proto", "string s = 1 [default = \"abc\"];"),
            ("def_dbl.proto", "double d = 1 [default = 1.5];"),
            ("def_neg_zero.proto", "double d = 1 [default = -0.0];"),
            ("def_enum.proto", "S st = 1 [default = S_ONE];"),
        ] {
            try assertRejected(
                protos: [
                    name: """
                    edition = "2023";
                    package neg;
                    enum S { S_ZERO = 0; S_ONE = 1; }
                    message M {
                      \(fieldDecl)
                    }
                    """,
                ],
                target: name,
                expectedSubstring: "default value"
            )
        }

        // 6. Non-option extensions & extension ranges in Editions
        try assertRejected(
            protos: [
                "ext_range.proto": """
                edition = "2023";
                package neg;
                message M {
                  int32 id = 1;
                  extensions 100 to 199;
                }
                """,
            ],
            target: "ext_range.proto",
            expectedSubstring: "extension"
        )
        try assertRejected(
            protos: [
                "base_ext.proto": """
                syntax = "proto2";
                package base;
                message Extensible {
                  extensions 100 to 199;
                }
                """,
                "file_ext.proto": """
                edition = "2023";
                package neg;
                import "base_ext.proto";
                extend base.Extensible {
                  int32 custom_ext = 100;
                }
                """,
            ],
            target: "file_ext.proto",
            expectedSubstring: "extension"
        )

        // Option extensions (google.protobuf.*Options) ARE allowed in Editions
        try EditionsTestHarness.withTempDir { dir in
            let ds = try EditionsTestHarness.compileProtosToDescriptorSet(
                protos: [
                    "opt_ext.proto": """
                    edition = "2023";
                    package ok;
                    import "google/protobuf/descriptor.proto";
                    extend google.protobuf.FieldOptions {
                      string custom_tag = 50001;
                    }
                    message Tagged {
                      int32 value = 1 [(custom_tag) = "ok"];
                    }
                    """,
                ],
                targets: ["opt_ext.proto"],
                in: dir
            )
            let out = try generator.generate(files: ds.files.filter { $0.name == "opt_ext.proto" })
            #expect(out.count == 1)
        }

        // 7. Legacy proto2 group rejected
        try assertRejected(
            protos: [
                "proto2_group.proto": """
                syntax = "proto2";
                package neg;
                message M {
                  optional group LegacyGrp = 1 {
                    optional int32 x = 2;
                  }
                }
                """,
            ],
            target: "proto2_group.proto",
            expectedSubstring: "group"
        )
    }
}
