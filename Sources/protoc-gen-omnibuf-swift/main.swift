import OmniBufCodeGen
import SwiftProtobuf
import SwiftProtobufPluginLibrary

@main
struct OmniBufSwiftPlugin: CodeGenerator {
    var version: String? { "0.1.0" }
    var projectURL: String? { "https://github.com/omnibuf/omnibuf-swift" }
    var copyrightLine: String? { "Copyright 2026 Kevin McDonald" }

    var supportedFeatures: [Google_Protobuf_Compiler_CodeGeneratorResponse.Feature] {
        OmniBufCodeGenerator.supportedFeatures
    }

    var supportedEditionRange: ClosedRange<Google_Protobuf_Edition> {
        OmniBufCodeGenerator.supportedEditionRange
    }

    init() {}

    func generate(
        files: [FileDescriptor],
        parameter: any CodeGeneratorParameter,
        protoCompilerContext: any ProtoCompilerContext,
        generatorOutputs: any GeneratorOutputs
    ) throws {
        let generator = OmniBufCodeGenerator()
        for output in try generator.generate(files: files) {
            try generatorOutputs.add(fileName: output.fileName, contents: output.contents)
        }
    }
}
