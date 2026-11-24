import Foundation
import OmniBuf

/// Constants for gRPC content types and codec identifiers used with OmniBuf.
public enum OmniBufGRPC {
    /// Standard gRPC codec name for compact OmniBuf payloads.
    public static let codecName = "omnibuf"

    /// Codec name for self-describing OmniBuf payloads carrying Field #0 metadata.
    public static let selfDescribingCodecName = "x-omnibuf"

    /// gRPC HTTP/2 content-type header value for compact OmniBuf payloads.
    public static let contentType = "application/grpc+omnibuf"

    /// gRPC HTTP/2 content-type header value for self-describing OmniBuf payloads.
    public static let selfDescribingContentType = "application/grpc+x-omnibuf"
}

/// Detached gRPC message serializer for `OmniBufMessage` types.
/// Matches the `grpc-swift` `MessageSerializer` shape without coupling core `OmniBuf` to `grpc-swift`.
public struct OmniBufGRPCSerializer<Message: OmniBufMessage>: Sendable, Equatable {
    /// Encoding options applied by `serialize(_:)`.
    public let encodeOptions: EncodeOptions

    public static var compact: Self {
        Self(encodeOptions: .default)
    }

    public static var selfDescribing: Self {
        Self(encodeOptions: .selfDescribing)
    }

    public init(encodeOptions: EncodeOptions = .default) {
        self.encodeOptions = encodeOptions
    }

    /// gRPC codec identifier matching `encodeOptions`.
    public var name: String {
        encodeOptions.selfDescribing ? OmniBufGRPC.selfDescribingCodecName : OmniBufGRPC.codecName
    }

    /// gRPC content-type header matching `encodeOptions`.
    public var contentType: String {
        encodeOptions.selfDescribing ? OmniBufGRPC.selfDescribingContentType : OmniBufGRPC.contentType
    }

    /// Serializes `message` into OmniBuf wire bytes.
    public func serialize(_ message: Message) throws -> [UInt8] {
        try message.encodeOmniBuf(options: encodeOptions)
    }

    /// Serializes `message` into OmniBuf wire `Data`.
    public func serializeData(_ message: Message) throws -> Data {
        Data(try serialize(message))
    }
}

/// Detached gRPC message deserializer for `OmniBufMessage` types.
/// Matches the `grpc-swift` `MessageDeserializer` shape without coupling core `OmniBuf` to `grpc-swift`.
public struct OmniBufGRPCDeserializer<Message: OmniBufMessage>: Sendable, Equatable {
    /// Decoding limits applied by `deserialize(_:)`.
    public let decodeOptions: DecodeOptions

    public static var `default`: Self {
        Self(decodeOptions: .default)
    }

    public init(decodeOptions: DecodeOptions = .default) {
        self.decodeOptions = decodeOptions
    }

    /// Deserializes OmniBuf wire bytes into `Message`.
    public func deserialize(_ bytes: [UInt8]) throws -> Message {
        try Message.decoded(from: bytes, options: decodeOptions)
    }

    /// Deserializes OmniBuf wire `Data` into `Message`.
    public func deserializeData(_ data: Data) throws -> Message {
        try deserialize([UInt8](data))
    }
}
