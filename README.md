# omnibuf-swift

Swift 6 implementation of the [OmniBuf v0.1](https://omnibuf.com/spec) binary wire format.

## Features

- **Zero-dependency core (`OmniBuf`)**: Pure Swift standard library wire reader, single-pass backpatching writer, strict UTF-8 validator, Field #0 `SchemaMeta`, lazy `Opaque` scanners, in-place wire splicing, declarative `OmniBufStruct` schemas, and schema-less `decodeBlind` / `decodeBlindJSON`.
- **Tier 1 (`protoc-gen-omnibuf-swift`)**: Protobuf compiler plugin generating Swift structs, single-pass encoders/decoders, and zero-copy lazy `Opaque<Message>` views with wire splicing.
- **Tier 2 (`OmniBufProtobuf`)**: Direct `SwiftProtobuf.Message` encoding and decoding via custom `SwiftProtobuf.Visitor` and `SwiftProtobuf.Decoder` implementations.
- **Tier 3 (`OmniBufStruct`)**: Native Swift structs mapped with declarative `OmniBufStructSchema` key-path field codecs, including recursive types via `Indirect<T>`.
- **Tier 4 (`decodeBlind`)**: Schema-less packet inspection to `BlindValue` trees and canonical JSON, resolving Field #0 `SchemaMeta` names or falling back to `field_<N>`.
- **Cross-language conformance**: Passes all 992/992 test cases across all 4 tiers in `omnibuf-go`'s `conformance-runner`.

## Installation

Add `omnibuf-swift` to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/omnibuf/omnibuf-swift.git", from: "0.1.0"),
]
```

Depend on `"OmniBuf"` for the zero-dependency core, or `"OmniBufProtobuf"` to add `SwiftProtobuf.Message` support.

## Quick Start

### Declarative Swift Structs (Tier 3)

```swift
import OmniBuf

struct Location: OmniBufStruct, Equatable {
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

let bytes = try Location(city: "FRA", rack: 42).encodeOmniBuf()
let decoded = try Location.decoded(from: bytes)
```

### Schema-less Inspection (Tier 4)

```swift
import OmniBuf

let json = try decodeBlindJSON(bytes)
// {"field_3":"FRA","field_4":42}
```

### Code Generation (`protoc-gen-omnibuf-swift`)

```bash
swift build -c release --product protoc-gen-omnibuf-swift
protoc \
  --plugin=protoc-gen-omnibuf-swift=.build/release/protoc-gen-omnibuf-swift \
  --omnibuf-swift_out=./Generated \
  -I proto proto/omnibuf/bench/peer.proto
```

### Lazy Zero-Decode Views & Wire Splicing

```swift
var view = OpaquePeerUpdate(packet)
let city = view.getLocation().getCity()
view.setSequence(view.getSequence() + 1)
let updatedPacket = view.marshal()
```

## Development

```bash
just build         # Debug build
just build-release # Release build
just test          # Swift unit tests
just conformance   # Run 992-case cross-language conformance suite
just bench         # Run 6-category PeerUpdate benchmark suite -> testdata/benchmarks.json
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
