// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "omnibuf-swift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "OmniBuf",
            targets: ["OmniBuf"]
        ),
        .library(
            name: "OmniBufProtobuf",
            targets: ["OmniBufProtobuf"]
        ),
        .library(
            name: "OmniBufGRPC",
            targets: ["OmniBufGRPC"]
        ),
        .library(
            name: "OmniBufConnect",
            targets: ["OmniBufConnect"]
        ),
        .executable(
            name: "protoc-gen-omnibuf-swift",
            targets: ["protoc-gen-omnibuf-swift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.41.0"),
    ],
    targets: [
        .target(
            name: "OmniBuf",
            dependencies: []
        ),
        .target(
            name: "OmniBufGRPC",
            dependencies: [
                "OmniBuf",
            ]
        ),
        .target(
            name: "OmniBufConnect",
            dependencies: [
                "OmniBuf",
            ]
        ),
        .target(
            name: "OmniBufProtobuf",
            dependencies: [
                "OmniBuf",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .target(
            name: "OmniBufCodeGen",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ]
        ),
        .target(
            name: "OmniBufGenerated",
            dependencies: [
                "OmniBuf",
            ]
        ),
        .executableTarget(
            name: "protoc-gen-omnibuf-swift",
            dependencies: [
                "OmniBufCodeGen",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "conformance-swift",
            dependencies: [
                "OmniBuf",
                "OmniBufGenerated",
                "OmniBufProtobuf",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "OmniBufBench",
            dependencies: [
                "OmniBuf",
                "OmniBufGenerated",
                "OmniBufProtobuf",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "OmniBufTests",
            dependencies: [
                "OmniBuf",
                "OmniBufCodeGen",
                "OmniBufProtobuf",
                "OmniBufGRPC",
                "OmniBufConnect",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ]
        ),
    ]
)
