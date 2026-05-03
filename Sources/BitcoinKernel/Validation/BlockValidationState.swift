internal import libbitcoinkernel

/// The validation state of a block after processing — a (mode, result)
/// pair describing whether the kernel accepted the block and, if not, why.
///
/// Pass to ``ChainstateManager/processBlockHeader(_:state:)`` as an
/// out-parameter; the kernel populates it with the verdict. Read
/// ``validationMode`` for the high-level status and
/// ``blockValidationResult`` for the granular reason on rejection.
///
/// Wraps the opaque `btck_BlockValidationState` type; `deinit` calls
/// `btck_block_validation_state_destroy` when the last Swift reference
/// drops.
public final class BlockValidationState: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a new (empty) block validation state.
    public init() {
        self.pointer = btck_block_validation_state_create()
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The validation mode (valid, invalid, or internal error).
    public var validationMode: ValidationMode {
        let raw = btck_block_validation_state_get_validation_mode(pointer)
        return ValidationMode(rawValue: raw) ?? .internalError
    }

    /// The granular validation result explaining why a block was rejected.
    public var blockValidationResult: BlockValidationResult {
        let raw = btck_block_validation_state_get_block_validation_result(pointer)
        return BlockValidationResult(rawValue: raw) ?? .unset
    }

    deinit {
        btck_block_validation_state_destroy(pointer)
    }
}
