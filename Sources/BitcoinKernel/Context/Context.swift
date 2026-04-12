internal import libbitcoinkernel

/// A kernel context for validation operations.
///
/// The context holds chain parameters and callbacks. It can safely be used
/// from multiple threads simultaneously.
///
/// Wraps the opaque `btck_Context` type. ARC via `deinit` calls
/// `btck_context_destroy` when the last reference drops.
public final class Context: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a new kernel context.
    ///
    /// - Parameter options: Configuration options. Pass `nil` (the default) for
    ///   a mainnet context with no callbacks.
    /// - Throws: ``KernelError/contextCreationFailed`` if the C API returns null.
    public init(options: ContextOptions? = nil) throws {
        guard let ptr = btck_context_create(options?.pointer) else {
            throw KernelError.contextCreationFailed
        }
        self.pointer = ptr
    }

    /// Interrupts long-running validation operations such as reindexing,
    /// block importing, or block processing.
    ///
    /// This method is safe to call from any thread. It signals the kernel to
    /// stop ongoing work at the next safe checkpoint.
    ///
    /// - Returns: `true` if the interrupt was successful.
    public func interrupt() -> Bool {
        btck_context_interrupt(pointer) == 0
    }

    deinit {
        btck_context_destroy(pointer)
    }
}
