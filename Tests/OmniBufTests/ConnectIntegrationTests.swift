import Foundation
import OmniBuf
import OmniBufConnect
import Testing

private struct ConnectPingRequest: OmniBufStruct, Sendable, Equatable {
    var node: String = ""
    var seq: UInt64 = 0
    var ok: Bool = false

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "ConnectPingRequest",
        fields: [
            Field.string(1, "node", \.node),
            Field.uint64(2, "seq", \.seq),
            Field.bool(3, "ok", \.ok),
        ]
    )
}

private struct ConnectPingResponse: OmniBufStruct, Sendable, Equatable {
    var echoNode: String = ""
    var ackSeq: UInt64 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "ConnectPingResponse",
        fields: [
            Field.string(1, "echo_node", \.echoNode),
            Field.uint64(2, "ack_seq", \.ackSeq),
        ]
    )
}

/// Simulates a Connect unary HTTP request/response exchange wired with OmniBufConnectCodec.
private struct ConnectUnaryTransport: Sendable {
    let codec: OmniBufConnectCodec

    func call<Request: OmniBufMessage, Response: OmniBufMessage>(
        _ request: Request,
        handler: @Sendable (Request) -> Response
    ) throws -> (contentType: String, response: Response) {
        let reqBody = try codec.serialize(message: request)
        let decodedReq: Request = try codec.deserialize(source: reqBody)
        let respMsg = handler(decodedReq)
        let respBody = try codec.serialize(message: respMsg)
        let decodedResp: Response = try codec.deserialize(source: respBody)
        return (codec.unaryContentType, decodedResp)
    }
}

@Suite("OmniBufConnect Integration Tests")
struct ConnectIntegrationTests {
    @Test("Compact and self-describing codecs expose expected Connect names and content types")
    func testCodecNamesAndContentTypes() {
        #expect(OmniBufConnectCodec.compact.name() == "omnibuf")
        #expect(OmniBufConnectCodec.compact.unaryContentType == "application/omnibuf")
        #expect(OmniBufConnectCodec.compact.streamingContentType == "application/connect+omnibuf")

        #expect(OmniBufConnectCodec.selfDescribing.name() == "x-omnibuf")
        #expect(OmniBufConnectCodec.selfDescribing.unaryContentType == "application/x-omnibuf")
        #expect(OmniBufConnectCodec.selfDescribing.streamingContentType == "application/connect+x-omnibuf")
    }

    @Test("Connect unary transport round-trips OmniBuf messages")
    func testUnaryTransportRoundTrip() throws {
        let transport = ConnectUnaryTransport(codec: .compact)
        let result = try transport.call(ConnectPingRequest(node: "edge-nrt-03", seq: 7, ok: true)) { req in
            ConnectPingResponse(echoNode: req.node, ackSeq: req.seq + 10)
        }
        #expect(result.contentType == "application/omnibuf")
        #expect(result.response == ConnectPingResponse(echoNode: "edge-nrt-03", ackSeq: 17))
    }

    @Test("Self-describing Connect codec embeds Field #0 metadata and round-trips")
    func testSelfDescribingRoundTrip() throws {
        let original = ConnectPingRequest(node: "edge-sjc-04", seq: 512, ok: true)
        let compactData = try OmniBufConnectCodec.compact.serialize(message: original)
        let selfDescData = try OmniBufConnectCodec.selfDescribing.serialize(message: original)

        #expect(selfDescData.count > compactData.count)

        let decoded: ConnectPingRequest = try OmniBufConnectCodec.selfDescribing.deserialize(source: selfDescData)
        #expect(decoded == original)

        let blind = try decodeBlind([UInt8](selfDescData))
        #expect(blind["node"] == .string("edge-sjc-04"))
        #expect(blind["seq"] == .uint(512))
    }

    @Test("Connect codec enforces DecodeOptions limits")
    func testDecodeOptionsLimits() throws {
        let limited = OmniBufConnectCodec(
            encodeOptions: .default,
            decodeOptions: DecodeOptions(maxMessageBytes: 4)
        )
        let data = try limited.serialize(message: ConnectPingRequest(node: "oversized-node-name", seq: 1, ok: true))

        #expect(throws: OmniBufError.self) {
            let _: ConnectPingRequest = try limited.deserialize(source: data)
        }
    }
}
