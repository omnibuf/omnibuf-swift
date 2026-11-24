# omnibuf-swift

[![OmniBuf Spec: v1 DRAFT-1](https://img.shields.io/badge/OmniBuf%20Spec-v1%20DRAFT--1-FF4F18)](https://omnibuf.com/spec)

Swift 6 implementation of the [OmniBuf v1 DRAFT-1 wire format](https://omnibuf.com/spec). Documentation and benchmarks live at [omnibuf.com/swift](https://omnibuf.com/swift).

## Install

Add `omnibuf-swift` to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/omnibuf/omnibuf-swift.git", from: "0.1.0"),
]
```

Depend on the `OmniBuf` product for the zero-dependency core, `OmniBufGRPC` for gRPC serializers, `OmniBufConnect` for Connect codecs, or `OmniBufProtobuf` for `SwiftProtobuf` interop.

## Quick usage

```swift
import OmniBuf

struct Location: OmniBufStruct, Sendable, Equatable {
    var city: String = ""
    var rack: UInt32 = 0

    static let omniBufSchema = OmniBufStructSchema<Self>(
        typeName: "Location",
        fields: [
            Field.string(3, "city", \.city),
            Field.uint32(4, "rack", \.rack),
        ]
    )
}

let wire = try Location(city: "FRA", rack: 42).encodeOmniBuf()
let decoded = try Location.decoded(from: wire)
```

## gRPC-Swift

Import the detached `OmniBufGRPC` product to wire `OmniBufMessage` serializers and deserializers into `grpc-swift` without pulling gRPC into core `OmniBuf`.

```swift
import OmniBufGRPC

let serializer = OmniBufGRPCSerializer<Location>.compact // codec name: "omnibuf"
let deserializer = OmniBufGRPCDeserializer<Location>.default
let payload = try serializer.serialize(Location(city: "FRA", rack: 42))
let decoded = try deserializer.deserialize(payload)
```

## Connect-Swift

Import the separate `OmniBufConnect` product for `connect-swift` codecs.

```swift
import OmniBufConnect

let codec = OmniBufConnectCodec.compact // or .selfDescribing for "x-omnibuf"
let payload = try codec.serialize(message: Location(city: "FRA", rack: 42))
let decoded: Location = try codec.deserialize(source: payload)
```

## Details

- Built for Swift 6 strict concurrency with `Sendable` structs and a zero-dependency `OmniBuf` core module.
- `OmniBufStruct` maps native Swift structs through declarative `OmniBufStructSchema` key-path codecs, with `Indirect<T>` for recursive types.
- `OmniBufProtobuf` encodes and decodes `SwiftProtobuf.Message` values via custom `SwiftProtobuf.Visitor` and `SwiftProtobuf.Decoder` implementations.
- `protoc-gen-omnibuf-swift` generates Swift structs, single-pass encoders/decoders, and lazy `Opaque*` views with wire splicing.
- `decodeBlind` and `decodeBlindJSON` inspect arbitrary packets and resolve inline `Field #0` schema metadata.

## License

Apache-2.0. See [LICENSE](./LICENSE).
