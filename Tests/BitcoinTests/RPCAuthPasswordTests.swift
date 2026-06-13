//
//  RPCAuthPasswordTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import Bitcoin

// MARK: - RPCAuth(username:password:) generation

@Suite("RPCAuth Password Generation")
struct RPCAuthPasswordTests {

    /// Known-answer vectors computed with Bitcoin Core's own algorithm:
    /// `HMAC-SHA256(key = utf8(salt hex string), message = utf8(password))`
    /// (see `share/rpcauth/rpcauth.py:20-22`).
    @Test("HMAC matches rpcauth.py known-answer vectors")
    func knownAnswer() {
        #expect(
            RPCAuth.hmacHex(salt: "0102030405060708090a0b0c0d0e0f10", password: "swordfish")
                == "ae438e27e5b926f27851ceb6039188372764ebf01b7586290d45b61bf08704a0")
        #expect(
            RPCAuth.hmacHex(salt: "deadbeefdeadbeefdeadbeefdeadbeef", password: "correct horse battery staple")
                == "9ff158646c9da5849c54ddcd4a22636b4ba030b70afd4eae7e49b8faf7b8ebe4")
        // The package's long-standing demo credentials (user "111" / pass "222").
        #expect(
            RPCAuth.hmacHex(salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b", password: "222")
                == "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4")
    }

    @Test("init(username:password:) round-trips through the rawValue parser")
    func roundTrip() {
        let auth = RPCAuth(username: "alice", password: "s3cret!")
        #expect(auth.username == "alice")
        #expect(auth.salt.count == 32)          // 16 random bytes, hex
        #expect(auth.passwordHMAC.count == 64)  // 32 HMAC bytes, hex

        // rawValue (the `-rpcauth=` argument the daemon consumes) parses back
        // to the same fields via the existing parser.
        let parsed = RPCAuth(rawString: auth.rawValue)
        #expect(parsed?.username == "alice")
        #expect(parsed?.salt == auth.salt)
        #expect(parsed?.passwordHMAC == auth.passwordHMAC)

        // The HMAC is reproducible for the generated salt and password.
        #expect(RPCAuth.hmacHex(salt: auth.salt, password: "s3cret!") == auth.passwordHMAC)
    }

    @Test("salt is random across instances")
    func saltIsRandom() {
        let a = RPCAuth(username: "u", password: "p")
        let b = RPCAuth(username: "u", password: "p")
        #expect(a.salt != b.salt)
        #expect(a.passwordHMAC != b.passwordHMAC)  // different salt yields a different HMAC
    }
}
