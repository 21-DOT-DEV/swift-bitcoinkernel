//
//  Daemon.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 Twenty Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import bitcoind
import Foundation

public enum Daemon {
    /// Signaled when the blocking `entry()` call returns.
    private static let finished = DispatchSemaphore(value: 0)

    /// Launch the daemon on a dedicated thread. Returns immediately.
    public static func start(_ arguments: [String]) {
        let arguments: [String] = ["bitcoind"] + arguments

        Thread.detachNewThread {
            // Convert the Swift strings to arrays of CChar, and keep them in scope to manage memory automatically
            let cStringArrays: [Array<CChar>] = arguments.map { Array($0.utf8CString) }

            // Convert the arrays of CChar to pointers to CChar
            var cStringPointers: [UnsafeMutablePointer<CChar>?] = cStringArrays.map {
                UnsafeMutablePointer(mutating: $0)
            }

            // Now, get an UnsafeMutablePointer to the array of pointers
            cStringPointers.withUnsafeMutableBufferPointer { buffer in
                let argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>! = UnsafeMutablePointer(mutating: buffer.baseAddress)
                print(entry(Int32(arguments.count), argv))
            }

            finished.signal()
        }
    }

    /// Block until the daemon's `entry()` call has fully returned.
    public static func waitUntilStopped() {
        finished.wait()
    }
}
