import Foundation
import OmniBuf
import OmniBufGRPC
import Testing

private struct GRPCPingRequest: OmniBufStruct, Sendable, Equatable {
    var node: String = ""
    var seq: UInt64 = 0
    var ok: Bool = false

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "GRPCPingRequest",
        fields: [
            Field.string(1, "node", \.node),
            Field.uint64(2, "seq", \.seq),
            Field.bool(3, "ok", \.ok),
        ]
    )
}

private struct GRPCPingResponse: OmniBufStruct, Sendable, Equatable {
    var echoNode: String = ""
    var ackSeq: UInt64 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "GRPCPingResponse",
        fields: [
            Field.string(1, "echo_node", \.echoNode),
            Field.uint64(2, "ack_seq", \.ackSeq),
        ]
    )
}

/// Minimal gRPC length-prefixed frame codec (1-byte compression flag + 4-byte big-endian length).
private enum GRPCFrame {
    static func pack(_ payload: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [0]
        let len = UInt32(payload.count)
        frame.append(UInt8((len >> 24) & 0xFF))
        frame.append(UInt8((len >> 16) & 0xFF))
        frame.append(UInt8((len >> 8) & 0xFF))
        frame.append(UInt8(len & 0xFF))
        frame.append(contentsOf: payload)
        return frame
    }

    static func unpack(_ frame: [UInt8]) -> [UInt8]? {
        guard frame.count >= 5, frame[0] == 0 else { return nil }
        let len = (Int(frame[1]) << 24) | (Int(frame[2]) << 16) | (Int(frame[3]) << 8) | Int(frame[4])
        guard frame.count == 5 + len else { return nil }
        return Array(frame[5...])
    }
}

private enum GRPCFrameError: Error {
    case malformedFrame
}

/// Simulates a gRPC-Swift unary method pipeline wired with OmniBufGRPCSerializer and OmniBufGRPCDeserializer.
private struct UnaryGRPCPipeline<Request: OmniBufMessage, Response: OmniBufMessage>: Sendable {
    let requestSerializer: OmniBufGRPCSerializer<Request>
    let requestDeserializer: OmniBufGRPCDeserializer<Request>
    let responseSerializer: OmniBufGRPCSerializer<Response>
    let responseDeserializer: OmniBufGRPCDeserializer<Response>
    let handler: @Sendable (Request) -> Response

    func invoke(_ request: Request) throws -> Response {
        let reqFrame = GRPCFrame.pack(try requestSerializer.serialize(request))
        guard let reqBytes = GRPCFrame.unpack(reqFrame) else {
            throw GRPCFrameError.malformedFrame
        }
        let serverReq = try requestDeserializer.deserialize(reqBytes)
        let serverResp = handler(serverReq)
        let respFrame = GRPCFrame.pack(try responseSerializer.serialize(serverResp))
        guard let respBytes = GRPCFrame.unpack(respFrame) else {
            throw GRPCFrameError.malformedFrame
        }
        return try responseDeserializer.deserialize(respBytes)
    }
}

@Suite("OmniBufGRPC Integration Tests")
struct GRPCIntegrationTests {
    @Test("Codec names and content-types match gRPC specification")
    func testConstantsAndMetadata() {
        #expect(OmniBufGRPC.codecName == "omnibuf")
        #expect(OmniBufGRPC.selfDescribingCodecName == "x-omnibuf")
        #expect(OmniBufGRPC.contentType == "application/grpc+omnibuf")
        #expect(OmniBufGRPC.selfDescribingContentType == "application/grpc+x-omnibuf")

        let compact = OmniBufGRPCSerializer<GRPCPingRequest>.compact
        let selfDesc = OmniBufGRPCSerializer<GRPCPingRequest>.selfDescribing
        #expect(compact.name == "omnibuf")
        #expect(compact.contentType == "application/grpc+omnibuf")
        #expect(selfDesc.name == "x-omnibuf")
        #expect(selfDesc.contentType == "application/grpc+x-omnibuf")
    }

    @Test("Unary gRPC pipeline round-trips framed OmniBuf request and response")
    func testUnaryPipelineRoundTrip() throws {
        let pipeline = UnaryGRPCPipeline<GRPCPingRequest, GRPCPingResponse>(
            requestSerializer: .compact,
            requestDeserializer: .default,
            responseSerializer: .compact,
            responseDeserializer: .default
        ) { req in
            GRPCPingResponse(echoNode: req.node, ackSeq: req.seq + 1)
        }

        let response = try pipeline.invoke(GRPCPingRequest(node: "edge-fra-01", seq: 42, ok: true))
        #expect(response == GRPCPingResponse(echoNode: "edge-fra-01", ackSeq: 43))
    }

    @Test("Self-describing gRPC serializer embeds Field #0 metadata and round-trips via Data")
    func testSelfDescribingRoundTrip() throws {
        let compactSer = OmniBufGRPCSerializer<GRPCPingRequest>.compact
        let selfDescSer = OmniBufGRPCSerializer<GRPCPingRequest>.selfDescribing
        let deser = OmniBufGRPCDeserializer<GRPCPingRequest>.default

        let original = GRPCPingRequest(node: "edge-iad-02", seq: 9001, ok: false)
        let compactData = try compactSer.serializeData(original)
        let selfDescData = try selfDescSer.serializeData(original)

        #expect(selfDescData.count > compactData.count)
        #expect(try deser.deserializeData(selfDescData) == original)

        let blind = try decodeBlind([UInt8](selfDescData))
        #expect(blind["node"] == .string("edge-iad-02"))
        #expect(blind["seq"] == .uint(9001))
    }

    @Test("Deserializer enforces DecodeOptions limits")
    func testDecodeOptionsLimits() throws {
        let ser = OmniBufGRPCSerializer<GRPCPingRequest>.compact
        let limited = OmniBufGRPCDeserializer<GRPCPingRequest>(
            decodeOptions: DecodeOptions(maxMessageBytes: 4)
        )
        let wire = try ser.serialize(GRPCPingRequest(node: "oversized-node-name", seq: 1, ok: true))

        #expect(throws: OmniBufError.self) {
            _ = try limited.deserialize(wire)
        }
    }
}
