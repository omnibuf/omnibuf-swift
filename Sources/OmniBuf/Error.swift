/// Errors produced by OmniBuf encoding, decoding, and validation.
public enum OmniBufError: Error, Equatable, Sendable, CustomStringConvertible {
    case parse(String)
    case serialize(String)
    case depthLimitExceeded(Int)
    case unsupportedExtension(UInt8)
    case allocationLimitExceeded(String)

    public var description: String {
        switch self {
        case .parse(let msg):
            return "OmniBuf parse error: \(msg)"
        case .serialize(let msg):
            return "OmniBuf serialize error: \(msg)"
        case .depthLimitExceeded(let depth):
            return "OmniBuf nesting depth \(depth) exceeds limit"
        case .unsupportedExtension(let ext):
            return "OmniBuf unsupported WireExtended ext type \(ext)"
        case .allocationLimitExceeded(let msg):
            return "OmniBuf allocation limit exceeded: \(msg)"
        }
    }
}
