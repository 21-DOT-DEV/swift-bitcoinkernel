//
//  ScreenWakeControllerTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing

// `ScreenWakeController` lives in the shared source tree, which is compiled into
// both the NodeApp and KernelApp modules. This suite runs in both test targets;
// the conditional import binds to whichever app module is present.
#if canImport(NodeApp)
@testable import NodeApp
#elseif canImport(KernelApp)
@testable import KernelApp
#endif

@MainActor
struct ScreenWakeControllerTests {
    /// Escaping-closure sink for the injected begin/end effects.
    private final class Counter {
        var begins = 0
        var ends = 0
    }

    private func makeController(_ counter: Counter) -> ScreenWakeController {
        ScreenWakeController(
            onBegin: { counter.begins += 1 },
            onEnd: { counter.ends += 1 }
        )
    }

    @Test("Keeps awake only when enabled AND active")
    func awakeRequiresBoth() {
        let c = Counter()
        let controller = makeController(c)

        controller.update(enabled: false, isActive: false)
        controller.update(enabled: true, isActive: false)   // enabled, not on-screen
        controller.update(enabled: false, isActive: true)   // on-screen, not enabled
        #expect(c.begins == 0)

        controller.update(enabled: true, isActive: true)     // both → awake
        #expect(c.begins == 1)
        #expect(c.ends == 0)
    }

    @Test("Repeated on-calls hold exactly one activity; off releases once (no leak)")
    func idempotentNoLeak() {
        let c = Counter()
        let controller = makeController(c)

        controller.update(enabled: true, isActive: true)     // begin
        controller.update(enabled: true, isActive: true)     // no-op
        controller.update(enabled: true, isActive: true)     // no-op
        #expect(c.begins == 1)                                // began ONCE despite 3 on-calls
        #expect(c.ends == 0)

        controller.update(enabled: true, isActive: false)    // leaving front → release
        #expect(c.ends == 1)                                  // ended ONCE
        controller.update(enabled: false, isActive: false)   // no-op
        #expect(c.ends == 1)

        controller.update(enabled: true, isActive: true)     // back on → begin again
        #expect(c.begins == 2)
    }
}
