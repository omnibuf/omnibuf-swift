/// Options controlling OmniBuf encoding behavior.
public struct EncodeOptions: Sendable, Equatable {
    /// Sort map keys deterministically (unsigned UTF-8 byte order for strings, numeric order for ints, false before true for bools).
    public var deterministic: Bool

    /// Embed Field #0 (`omnibuf.v1.SchemaMeta`) at the beginning of the root message.
    public var selfDescribing: Bool

    public init(deterministic: Bool = true, selfDescribing: Bool = false) {
        self.deterministic = deterministic
        self.selfDescribing = selfDescribing
    }

    public static let `default` = EncodeOptions()
    public static let selfDescribing = EncodeOptions(deterministic: true, selfDescribing: true)
}

/// Options controlling OmniBuf decoding and security limits.
public struct DecodeOptions: Sendable, Equatable {
    /// Maximum allowed input packet byte length (default: 64 MiB).
    public var maxMessageBytes: Int

    /// Maximum cumulative container element count across arrays and maps (default: 4,194,304).
    public var maxElements: Int

    /// Maximum cumulative allocation budget in bytes (default: 64 MiB).
    public var maxAllocBytes: Int

    /// Maximum allowed container and sub-message recursion depth (default: 32).
    public var maxDepth: Int

    public init(
        maxMessageBytes: Int = 64 * 1024 * 1024,
        maxElements: Int = 4_194_304,
        maxAllocBytes: Int = 64 * 1024 * 1024,
        maxDepth: Int = WireType.maxNestingDepth
    ) {
        self.maxMessageBytes = maxMessageBytes
        self.maxElements = maxElements
        self.maxAllocBytes = maxAllocBytes
        self.maxDepth = min(maxDepth, WireType.maxNestingDepth)
    }

    public static let `default` = DecodeOptions()
}

/// Mutable decode budget tracker shared across recursive decoding calls.
public struct DecodeBudget: Sendable {
    public let maxElements: Int
    public let maxAllocBytes: Int
    public let maxDepth: Int
    public var elements: Int = 0
    public var allocBytes: Int = 0

    @inlinable
    public init(options: DecodeOptions = .default) {
        self.maxElements = options.maxElements
        self.maxAllocBytes = options.maxAllocBytes
        self.maxDepth = min(options.maxDepth, WireType.maxNestingDepth)
    }

    @inlinable
    @inline(__always)
    public mutating func addElements(_ count: Int) throws {
        let (next, overflow) = elements.addingReportingOverflow(count)
        if overflow || next > maxElements {
            throw OmniBufError.allocationLimitExceeded(
                "element count \(next) exceeds maxElements \(maxElements)"
            )
        }
        elements = next
    }

    @inlinable
    @inline(__always)
    public mutating func addAlloc(_ bytes: Int) throws {
        let (next, overflow) = allocBytes.addingReportingOverflow(bytes)
        if overflow || next > maxAllocBytes {
            throw OmniBufError.allocationLimitExceeded(
                "allocation \(next) exceeds maxAllocBytes \(maxAllocBytes)"
            )
        }
        allocBytes = next
    }
}
