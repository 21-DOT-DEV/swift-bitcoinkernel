//
//  FakeTorSession.swift
//  21-DOT-DEV/Bitcoin
//
//  Shared test double for `TorSession`. Consumed by both
//  `NodeAppTests` and `KernelAppTests`; colocated in
//  `Sources/SharedTests/` so each target compiles its own internal copy
//  without duplicating source.
//
//  Copyright (c) 2026 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Tor

// MARK: - FakeTorSession

/// Test double for `TorSession` that blocks bootstrap until released.
///
/// Used to deterministically reach the race windows where
/// ``TorViewModel/stop()`` must cancel an in-flight `start()` Task before
/// it can write state, and where the auto-retry state machine must
/// schedule/cancel retries under rapid user input. Also the driver of
/// choice for any test that needs a `TorViewModel` to land in
/// ``TorViewModel/isReady`` without booting a real Tor daemon.
actor FakeTorSession: TorSession {

    enum Mode: Sendable {
        case blockUntilReleased
        case startThrows
    }

    private let mode: Mode
    private var bootstrapGate: CheckedContinuation<Void, Error>?
    private var bootstrapPreReleased = false
    private var eventContinuation: AsyncStream<TorEvent>.Continuation?

    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var bootstrapWasCancelled = false

    init(mode: Mode = .blockUntilReleased) {
        self.mode = mode
    }

    // MARK: TorSession

    var events: AsyncStream<TorEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    var socksEndpoint: HostPort? {
        HostPort(host: "127.0.0.1", port: 9050)
    }

    func start() async throws {
        startCalled = true
        if case .startThrows = mode {
            struct FakeStartError: Error {}
            throw FakeStartError()
        }
    }

    func waitUntilBootstrapped(timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                Task { await self.storeGate(cont) }
            }
        } onCancel: {
            Task { await self.cancelBootstrap() }
        }
    }

    func stop() async {
        stopCalled = true
        if let gate = bootstrapGate {
            gate.resume(throwing: CancellationError())
            bootstrapGate = nil
        }
        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: Test hooks

    private func storeGate(_ cont: CheckedContinuation<Void, Error>) {
        // Cancel-before-store race: if cancelBootstrap fired before this
        // task reached the actor, resume immediately with CancellationError
        // instead of leaking the continuation (Finding B round-2 review).
        if bootstrapWasCancelled {
            cont.resume(throwing: CancellationError())
            return
        }
        // Symmetric race for successful release: a test that calls
        // `releaseBootstrap()` right after observing `.starting` may beat
        // the async storeGate task to the actor. Honor the pre-release flag.
        if bootstrapPreReleased {
            cont.resume(returning: ())
            return
        }
        self.bootstrapGate = cont
    }

    private func cancelBootstrap() {
        bootstrapWasCancelled = true
        if let gate = bootstrapGate {
            gate.resume(throwing: CancellationError())
            bootstrapGate = nil
        }
    }

    /// Releases the bootstrap gate so `waitUntilBootstrapped()` returns normally.
    ///
    /// If called before `storeGate` has landed on the actor, sets a
    /// pre-release flag so the continuation is resumed immediately when it
    /// eventually stores. Mirrors the `bootstrapWasCancelled` contract.
    func releaseBootstrap() {
        if let gate = bootstrapGate {
            gate.resume(returning: ())
            bootstrapGate = nil
        } else {
            bootstrapPreReleased = true
        }
    }
}
