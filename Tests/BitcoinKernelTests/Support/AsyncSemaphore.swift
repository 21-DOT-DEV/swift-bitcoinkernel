//
//  AsyncSemaphore.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A minimal FIFO async counting semaphore.
///
/// Used by ``KernelSerializationTrait`` to run kernel-touching tests one at a
/// time. The usual mutual-exclusion primitives don't fit an `async` test body:
/// `Synchronization.Mutex` can't be held across an `await`, and an actor is
/// reentrant — an `await` inside an actor method lets another call interleave,
/// so it won't serialize work that suspends. A counting semaphore backed by
/// continuations is the standard tool for "run these async closures serially."
///
/// - Note: A task cancelled while parked in ``wait()`` leaves its continuation
///   un-resumed. That only happens when the whole run is tearing down (at which
///   point the process exits), so it's not handled here.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.permits = value
    }

    /// Acquire a permit, suspending until one is available.
    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Release a permit, waking the longest-waiting caller if any.
    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            // Hand the permit directly to the next waiter (don't bump the
            // count) so it resumes already holding it.
            waiters.removeFirst().resume()
        }
    }
}
