import Foundation

/// Errors from the Bitcoin kernel C API.
///
/// The kernel C API does not provide detailed error information — functions
/// return `NULL` on failure with no error code or message.
public enum KernelError: Error, Sendable, CaseIterable, Equatable, CustomStringConvertible, LocalizedError {
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

    public var description: String {
        switch self {
        case .contextCreationFailed:
            return "Kernel context creation failed."
        case .loggingConnectionFailed:
            return "Kernel logging connection creation failed."
        case .transactionCreationFailed:
            return "Transaction creation failed (invalid serialized data)."
        case .blockCreationFailed:
            return "Block creation failed (invalid serialized data)."
        case .blockHeaderCreationFailed:
            return "Block header creation failed (invalid serialized data)."
        case .precomputedDataCreationFailed:
            return "Precomputed transaction data creation failed."
        case .chainstateManagerOptionsCreationFailed:
            return "Chainstate manager options creation failed."
        case .chainstateManagerCreationFailed:
            return "Chainstate manager creation failed."
        }
    }

    public var errorDescription: String? { description }
}
