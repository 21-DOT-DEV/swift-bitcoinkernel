import libbitcoinkernel

/// Minimal Swift wrapper around the libbitcoinkernel C API.
public struct BitcoinKernel: Sendable {

    /// Creates a kernel context with default options and immediately destroys it.
    /// Returns true if the context was created successfully.
    @discardableResult
    public static func verify() -> Bool {
        guard let context = btck_context_create(nil) else { return false }
        btck_context_destroy(context)
        return true
    }
}
