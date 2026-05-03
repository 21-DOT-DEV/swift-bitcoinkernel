import Foundation

/// Errors thrown by ``BlockSource`` conformers.
///
/// Covers the five common failure modes of fetching blockchain data from a
/// remote source: malformed responses, missing data, unsupported operations,
/// rate-limiting, and transport-layer failures. Designed so that a single
/// `catch let error as BlockSourceError` in calling code is sufficient to
/// handle every source-side failure category.
///
/// Inside ``BlockchainSync``, any `BlockSourceError` thrown from a conformer
/// is re-surfaced to the caller as a terminal
/// ``BlockchainSync/Update/State-swift.enum/failed(_:)`` update carrying the
/// error's localized description — the sequence itself does not throw.
public enum BlockSourceError: Error, Sendable {
    /// The source returned a response the client could not parse.
    ///
    /// The associated value describes what was malformed — e.g.
    /// `"expected numeric height, got 'not-a-number'"` or
    /// `"HTTP 500 after 5 attempt(s)"`. Treat the message as human-readable
    /// diagnostic, not machine-parseable.
    case invalidResponse(String)

    /// The requested block, header, or height is not available on this
    /// source.
    ///
    /// Mapped from HTTP 404 for ``EsploraBlockSource``. Never retried — the
    /// resource is definitively absent rather than transiently unavailable.
    case notFound

    /// The source does not implement the requested method.
    ///
    /// Reserved for conformers that deliberately decline specific methods
    /// (e.g., a "headers-only" source that declines ``BlockSource/block(for:)``).
    /// ``EsploraBlockSource`` never throws this — every method is supported.
    case notSupported

    /// The source is rate-limiting the client. Surfaces only after all
    /// built-in retries have been exhausted.
    ///
    /// - Parameter retryAfter: The server-hinted wait duration, parsed from
    ///   the `Retry-After` response header per
    ///   [RFC 9110 §10.2.3](https://www.rfc-editor.org/rfc/rfc9110#section-10.2.3),
    ///   if the response carried one. `nil` when the server did not provide
    ///   a hint.
    case rateLimited(retryAfter: Duration?)

    /// A transport-layer error occurred: DNS failure, TCP connection drop,
    /// TLS handshake failure, timeout, etc.
    ///
    /// - Parameter underlying: The underlying `Error` from the transport
    ///   stack — for ``EsploraBlockSource`` this is a `URLError` with the
    ///   original `URLError.Code` preserved.
    case network(underlying: any Error)
}

extension BlockSourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let details):
            return "Block source returned an invalid response: \(details)"
        case .notFound:
            return "The requested block was not found at the source."
        case .notSupported:
            return "The block source does not support this operation."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "The block source is rate-limiting requests. Retry after \(retryAfter)."
            } else {
                return "The block source is rate-limiting requests."
            }
        case .network(let underlying):
            return "Network error while contacting block source: \(underlying.localizedDescription)"
        }
    }
}
