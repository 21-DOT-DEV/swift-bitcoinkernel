internal import libbitcoinkernel

/// Options for creating a kernel context.
///
/// A builder object — configure it, then pass to ``Context/init(options:)``.
/// Not thread-safe; use from a single thread before creating the context.
///
/// Wraps the opaque `btck_ContextOptions` type. ARC via `deinit` calls
/// `btck_context_options_destroy` when the last reference drops.
public final class ContextOptions {
    let pointer: OpaquePointer

    /// Creates empty context options with default values.
    public init() {
        self.pointer = btck_context_options_create()
    }

    /// Sets the chain parameters for the context to be created.
    ///
    /// The C API copies the parameters internally — `params` may be
    /// deallocated after this call returns.
    ///
    /// - Parameter params: The chain parameters to use.
    public func setChainParams(_ params: ChainParameters) {
        btck_context_options_set_chainparams(pointer, params.pointer)
    }

    /// Sets the notification callbacks for the context.
    ///
    /// The kernel takes ownership of the callback state. You may release
    /// your reference to `notifications` after this call.
    ///
    /// - Parameter notifications: The notification callbacks.
    public func setNotifications(_ notifications: NotificationCallbacks) {
        btck_context_options_set_notifications(pointer, notifications.makeCCallbacks())
    }

    /// Sets the validation interface callbacks for the context.
    ///
    /// The kernel takes ownership of the callback state. You may release
    /// your reference to `callbacks` after this call.
    ///
    /// - Parameter callbacks: The validation interface callbacks.
    public func setValidationInterface(_ callbacks: ValidationInterfaceCallbacks) {
        btck_context_options_set_validation_interface(pointer, callbacks.makeCCallbacks())
    }

    deinit {
        btck_context_options_destroy(pointer)
    }
}
