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

public enum Daemon {
    private static var task: Task<Void, Never>?

    /// Launch the daemon on a background task. Returns immediately.
    public static func start(_ arguments: [String]) {
        task = Task.detached {
            // Define your command-line arguments array
            let arguments: [String] = ["bitcoind"] + arguments

            // Convert the Swift strings to arrays of CChar, and keep them in scope to manage memory automatically
            let cStringArrays: [Array<CChar>] = arguments.map { Array($0.utf8CString) }

            // Convert the arrays of CChar to pointers to CChar
            var cStringPointers: [UnsafeMutablePointer<CChar>?] = cStringArrays.map {
                UnsafeMutablePointer(mutating: $0)
            }

            // Now, get an UnsafeMutablePointer to the array of pointers
            cStringPointers.withUnsafeMutableBufferPointer { buffer in
                let argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>! = UnsafeMutablePointer(mutating: buffer.baseAddress)

                // `argv` is now ready to use within this scope, and no need to use `free()`
                // For example, you could pass `argv` to a C function here
                print(entry(Int32(arguments.count), argv))
            }
        }
    }

    /// Signal the daemon to shut down and wait for it to finish.
    public static func stopAndWait() async {
        StartShutdown()
        await task?.value
        task = nil
    }

    /// Signal the daemon to shut down without waiting.
    public static func stop() {
        StartShutdown()
    }
}
