/// OmniBuf v0.1 4-bit wire type codes and protocol constants.
public enum WireType: UInt8, Sendable, Equatable, Hashable {
    case uint = 0
    case sint = 1
    case boolFalse = 2
    case boolTrue = 3
    case fixed32 = 4
    case fixed64 = 5
    case sfixed32 = 6
    case sfixed64 = 7
    case float32 = 8
    case float64 = 9
    case string = 10
    case bytes = 11
    case subMsg = 12
    case array = 13
    case map = 14
    case extended = 15

    /// Raw constants for hot-path byte operations.
    public static let wireUint: UInt8 = 0
    public static let wireSint: UInt8 = 1
    public static let wireBoolFalse: UInt8 = 2
    public static let wireBoolTrue: UInt8 = 3
    public static let wireFixed32: UInt8 = 4
    public static let wireFixed64: UInt8 = 5
    public static let wireSfixed32: UInt8 = 6
    public static let wireSfixed64: UInt8 = 7
    public static let wireFloat32: UInt8 = 8
    public static let wireFloat64: UInt8 = 9
    public static let wireString: UInt8 = 10
    public static let wireBytes: UInt8 = 11
    public static let wireSubMsg: UInt8 = 12
    public static let wireArray: UInt8 = 13
    public static let wireMap: UInt8 = 14
    public static let wireExtended: UInt8 = 15

    /// Maximum valid OmniBuf field number (2^29 - 1 = 536,870,911).
    public static let maxFieldNumber: UInt64 = 536_870_911

    /// Default maximum container / submessage recursion depth.
    public static let maxNestingDepth: Int = 32

    /// Field #0 tag byte: `(0 << 4) | 12 = 12`, encoded as 1-byte Prefix-Varint `(12 << 1) | 1 = 0x19`.
    public static let field0TagByte: UInt8 = 0x19

    /// Returns whether `wt` is a valid element or map value wire type code (0..15, excluding 3).
    @inlinable
    @inline(__always)
    public static func isValidCollectionValueType(_ wt: UInt8) -> Bool {
        wt <= 15 && wt != wireBoolTrue
    }

    /// Returns whether `wt` is a valid `WireMap` key wire type code (integers, bool, string).
    @inlinable
    @inline(__always)
    public static func isValidMapKeyType(_ wt: UInt8) -> Bool {
        switch wt {
        case wireUint, wireSint, wireBoolFalse, wireFixed32, wireFixed64,
             wireSfixed32, wireSfixed64, wireString:
            return true
        default:
            return false
        }
    }

    /// Returns the fixed byte width of an element inside a collection, or 0 for variable-width types.
    @inlinable
    @inline(__always)
    public static func fixedCollectionElementWidth(_ wt: UInt8) -> Int {
        switch wt {
        case wireBoolFalse:
            return 1
        case wireFixed32, wireSfixed32, wireFloat32:
            return 4
        case wireFixed64, wireSfixed64, wireFloat64:
            return 8
        default:
            return 0
        }
    }
}
