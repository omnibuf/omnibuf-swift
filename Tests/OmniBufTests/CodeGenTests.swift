import OmniBufCodeGen
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import Testing

@Suite("OmniBufCodeGen Tests")
struct CodeGenTests {
    @Test("Output file name replaces .proto suffix with .omnibuf.swift")
    func testOutputFileName() {
        let generator = OmniBufCodeGenerator()
        #expect(generator.outputFileName(for: "omnibuf/bench/peer.proto") == "omnibuf/bench/peer.omnibuf.swift")
        #expect(generator.outputFileName(for: "custom_schema") == "custom_schema.omnibuf.swift")
    }

    @Test("Code generator handles recursive messages, nested type qualification, enums, and depth limits")
    func testCodegenRecursiveNestedEnumsAndDepthLimit() throws {
        // Must not falsely advertise proto3_optional
        #expect(OmniBufCodeGenerator.supportedFeatures.isEmpty)

        // Build a synthetic FileDescriptorProto containing:
        // - Top-level enum TopStatus
        // - Self-recursive message TreeNode (singular primary: TreeNode, repeated children: TreeNode)
        // - Mutually recursive messages MutualA <-> MutualB
        // - Two messages OuterA and OuterB, each with nested message Item and nested enum Status
        var file = Google_Protobuf_FileDescriptorProto()
        file.name = "test_codegen.proto"
        file.package = "test.pkg"
        file.syntax = "proto3"

        file.enumType = [
            Google_Protobuf_EnumDescriptorProto.with {
                $0.name = "TopStatus"
                $0.value = [
                    Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "TOP_STATUS_UNSPECIFIED"; $0.number = 0 },
                    Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "TOP_STATUS_OK"; $0.number = 1 },
                ]
            },
        ]

        let treeNode = Google_Protobuf_DescriptorProto.with {
            $0.name = "TreeNode"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "id"; $0.jsonName = "id"; $0.number = 1; $0.label = .optional; $0.type = .uint32
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "primary"; $0.jsonName = "primary"; $0.number = 2; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.TreeNode"
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "children"; $0.jsonName = "children"; $0.number = 3; $0.label = .repeated; $0.type = .message; $0.typeName = ".test.pkg.TreeNode"
                },
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "status"; $0.jsonName = "status"; $0.number = 4; $0.label = .optional; $0.type = .enum; $0.typeName = ".test.pkg.TopStatus"
                },
            ]
        }

        let mutualA = Google_Protobuf_DescriptorProto.with {
            $0.name = "MutualA"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "b"; $0.jsonName = "b"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.MutualB"
                },
            ]
        }
        let mutualB = Google_Protobuf_DescriptorProto.with {
            $0.name = "MutualB"
            $0.field = [
                Google_Protobuf_FieldDescriptorProto.with {
                    $0.name = "a"; $0.jsonName = "a"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.MutualA"
                },
            ]
        }

        func makeOuter(_ outerName: String) -> Google_Protobuf_DescriptorProto {
            Google_Protobuf_DescriptorProto.with {
                $0.name = outerName
                $0.nestedType = [
                    Google_Protobuf_DescriptorProto.with {
                        $0.name = "Item"
                        $0.field = [
                            Google_Protobuf_FieldDescriptorProto.with {
                                $0.name = "val"; $0.jsonName = "val"; $0.number = 1; $0.label = .optional; $0.type = .uint32
                            },
                        ]
                    },
                ]
                $0.enumType = [
                    Google_Protobuf_EnumDescriptorProto.with {
                        $0.name = "Status"
                        $0.value = [
                            Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "STATUS_UNSPECIFIED"; $0.number = 0 },
                            Google_Protobuf_EnumValueDescriptorProto.with { $0.name = "STATUS_ACTIVE"; $0.number = 1 },
                        ]
                    },
                ]
                $0.field = [
                    Google_Protobuf_FieldDescriptorProto.with {
                        $0.name = "item"; $0.jsonName = "item"; $0.number = 1; $0.label = .optional; $0.type = .message; $0.typeName = ".test.pkg.\(outerName).Item"
                    },
                    Google_Protobuf_FieldDescriptorProto.with {
                        $0.name = "status"; $0.jsonName = "status"; $0.number = 2; $0.label = .optional; $0.type = .enum; $0.typeName = ".test.pkg.\(outerName).Status"
                    },
                ]
            }
        }

        file.messageType = [treeNode, mutualA, mutualB, makeOuter("OuterA"), makeOuter("OuterB")]

        let descriptorSet = DescriptorSet(protos: [file])
        let generator = OmniBufCodeGenerator()
        let outputs = generator.generate(files: descriptorSet.files)

        guard outputs.count == 1 else {
            Issue.record("expected 1 generated file, got \(outputs.count)")
            return
        }
        #expect(outputs[0].fileName == "test_codegen.omnibuf.swift")

        let code = outputs[0].contents
        // Self-recursive singular field uses Indirect<TreeNode>?, repeated stays [TreeNode]
        #expect(code.contains("public var primary: Indirect<TreeNode>?"))
        #expect(code.contains("public var children: [TreeNode]"))
        // Mutually recursive singular fields use Indirect<MutualB>? and Indirect<MutualA>?
        #expect(code.contains("public var b: Indirect<MutualB>?"))
        #expect(code.contains("public var a: Indirect<MutualA>?"))
        // Non-cyclic nested singular message fields stay plain Optional, qualified with parent name
        #expect(code.contains("public struct OuterA_Item:"))
        #expect(code.contains("public struct OuterB_Item:"))
        #expect(code.contains("public var item: OuterA_Item?"))
        #expect(code.contains("public var item: OuterB_Item?"))
        // Nested enums are qualified and enum fields use generated enum types
        #expect(code.contains("public enum OuterA_Status: Int32"))
        #expect(code.contains("public enum OuterB_Status: Int32"))
        #expect(code.contains("public var status: TopStatus"))
        #expect(code.contains("public var status: OuterA_Status"))
        #expect(code.contains("public var status: OuterB_Status"))
        // Encoding enforces WireType.maxNestingDepth and does not call estimatedOmniBufSize inside encodeOmniBufBodyFast
        #expect(code.contains("guard depth <= WireType.maxNestingDepth"))
        #expect(!code.contains("sub.estimatedOmniBufSize"))
        #expect(!code.contains("elem.estimatedOmniBufSize"))
        // Pre-allocation budget checks & SchemaMeta.validateSlice with budget
        #expect(code.contains("try SchemaMeta.validateSlice(slice, depth: depth &+ 1, budget: &budget)"))
    }
}
