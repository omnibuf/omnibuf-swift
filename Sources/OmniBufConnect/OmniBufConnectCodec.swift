import Foundation
import OmniBuf

/// Connect RPC codec for `OmniBufMessage` types (`connect-swift` `Codec` shape).
public struct OmniBufConnectCodec: Sendable, Equatable {
    /// Standard Connect codec name for compact OmniBuf payloads.
    public static let compactName = "omnibuf"

    /// Connect codec name for self-describing OmniBuf payloads carrying Field #0 metadata.
    public static let selfDescribingName = "x-omnibuf"

    /// Shared codec instance configured for compact encoding and default decode limits.
    public static let compact = OmniBufConnectCodec(encodeOptions: .default, decodeOptions: .default)

    /// Shared codec instance configured for self-describing Field #0 encoding and default decode limits.
    public static let selfDescribing = OmniBufConnectCodec(encodeOptions: .selfDescribing, decodeOptions: .default)

    /// Encoding options applied by `serialize(message:)`.
    public let encodeOptions: EncodeOptions

    /// Decoding limits applied by `deserialize(source:)`.
    public let decodeOptions: DecodeOptions

    public init(
        encodeOptions: EncodeOptions = .default,
        decodeOptions: DecodeOptions = .default
    ) {
        self.encodeOptions = encodeOptions
        self.decodeOptions = decodeOptions
    }

    /// Codec identifier advertised over Connect (`"omnibuf"` or `"x-omnibuf"`).
    public func name() -> String {
        encodeOptions.selfDescribing ? Self.selfDescribingName : Self.compactName
    }

    /// Connect unary content-type header (`"application/omnibuf"` or `"application/x-omnibuf"`).
    public var unaryContentType: String {
        "application/\(name())"
    }

    /// Connect streaming content-type header (`"application/connect+omnibuf"` or `"application/connect+x-omnibuf"`).
    public var streamingContentType: String {
        "application/connect+\(name())"
    }

    /// Serializes `message` into OmniBuf wire `Data`.
    public func serialize<Input: OmniBufMessage>(message: Input) throws -> Data {
        Data(try message.encodeOmniBuf(options: encodeOptions))
    }

    /// Deserializes OmniBuf wire `Data` into `Output`.
    public func deserialize<Output: OmniBufMessage>(source: Data) throws -> Output {
        try Output.decoded(from: [UInt8](source), options: decodeOptions)
    }
}
