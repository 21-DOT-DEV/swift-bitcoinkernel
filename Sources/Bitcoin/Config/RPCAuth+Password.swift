//
//  RPCAuth+Password.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import bitcoind

// MARK: - Password-based RPCAuth generation

extension RPCAuth {

    /// Creates RPC credentials from a username and plaintext password.
    ///
    /// Generates a random salt and computes the HMAC the way Bitcoin Core's
    /// `share/rpcauth/rpcauth.py` does, so ``rawValue`` is a valid `-rpcauth=`
    /// argument. Use this when you have a password and want the matching
    /// credential without running the Python helper.
    ///
    /// The plaintext password is not stored; keep it to authenticate the RPC
    /// client (for example ``RPCClient/init(url:username:password:)``).
    ///
    /// - Parameters:
    ///   - username: The RPC username.
    ///   - password: The plaintext RPC password.
    public init(username: String, password: String) {
        let salt = Self.randomSaltHex()
        self.init(
            username: username,
            salt: salt,
            passwordHMAC: Self.hmacHex(salt: salt, password: password)
        )
    }

    /// 16 cryptographically random bytes as a 32-character lowercase hex
    /// string, matching `rpcauth.py`'s `token_hex(16)`.
    static func randomSaltHex() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return hex(bytes)
    }

    /// HMAC-SHA256 over the password, keyed by the UTF-8 bytes of the hex
    /// `salt` string (not the raw salt bytes — this is the `rpcauth.py`
    /// contract), returned as lowercase hex. Uses Bitcoin Core's vendored
    /// `CHMAC_SHA256` via the `bitcoind` bridge.
    static func hmacHex(salt: String, password: String) -> String {
        let key = Array(salt.utf8)
        let message = Array(password.utf8)
        var digest = [UInt8](repeating: 0, count: 32)
        key.withUnsafeBufferPointer { k in
            message.withUnsafeBufferPointer { m in
                digest.withUnsafeMutableBufferPointer { d in
                    bitcoin_hmac_sha256(k.baseAddress, k.count, m.baseAddress, m.count, d.baseAddress)
                }
            }
        }
        return hex(digest)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var chars = [UInt8]()
        chars.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            chars.append(digits[Int(byte >> 4)])
            chars.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: chars, as: UTF8.self)
    }
}
