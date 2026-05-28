//
//  ContextOptions.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Builder for constructing a ``Context`` — configure, then pass to
/// ``Context/init(options:)``.
///
/// A one-shot builder: each setter replaces the previous value for that
/// property. Defaults produce a mainnet context with no callbacks (see
/// ``Context/init(options:)`` for the implications). Set the chain type
/// first, attach callbacks, then build the context.
///
/// - Warning: Not thread-safe. Configure on a single thread before creating
///   the context; the resulting ``Context`` is thread-safe but building
///   `ContextOptions` concurrently is undefined.
///
/// Wraps the opaque `btck_ContextOptions` type; `deinit` calls
/// `btck_context_options_destroy` when the last Swift reference drops.
public final class ContextOptions {
    let pointer: OpaquePointer

    /// Creates empty context options with default values — mainnet chain,
    /// no notification callbacks, no validation interface callbacks.
    public init() {
        self.pointer = btck_context_options_create()
    }

    /// Sets the chain parameters — determines which Bitcoin network the
    /// resulting ``Context`` validates against.
    ///
    /// The C API copies the parameters internally, so `params` may be
    /// deallocated after this call returns. Calling this replaces any
    /// previously-set chain parameters on the same options object.
    ///
    /// - Parameter params: Chain parameters, typically constructed via
    ///   ``ChainParameters/init(_:)`` from a ``ChainType``.
    public func setChainParams(_ params: ChainParameters) {
        btck_context_options_set_chainparams(pointer, params.pointer)
    }

    /// Attaches notification callbacks — tip updates, header tips, progress
    /// reports, warnings, and fatal errors.
    ///
    /// The kernel takes ownership of the callback state; you may release
    /// your Swift reference to `notifications` after this call returns.
    /// All callbacks are dispatched on kernel-internal threads — see
    /// ``NotificationCallbacks`` for the list and their semantics.
    ///
    /// - Parameter notifications: Preconfigured ``NotificationCallbacks``
    ///   with the closures you want invoked populated.
    public func setNotifications(_ notifications: NotificationCallbacks) {
        btck_context_options_set_notifications(pointer, notifications.makeCCallbacks())
    }

    /// Attaches validation interface callbacks — per-block validation,
    /// PoW confirmation, chain connect / disconnect events.
    ///
    /// The kernel takes ownership of the callback state. Validation
    /// callbacks fire on kernel-internal threads and **block further
    /// validation while executing**, so keep handlers fast and avoid
    /// synchronous I/O or long-running work inside them.
    ///
    /// - Parameter callbacks: Preconfigured ``ValidationInterfaceCallbacks``
    ///   with the closures you want invoked populated.
    public func setValidationInterface(_ callbacks: ValidationInterfaceCallbacks) {
        btck_context_options_set_validation_interface(pointer, callbacks.makeCCallbacks())
    }

    deinit {
        btck_context_options_destroy(pointer)
    }
}
