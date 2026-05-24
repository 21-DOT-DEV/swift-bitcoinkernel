//
//  Context.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A kernel context — the root runtime object for every validation operation.
///
/// Holds chain parameters (``ChainParameters``), optional
/// ``NotificationCallbacks`` and ``ValidationInterfaceCallbacks``, and the
/// interrupt flag that ``interrupt()`` toggles. A ``ChainstateManager``
/// takes a context by reference, so one context can back multiple managers
/// — typical applications use a single long-lived context per process.
///
/// The kernel documents contexts as thread-safe for use from multiple
/// threads simultaneously. Create once, share freely.
///
/// Wraps the opaque `btck_Context` type; `deinit` calls
/// `btck_context_destroy` when the last Swift reference drops.
public final class Context: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a new kernel context.
    ///
    /// - Parameter options: Configuration options. Pass `nil` (the default)
    ///   for a mainnet context with no callbacks — suitable for quick
    ///   experiments but not for any real use where you need to know about
    ///   new tips, validation failures, or log output.
    /// - Throws: ``KernelError/contextCreationFailed`` if the C API returns
    ///   null. The kernel does not expose a reason; re-run under kernel
    ///   logging (see ``LoggingConnection``) to see what went wrong.
    public init(options: ContextOptions? = nil) throws {
        guard let ptr = btck_context_create(options?.pointer) else {
            throw KernelError.contextCreationFailed
        }
        self.pointer = ptr
    }

    /// Interrupts long-running validation operations — reindex, block
    /// import, `ChainstateManager.processBlock`.
    ///
    /// Safe to call from any thread. Signals the kernel to stop at the next
    /// safe checkpoint; interruption is cooperative — a call in flight
    /// completes the current step before unwinding. Used by
    /// ``BlockchainSync`` to stop sync on consumer cancel.
    ///
    /// - Returns: `true` if the kernel accepted the interrupt signal. `false`
    ///   indicates the kernel rejected the request (typically because no
    ///   interruptible operation was in flight).
    public func interrupt() -> Bool {
        btck_context_interrupt(pointer) == 0
    }

    deinit {
        btck_context_destroy(pointer)
    }
}
