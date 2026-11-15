//
//  SHA256DispatchTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import SHA256DispatchProbe

// `SHA256AutoDetect()` picks the fastest SHA-256 path the hardware supports and
// reports its name — the same string `kernel::Context` logs once per process.
// Calling it through the probe is deterministic, which grepping that log is not.
// A silent build regression (the `ENABLE_ARM_SHANI` define or the extraction
// entry lost in a future subtree sync) changes the arm64 answer from
// "arm_shani(1way;2way)" to "standard" while hashes stay correct — this test
// turns that silent slowdown into a loud failure. Correctness of every path is
// enforced inside `SHA256AutoDetect()` itself by `assert(SelfTest())`. The test
// carries `.kernelSerialized` so it can't overlap context-creating tests'
// `call_once` detect, the other writer of the dispatcher's globals; trait-less
// hashing tests can still race the rewrite — formally racy, benign on our
// targets (idempotent writes of equivalent, self-tested pointers).
@Test(.kernelSerialized) func sha256DispatchSelectsBestImplementation() {
    let name = String(cString: SHA256DispatchProbeSelectedImplementation())
#if (os(macOS) || os(iOS) || os(tvOS) || os(visionOS)) && arch(arm64)
    // The os() list mirrors the platforms Package.swift scopes
    // ENABLE_ARM_SHANI to (Catalyst reports as os(iOS)); every Apple arm64
    // toolchain guarantees FEAT_SHA256, which the sysctl only confirms.
    #expect(name == "arm_shani(1way;2way)")
#elseif arch(x86_64)
    // compat/cpuid.h self-defines HAVE_GETCPUID on x86, so the SSE4 one-way
    // path has been live all along — Intel, Rosetta, and x86_64 Linux alike.
    // ENABLE_SSE41/AVX2/X86_SHANI (the multi-way paths) remain off.
    #expect(name == "sse4(1way)")
#else
    // Non-x86-64, non-Apple-arm64 — aarch64 Linux, i386, watchOS: either
    // ENABLE_ARM_SHANI is off or the SIMD path's dispatch compiles out.
    #expect(name == "standard")
#endif
}
