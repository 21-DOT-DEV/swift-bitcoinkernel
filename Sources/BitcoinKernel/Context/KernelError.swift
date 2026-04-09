/// Errors from the Bitcoin kernel C API.
///
/// The kernel C API does not provide detailed error information — functions
/// return `NULL` on failure with no error code or message.
public enum KernelError: Error, Sendable {
    /// `btck_context_create` returned null.
    case contextCreationFailed
    /// `btck_logging_connection_create` returned null.
    case loggingConnectionFailed
    /// `btck_transaction_create` returned null (invalid serialized data).
    case transactionCreationFailed
    /// `btck_block_create` returned null (invalid serialized data).
    case blockCreationFailed
    /// `btck_block_header_create` returned null (invalid serialized data).
    case blockHeaderCreationFailed
    /// `btck_precomputed_transaction_data_create` returned null.
    case precomputedDataCreationFailed
    /// `btck_chainstate_manager_options_create` returned null.
    case chainstateManagerOptionsCreationFailed
    /// `btck_chainstate_manager_create` returned null.
    case chainstateManagerCreationFailed
}
