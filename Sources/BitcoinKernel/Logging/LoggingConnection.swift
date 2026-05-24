//
//  LoggingConnection.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A connection to the kernel's internal logging system.
///
/// ### Opt-in by construction
///
/// Kernel logging is dormant until you explicitly create a
/// ``LoggingConnection``: there is no default, always-on destination. An
/// application that does not want kernel log output simply never instantiates
/// one — no build flag required. This replaces the `DISABLE_KERNEL_LOGGING`
/// build-flag pattern some downstream projects have used; the equivalent
/// opt-out here is just to skip construction.
///
/// For belt-and-suspenders silence (skip the internal logger entirely),
/// call ``disableLogging()`` once at program startup before any connection
/// is created. After ``disableLogging()`` has been called, no further
/// connections can be created and kernel log writes become no-ops.
///
/// ### Buffering
///
/// Messages logged before a connection is created are buffered (up to 1 MB)
/// and delivered immediately when the first connection is established.
///
/// Wraps the opaque `btck_LoggingConnection` type. ARC via `deinit` calls
/// `btck_logging_connection_destroy` when the last reference drops.
public final class LoggingConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a logging connection that delivers messages through a callback.
    ///
    /// - Parameter callback: Called for each log message with the message string.
    /// - Throws: ``KernelError/loggingConnectionFailed`` if the C API returns null.
    public init(callback: @escaping (String) -> Void) throws {
        let context = Unmanaged.passRetained(callback as AnyObject).toOpaque()

        guard let ptr = btck_logging_connection_create(
            { userData, message, messageLen in
                guard let userData, let message else { return }
                let string = String(
                    decoding: UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(message)), count: messageLen),
                    as: UTF8.self
                )
                let cb = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue() as! (String) -> Void
                cb(string)
            },
            context,
            { userData in
                guard let userData else { return }
                Unmanaged<AnyObject>.fromOpaque(userData).release()
            }
        ) else {
            Unmanaged<AnyObject>.fromOpaque(context).release()
            throw KernelError.loggingConnectionFailed
        }
        self.pointer = ptr
    }

    deinit {
        btck_logging_connection_destroy(pointer)
    }
}

// MARK: - Global Logging Configuration

/// Disables the global internal logger permanently.
///
/// Must only be called once. Not thread-safe. Must not be called while a
/// ``LoggingConnection`` exists.
public func disableLogging() {
    btck_logging_disable()
}

/// Sets formatting options for the global internal logger.
///
/// - Parameters:
///   - timestamps: Prefix each log line with a timestamp.
///   - timeMicros: Include microseconds in the timestamp.
///   - threadNames: Include the originating thread's name.
///   - sourceLocations: Append the source-file location that emitted the line.
///   - alwaysPrintCategoryLevels: Always print the log category and level,
///     even for lines that wouldn't normally include them.
public func setLoggingOptions(
    timestamps: Bool = false,
    timeMicros: Bool = false,
    threadNames: Bool = false,
    sourceLocations: Bool = false,
    alwaysPrintCategoryLevels: Bool = false
) {
    var opts = btck_LoggingOptions()
    opts.log_timestamps = timestamps ? 1 : 0
    opts.log_time_micros = timeMicros ? 1 : 0
    opts.log_threadnames = threadNames ? 1 : 0
    opts.log_sourcelocations = sourceLocations ? 1 : 0
    opts.always_print_category_levels = alwaysPrintCategoryLevels ? 1 : 0
    btck_logging_set_options(opts)
}

/// Sets the log level for a specific category.
///
/// - Parameters:
///   - category: The log category to configure.
///   - level: The minimum log level for the category.
public func setLogLevel(category: LogCategory, level: LogLevel) {
    btck_logging_set_level_category(category.rawValue, level.rawValue)
}

/// Enables a specific log category.
///
/// - Parameter category: The category to enable. Use `.all` to enable all categories.
public func enableLogCategory(_ category: LogCategory) {
    btck_logging_enable_category(category.rawValue)
}

/// Disables a specific log category.
///
/// - Parameter category: The category to disable. Use `.all` to disable all categories.
public func disableLogCategory(_ category: LogCategory) {
    btck_logging_disable_category(category.rawValue)
}
