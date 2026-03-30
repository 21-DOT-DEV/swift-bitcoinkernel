//
//  ConfigTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

// MARK: - Network Types

@Suite("Network Types")
struct NetworkTypeTests {

    @Test("Mainnet has no flag")
    func mainnetFlag() {
        #expect(Mainnet.flag == nil)
    }

    @Test("Mainnet default ports")
    func mainnetPorts() {
        #expect(Mainnet.defaultP2PPort == 8333)
        #expect(Mainnet.defaultRPCPort == 8332)
    }

    @Test("Regtest has -regtest flag")
    func regtestFlag() {
        #expect(Regtest.flag == "-regtest")
    }

    @Test("Regtest default ports")
    func regtestPorts() {
        #expect(Regtest.defaultP2PPort == 18444)
        #expect(Regtest.defaultRPCPort == 18443)
    }

    @Test("Testnet4 has -testnet4 flag")
    func testnet4Flag() {
        #expect(Testnet4.flag == "-testnet4")
    }

    @Test("Testnet4 default ports")
    func testnet4Ports() {
        #expect(Testnet4.defaultP2PPort == 48333)
        #expect(Testnet4.defaultRPCPort == 48332)
    }

    @Test("Signet has -signet flag")
    func signetFlag() {
        #expect(Signet.flag == "-signet")
    }

    @Test("Regtest config prepends -regtest flag")
    func regtestConfigFlag() {
        let config = BitcoinConfig.regtest()
        #expect(config.arguments.first == "-regtest")
    }

    @Test("Mainnet config has no leading flag")
    func mainnetConfigNoFlag() {
        let config = BitcoinConfig.mainnet()
        #expect(!config.arguments.contains("-mainnet"))
        #expect(!config.arguments.contains(where: { $0.hasPrefix("-mainnet") }))
    }

    // COMPILE-TIME CHECKS (uncomment to verify phantom type enforcement):
    // let _ = BitcoinConfig.mainnet().fastPrune()          // ❌ should not compile
    // let _ = BitcoinConfig.regtest().signetChallenge("")  // ❌ should not compile
    // let _ = BitcoinConfig.regtest().fastPrune()          // ✅ should compile
}

// MARK: - Value Types

@Suite("Value Types")
struct ValueTypeTests {

    // IPAddress

    @Test("IPAddress.localhost is 127.0.0.1")
    func localhostAddress() {
        #expect(IPAddress.localhost.description == "127.0.0.1")
    }

    @Test("IPAddress.allInterfaces is 0.0.0.0")
    func allInterfacesAddress() {
        #expect(IPAddress.allInterfaces.description == "0.0.0.0")
    }

    @Test("IPAddress.loopbackIPv6 is ::1")
    func loopbackIPv6Address() {
        #expect(IPAddress.loopbackIPv6.description == "::1")
    }

    @Test("IPAddress string literal initialisation")
    func ipAddressStringLiteral() {
        let ip: IPAddress = "192.168.1.1"
        #expect(ip.description == "192.168.1.1")
    }

    @Test("IPAddress CIDR notation preserved")
    func ipAddressCIDR() {
        let ip: IPAddress = "192.168.1.0/24"
        #expect(ip.description == "192.168.1.0/24")
    }

    // RPCAuth

    @Test("RPCAuth rawValue round-trips")
    func rpcAuthRawValue() {
        let auth = RPCAuth(username: "alice", salt: "abc123", passwordHMAC: "def456")
        #expect(auth.rawValue == "alice:abc123$def456")
    }

    @Test("RPCAuth parses from raw string")
    func rpcAuthParse() throws {
        let auth = RPCAuth(rawString: "bob:salt99$hmacXYZ")
        let unwrapped = try #require(auth)
        #expect(unwrapped.username == "bob")
        #expect(unwrapped.salt == "salt99")
        #expect(unwrapped.passwordHMAC == "hmacXYZ")
    }

    @Test("RPCAuth round-trips through rawValue")
    func rpcAuthRoundTrip() throws {
        let original = RPCAuth(username: "111", salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b", passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4")
        let parsed = RPCAuth(rawString: original.rawValue)
        let roundTripped = try #require(parsed)
        #expect(roundTripped.username == original.username)
        #expect(roundTripped.salt == original.salt)
        #expect(roundTripped.passwordHMAC == original.passwordHMAC)
    }

    @Test("RPCAuth init fails on malformed string")
    func rpcAuthMalformed() {
        #expect(RPCAuth(rawString: "nodollar") == nil)
        #expect(RPCAuth(rawString: "nocolon$hmac") == nil)
        #expect(RPCAuth(rawString: "") == nil)
    }

    // PruneMode

    @Test("PruneMode.disabled rawValue is 0")
    func pruneModeDisabled() {
        #expect(PruneMode.disabled.rawValue == 0)
    }

    @Test("PruneMode.manual rawValue is 1")
    func pruneModeManual() {
        #expect(PruneMode.manual.rawValue == 1)
    }

    @Test("PruneMode.minimum is size(550)")
    func pruneModeMinimum() {
        if case .size(let mb) = PruneMode.minimum {
            #expect(mb == 550)
        } else {
            Issue.record("PruneMode.minimum should be .size(mb: 550)")
        }
        #expect(PruneMode.minimum.rawValue == 550)
    }

    @Test("PruneMode.size rawValue equals mb")
    func pruneModeSize() {
        #expect(PruneMode.size(mb: 1000).rawValue == 1000)
    }

    // BlockFilterMode

    @Test("BlockFilterMode descriptions")
    func blockFilterModeDescriptions() {
        #expect(BlockFilterMode.disabled.description == "0")
        #expect(BlockFilterMode.all.description == "1")
        #expect(BlockFilterMode.basic.description == "basic")
    }
}

// MARK: - Config Building

@Suite("Config Building")
struct ConfigBuildingTests {

    @Test("server() appends -server=1")
    func serverEnabled() {
        let args = BitcoinConfig.mainnet().server().arguments
        #expect(args.contains("-server=1"))
    }

    @Test("server(false) appends -server=0")
    func serverDisabled() {
        let args = BitcoinConfig.mainnet().server(false).arguments
        #expect(args.contains("-server=0"))
    }

    @Test("prune(.minimum) appends -prune=550")
    func pruneMinimum() {
        let args = BitcoinConfig.mainnet().prune(.minimum).arguments
        #expect(args.contains("-prune=550"))
    }

    @Test("prune(.disabled) appends -prune=0")
    func pruneDisabled() {
        let args = BitcoinConfig.mainnet().prune(.disabled).arguments
        #expect(args.contains("-prune=0"))
    }

    @Test("rpcBind appends -rpcbind=")
    func rpcBind() {
        let args = BitcoinConfig.mainnet().rpcBind(.allInterfaces).arguments
        #expect(args.contains("-rpcbind=0.0.0.0"))
    }

    @Test("rpcAuth appends -rpcauth= with rawValue")
    func rpcAuth() {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let args = BitcoinConfig.mainnet().rpcAuth(auth).arguments
        #expect(args.contains("-rpcauth=u:s$h"))
    }

    @Test("rpcAllowIP called twice produces two args")
    func rpcAllowIPMultiValue() {
        let args = BitcoinConfig.mainnet()
            .rpcAllowIP(.localhost)
            .rpcAllowIP("192.168.1.0/24")
            .arguments
        let allowArgs = args.filter { $0.hasPrefix("-rpcallowip=") }
        #expect(allowArgs.count == 2)
        #expect(allowArgs.contains("-rpcallowip=127.0.0.1"))
        #expect(allowArgs.contains("-rpcallowip=192.168.1.0/24"))
    }

    @Test("dbCache clamps to minimum 4")
    func dbCacheClamp() {
        let args = BitcoinConfig.mainnet().dbCache(2).arguments
        #expect(args.contains("-dbcache=4"))
    }

    @Test("rpcThreads clamps to 1-64 range")
    func rpcThreadsClamp() {
        let tooLow = BitcoinConfig.mainnet().rpcThreads(0).arguments
        let tooHigh = BitcoinConfig.mainnet().rpcThreads(100).arguments
        #expect(tooLow.contains("-rpcthreads=1"))
        #expect(tooHigh.contains("-rpcthreads=64"))
    }

    @Test("fluent chain produces correct argument order")
    func fluentChain() {
        let config = BitcoinConfig.mainnet()
            .server()
            .rpcBind(.allInterfaces)
            .rpcAllowIP(.localhost)
            .rpcPort(8332)
        let args = config.arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-rpcbind=0.0.0.0"))
        #expect(args.contains("-rpcallowip=127.0.0.1"))
        #expect(args.contains("-rpcport=8332"))
    }

    @Test("regtest() prepends -regtest before other args")
    func regtestPrepended() {
        let args = BitcoinConfig.regtest().server().arguments
        #expect(args.first == "-regtest")
        #expect(args.contains("-server=1"))
    }

    @Test("fastPrune compiles on Regtest")
    func fastPruneRegtest() {
        let args = BitcoinConfig.regtest().fastPrune().arguments
        #expect(args.contains("-fastprune=1"))
    }

    @Test("signetChallenge compiles on Signet")
    func signetChallengeSignet() {
        let args = BitcoinConfig.signet().signetChallenge("51").arguments
        #expect(args.contains("-signetchallenge=51"))
    }

    @Test("assumeValid() appends -assumevalid=")
    func assumeValidArg() {
        let hash = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        let args = BitcoinConfig.mainnet().assumeValid(hash).arguments
        #expect(args.contains("-assumevalid=\(hash)"))
    }

    @Test("assumeValid(\"0\") disables optimization")
    func assumeValidDisabled() {
        let args = BitcoinConfig.mainnet().assumeValid("0").arguments
        #expect(args.contains("-assumevalid=0"))
    }

    @Test("persistMempool() appends -persistmempool=1")
    func persistMempoolEnabled() {
        let args = BitcoinConfig.mainnet().persistMempool().arguments
        #expect(args.contains("-persistmempool=1"))
    }

    @Test("persistMempool(false) appends -persistmempool=0")
    func persistMempoolDisabled() {
        let args = BitcoinConfig.mainnet().persistMempool(false).arguments
        #expect(args.contains("-persistmempool=0"))
    }

    @Test("peerBloomFilters() appends -peerbloomfilters=1")
    func peerBloomFiltersEnabled() {
        let args = BitcoinConfig.mainnet().peerBloomFilters().arguments
        #expect(args.contains("-peerbloomfilters=1"))
    }

    @Test("peerBloomFilters(false) appends -peerbloomfilters=0")
    func peerBloomFiltersDisabled() {
        let args = BitcoinConfig.mainnet().peerBloomFilters(false).arguments
        #expect(args.contains("-peerbloomfilters=0"))
    }

    @Test("loadBlock() appends -loadblock=")
    func loadBlockArg() {
        let args = BitcoinConfig.mainnet().loadBlock("/path/to/blk00000.dat").arguments
        #expect(args.contains("-loadblock=/path/to/blk00000.dat"))
    }

    @Test("loadBlock() called twice produces two -loadblock= args")
    func loadBlockMultiValue() {
        let args = BitcoinConfig.mainnet()
            .loadBlock("/path/to/blk00000.dat")
            .loadBlock("/path/to/blk00001.dat")
            .arguments
        #expect(args.filter { $0.hasPrefix("-loadblock=") }.count == 2)
    }

    @Test(".raw() appends verbatim argument")
    func rawArgument() {
        let args = BitcoinConfig.mainnet().raw("-someunknownoption=1").arguments
        #expect(args.contains("-someunknownoption=1"))
    }
}

// MARK: - Config Validation

@Suite("Config Validation")
struct ConfigValidationTests {

    @Test("txIndex + prune(.size) throws txIndexWithPrune")
    func txIndexWithPrune() throws {
        let config = BitcoinConfig.mainnet().txIndex().prune(.minimum)
        #expect(throws: ConfigError.txIndexWithPrune) {
            try config.validate()
        }
    }

    @Test("txIndex(false) + prune(.size) does NOT throw")
    func txIndexFalseWithPrune() throws {
        let config = BitcoinConfig.mainnet().txIndex(false).prune(.minimum)
        let warnings = try config.validate()
        #expect(!warnings.contains(.missingRPCAuth))
    }

    @Test("coinStatsIndex + prune(.size) throws coinStatsIndexWithPrune")
    func coinStatsIndexWithPrune() {
        let config = BitcoinConfig.mainnet().coinStatsIndex().prune(.minimum)
        #expect(throws: ConfigError.coinStatsIndexWithPrune) {
            try config.validate()
        }
    }

    @Test("txIndex + prune(.disabled) does NOT throw")
    func txIndexWithPruneDisabled() throws {
        let config = BitcoinConfig.mainnet().txIndex().prune(.disabled)
        let warnings = try config.validate()
        _ = warnings
    }

    @Test("rpcBind without rpcAllowIP produces warning")
    func rpcBindWithoutAllowIP() throws {
        let config = BitcoinConfig.mainnet().rpcBind(.allInterfaces)
        let warnings = try config.validate()
        #expect(warnings.contains(.rpcBindWithoutAllowIP))
    }

    @Test("rpcBind with rpcAllowIP produces no bind warning")
    func rpcBindWithAllowIP() throws {
        let config = BitcoinConfig.mainnet().rpcBind(.allInterfaces).rpcAllowIP(.localhost)
        let warnings = try config.validate()
        #expect(!warnings.contains(.rpcBindWithoutAllowIP))
    }

    @Test("server(true) without rpcAuth produces missingRPCAuth warning")
    func serverWithoutRPCAuth() throws {
        let config = BitcoinConfig.mainnet().server()
        let warnings = try config.validate()
        #expect(warnings.contains(.missingRPCAuth))
    }

    @Test("server(true) with rpcAuth produces no missingRPCAuth warning")
    func serverWithRPCAuth() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet().server().rpcAuth(auth)
        let warnings = try config.validate()
        #expect(!warnings.contains(.missingRPCAuth))
    }

    @Test("blocksOnly + maxMempool produces warning")
    func blocksOnlyWithMaxMempool() throws {
        let config = BitcoinConfig.mainnet().blocksOnly().maxMempool(300)
        let warnings = try config.validate()
        #expect(warnings.contains(.blocksOnlyWithMaxMempool))
    }

    @Test("rpcBind without server produces serverDisabledWithRPCOptions warning")
    func serverDisabledWithRPCBind() throws {
        let config = BitcoinConfig.mainnet().rpcBind(.localhost)
        let warnings = try config.validate()
        #expect(warnings.contains(.serverDisabledWithRPCOptions))
    }

    @Test("rpcAuth without server produces serverDisabledWithRPCOptions warning")
    func serverDisabledWithRPCAuth() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet().rpcAuth(auth)
        let warnings = try config.validate()
        #expect(warnings.contains(.serverDisabledWithRPCOptions))
    }

    @Test("server(true) with rpcBind produces no serverDisabledWithRPCOptions warning")
    func serverEnabledWithRPCBind() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet().server().rpcBind(.localhost).rpcAllowIP(.localhost).rpcAuth(auth)
        let warnings = try config.validate()
        #expect(!warnings.contains(.serverDisabledWithRPCOptions))
    }

    @Test("clean config produces no errors or warnings")
    func cleanConfig() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet()
            .server()
            .rpcBind(.allInterfaces)
            .rpcAllowIP(.localhost)
            .rpcAuth(auth)
        let warnings = try config.validate()
        #expect(warnings.isEmpty)
    }
}

// MARK: - Config Presets

@Suite("Config Presets")
struct ConfigPresetTests {

    let auth = RPCAuth(username: "111", salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b", passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4")

    @Test("prunedDefault produces expected args")
    func prunedDefault() {
        let args = BitcoinConfig.prunedDefault(rpcAuth: auth).arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-rpcbind=0.0.0.0"))
        #expect(args.contains("-rpcallowip=127.0.0.1"))
        #expect(args.contains("-rpcport=8332"))
        #expect(args.contains("-prune=550"))
        #expect(args.contains("-blockfilterindex=1"))
    }

    @Test("prunedDefault validates without errors")
    func prunedDefaultValidation() throws {
        let warnings = try BitcoinConfig.prunedDefault(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }

    @Test("regtestDefault prepends -regtest")
    func regtestDefault() {
        let args = BitcoinConfig.regtestDefault(rpcAuth: auth).arguments
        #expect(args.first == "-regtest")
        #expect(args.contains("-server=1"))
        #expect(args.contains("-rpcbind=127.0.0.1"))
        #expect(args.contains("-rpcallowip=127.0.0.1"))
        #expect(args.contains("-rpcport=18443"))
    }

    @Test("regtestDefault validates without errors")
    func regtestDefaultValidation() throws {
        let warnings = try BitcoinConfig.regtestDefault(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }

    @Test("fullNode produces expected args")
    func fullNode() {
        let args = BitcoinConfig.fullNode(rpcAuth: auth).arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-txindex=1"))
        #expect(args.contains("-dbcache=4000"))
    }

    @Test("fullNode validates without errors")
    func fullNodeValidation() throws {
        let warnings = try BitcoinConfig.fullNode(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }

    @Test("lowBandwidth produces expected args")
    func lowBandwidth() {
        let args = BitcoinConfig.lowBandwidth(rpcAuth: auth).arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-prune=550"))
        #expect(args.contains("-maxconnections=8"))
        #expect(args.contains("-maxuploadtarget=500"))
        #expect(args.contains("-dnsseed=0"))
    }

    @Test("torNode produces expected args")
    func torNode() {
        let args = BitcoinConfig.torNode(rpcAuth: auth).arguments
        #expect(args.contains("-proxy=127.0.0.1:9050"))
        #expect(args.contains("-onion=127.0.0.1:9050"))
        #expect(args.contains("-onlynet=onion"))
        #expect(args.contains("-listen=0"))
        #expect(args.contains("-prune=550"))
    }

    @Test("raspberryPi produces expected args")
    func raspberryPi() {
        let args = BitcoinConfig.raspberryPi(rpcAuth: auth).arguments
        #expect(args.contains("-prune=550"))
        #expect(args.contains("-dbcache=150"))
        #expect(args.contains("-maxconnections=40"))
        #expect(args.contains("-maxmempool=50"))
        #expect(args.contains("-par=1"))
    }

    @Test("lightningEclair produces expected args")
    func lightningEclair() {
        let args = BitcoinConfig.lightningEclair(rpcAuth: auth).arguments
        #expect(args.contains("-txindex=1"))
        #expect(args.contains("-blockfilterindex=1"))
        #expect(args.contains("-rpcport=8332"))
    }

    @Test("lightningEclair validates without errors")
    func lightningEclairValidation() throws {
        let warnings = try BitcoinConfig.lightningEclair(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }
}

// MARK: - Phase 2: Value Types

@Suite("Phase 2 Value Types")
struct Phase2ValueTypeTests {

    @Test("FeeRate.satoshisPerByte(1) equals 0.00001 BTC/kvB")
    func feeRateSatPerByte() {
        let rate = FeeRate.satoshisPerByte(1)
        #expect(rate.description == "0.00001")
    }

    @Test("FeeRate.btcPerKvB preserves value")
    func feeRateBtcPerKvB() {
        let rate = FeeRate.btcPerKvB(0.0001)
        #expect(rate.description == "0.0001")
    }

    @Test("FeeRate zero is valid")
    func feeRateZero() {
        let rate = FeeRate.btcPerKvB(0)
        #expect(rate.description == "0")
    }

    @Test("NetworkType rawValues")
    func networkTypeRawValues() {
        #expect(NetworkType.ipv4.rawValue == "ipv4")
        #expect(NetworkType.ipv6.rawValue == "ipv6")
        #expect(NetworkType.onion.rawValue == "onion")
        #expect(NetworkType.i2p.rawValue == "i2p")
        #expect(NetworkType.cjdns.rawValue == "cjdns")
    }

    @Test("AddressType rawValues")
    func addressTypeRawValues() {
        #expect(AddressType.legacy.rawValue == "legacy")
        #expect(AddressType.p2shSegwit.rawValue == "p2sh-segwit")
        #expect(AddressType.bech32.rawValue == "bech32")
        #expect(AddressType.bech32m.rawValue == "bech32m")
    }
}

// MARK: - Phase 2: Network Option Building

@Suite("Phase 2 Network Options")
struct Phase2NetworkOptionTests {

    @Test("connect() appends -connect= arg and sets flag")
    func connectArg() {
        let args = BitcoinConfig.mainnet().connect("192.168.1.100").arguments
        #expect(args.contains("-connect=192.168.1.100"))
    }

    @Test("connect() called twice produces two -connect= args")
    func connectMultiValue() {
        let args = BitcoinConfig.mainnet()
            .connect("peer1.example.com")
            .connect("peer2.example.com")
            .arguments
        let connectArgs = args.filter { $0.hasPrefix("-connect=") }
        #expect(connectArgs.count == 2)
    }

    @Test("onlyNet(.onion) appends -onlynet=onion")
    func onlyNetOnion() {
        let args = BitcoinConfig.mainnet().onlyNet(.onion).arguments
        #expect(args.contains("-onlynet=onion"))
    }

    @Test("onlyNet called twice produces two -onlynet= args")
    func onlyNetMultiValue() {
        let args = BitcoinConfig.mainnet()
            .onlyNet(.ipv4)
            .onlyNet(.ipv6)
            .arguments
        let netArgs = args.filter { $0.hasPrefix("-onlynet=") }
        #expect(netArgs.count == 2)
    }

    @Test("peerBlockFilters appends -peerblockfilters=1")
    func peerBlockFiltersArg() {
        let args = BitcoinConfig.mainnet().peerBlockFilters().arguments
        #expect(args.contains("-peerblockfilters=1"))
    }

    @Test("listen(true) appends -listen=1")
    func listenEnabled() {
        let args = BitcoinConfig.mainnet().listen(true).arguments
        #expect(args.contains("-listen=1"))
    }

    @Test("maxUploadTarget appends -maxuploadtarget=")
    func maxUploadTargetArg() {
        let args = BitcoinConfig.mainnet().maxUploadTarget(200).arguments
        #expect(args.contains("-maxuploadtarget=200"))
    }

    @Test("proxy appends -proxy=")
    func proxyArg() {
        let args = BitcoinConfig.mainnet().proxy("127.0.0.1:9050").arguments
        #expect(args.contains("-proxy=127.0.0.1:9050"))
    }

    @Test("addNode multi-value")
    func addNodeMultiValue() {
        let args = BitcoinConfig.mainnet()
            .addNode("node1.example.com")
            .addNode("node2.example.com")
            .arguments
        #expect(args.filter { $0.hasPrefix("-addnode=") }.count == 2)
    }
}

// MARK: - Phase 2: Wallet Option Building

@Suite("Phase 2 Wallet Options")
struct Phase2WalletOptionTests {

    @Test("disableWallet appends -disablewallet=1")
    func disableWalletArg() {
        let args = BitcoinConfig.mainnet().disableWallet().arguments
        #expect(args.contains("-disablewallet=1"))
    }

    @Test("addressType(.bech32) appends -addresstype=bech32")
    func addressTypeArg() {
        let args = BitcoinConfig.mainnet().addressType(.bech32).arguments
        #expect(args.contains("-addresstype=bech32"))
    }

    @Test("addressType(.p2shSegwit) appends correct raw value")
    func addressTypeP2SHSegwit() {
        let args = BitcoinConfig.mainnet().addressType(.p2shSegwit).arguments
        #expect(args.contains("-addresstype=p2sh-segwit"))
    }

    @Test("walletRbf appends -walletrbf=1")
    func walletRbfArg() {
        let args = BitcoinConfig.mainnet().walletRbf().arguments
        #expect(args.contains("-walletrbf=1"))
    }

    @Test("wallet() multi-value")
    func walletMultiValue() {
        let args = BitcoinConfig.mainnet()
            .wallet("wallet1.dat")
            .wallet("wallet2.dat")
            .arguments
        #expect(args.filter { $0.hasPrefix("-wallet=") }.count == 2)
    }

    @Test("minTxFee appends fee rate arg")
    func minTxFeeArg() {
        let args = BitcoinConfig.mainnet().minTxFee(.satoshisPerByte(1)).arguments
        #expect(args.contains("-mintxfee=0.00001"))
    }

    @Test("txConfirmTarget clamps to minimum 1")
    func txConfirmTargetClamp() {
        let args = BitcoinConfig.mainnet().txConfirmTarget(0).arguments
        #expect(args.contains("-txconfirmtarget=1"))
    }
}

// MARK: - Phase 2: Relay Option Building

@Suite("Phase 2 Relay Options")
struct Phase2RelayOptionTests {

    @Test("minRelayTxFee appends fee rate arg")
    func minRelayTxFeeArg() {
        let args = BitcoinConfig.mainnet().minRelayTxFee(.satoshisPerByte(1)).arguments
        #expect(args.contains("-minrelaytxfee=0.00001"))
    }

    @Test("dataCarrier(false) appends -datacarrier=0")
    func dataCarrierDisabled() {
        let args = BitcoinConfig.mainnet().dataCarrier(false).arguments
        #expect(args.contains("-datacarrier=0"))
    }

    @Test("dataCarrierSize appends -datacarriersize=")
    func dataCarrierSizeArg() {
        let args = BitcoinConfig.mainnet().dataCarrierSize(40).arguments
        #expect(args.contains("-datacarriersize=40"))
    }

    @Test("dustRelayFee appends -dustrelayfee=")
    func dustRelayFeeArg() {
        let args = BitcoinConfig.mainnet().dustRelayFee(.satoshisPerByte(3)).arguments
        #expect(args.contains("-dustrelayfee=0.00003"))
    }

    @Test("limitAncestorCount clamps to minimum 1")
    func limitAncestorCountClamp() {
        let args = BitcoinConfig.mainnet().limitAncestorCount(0).arguments
        #expect(args.contains("-limitancestorcount=1"))
    }
}

// MARK: - Phase 2: Validation Rules

@Suite("Phase 2 Validation")
struct Phase2ValidationTests {

    @Test("peerBlockFilters without blockFilterIndex throws peerBlockFiltersWithoutIndex")
    func peerBlockFiltersWithoutIndex() {
        let config = BitcoinConfig.mainnet().peerBlockFilters()
        #expect(throws: ConfigError.peerBlockFiltersWithoutIndex) {
            try config.validate()
        }
    }

    @Test("peerBlockFilters with blockFilterIndex(.all) does NOT throw")
    func peerBlockFiltersWithIndex() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet()
            .server()
            .rpcAuth(auth)
            .peerBlockFilters()
            .blockFilterIndex(.all)
        let warnings = try config.validate()
        #expect(!warnings.map(\.description).contains(where: { $0.contains("peerblockfilters") }))
    }

    @Test("connect() produces connectDisablesPeerDiscovery warning")
    func connectWarning() throws {
        let config = BitcoinConfig.mainnet().connect("192.168.1.1")
        let warnings = try config.validate()
        #expect(warnings.contains(.connectDisablesPeerDiscovery))
    }

    @Test("disableWallet + wallet option produces walletOptionWithDisableWallet warning")
    func disableWalletWithWalletOption() throws {
        let config = BitcoinConfig.mainnet().disableWallet().wallet("test.dat")
        let warnings = try config.validate()
        #expect(warnings.contains(.walletOptionWithDisableWallet))
    }

    @Test("disableWallet alone produces no walletOption warning")
    func disableWalletAlone() throws {
        let auth = RPCAuth(username: "u", salt: "s", passwordHMAC: "h")
        let config = BitcoinConfig.mainnet().server().rpcAuth(auth).disableWallet()
        let warnings = try config.validate()
        #expect(!warnings.contains(.walletOptionWithDisableWallet))
    }

    @Test("maxUploadTarget + listen produces maxUploadTargetWithListen warning")
    func maxUploadTargetWithListen() throws {
        let config = BitcoinConfig.mainnet().maxUploadTarget(50).listen(true)
        let warnings = try config.validate()
        #expect(warnings.contains(.maxUploadTargetWithListen))
    }

    @Test("maxUploadTarget without listen produces no maxUploadTargetWithListen warning")
    func maxUploadTargetWithoutListen() throws {
        let config = BitcoinConfig.mainnet().maxUploadTarget(50)
        let warnings = try config.validate()
        #expect(!warnings.contains(.maxUploadTargetWithListen))
    }

    @Test("blockFilterIndex(.basic) does NOT set blockFilterIndexAll flag")
    func blockFilterBasicDoesNotSetAllFlag() {
        let config = BitcoinConfig.mainnet().peerBlockFilters().blockFilterIndex(.basic)
        #expect(throws: ConfigError.peerBlockFiltersWithoutIndex) {
            try config.validate()
        }
    }
}

// MARK: - Phase 3: Value Types

@Suite("Phase 3 Value Types")
struct Phase3ValueTypeTests {

    @Test("DebugCategory rawValues match Bitcoin Core names")
    func debugCategoryRawValues() {
        #expect(DebugCategory.all.rawValue == "all")
        #expect(DebugCategory.net.rawValue == "net")
        #expect(DebugCategory.mempool.rawValue == "mempool")
        #expect(DebugCategory.rpc.rawValue == "rpc")
        #expect(DebugCategory.tor.rawValue == "tor")
        #expect(DebugCategory.zmq.rawValue == "zmq")
        #expect(DebugCategory.walletdb.rawValue == "walletdb")
        #expect(DebugCategory.validation.rawValue == "validation")
    }

    @Test("LogLevel rawValues match Bitcoin Core names")
    func logLevelRawValues() {
        #expect(LogLevel.info.rawValue == "info")
        #expect(LogLevel.debug.rawValue == "debug")
        #expect(LogLevel.trace.rawValue == "trace")
    }
}

// MARK: - Phase 3: Mining Options

@Suite("Phase 3 Mining Options")
struct Phase3MiningOptionTests {

    @Test("blockMinTxFee appends fee rate arg")
    func blockMinTxFeeArg() {
        let args = BitcoinConfig.mainnet().blockMinTxFee(.satoshisPerByte(1)).arguments
        #expect(args.contains("-blockmintxfee=0.00001"))
    }

    @Test("blockMaxWeight appends -blockmaxweight=")
    func blockMaxWeightArg() {
        let args = BitcoinConfig.mainnet().blockMaxWeight(3_996_000).arguments
        #expect(args.contains("-blockmaxweight=3996000"))
    }

    @Test("blockMaxWeight clamps to 4,000,000")
    func blockMaxWeightClamp() {
        let args = BitcoinConfig.mainnet().blockMaxWeight(5_000_000).arguments
        #expect(args.contains("-blockmaxweight=4000000"))
    }

    @Test("blockMaxSize appends -blockmaxsize=")
    func blockMaxSizeArg() {
        let args = BitcoinConfig.mainnet().blockMaxSize(900_000).arguments
        #expect(args.contains("-blockmaxsize=900000"))
    }
}

// MARK: - Phase 3: Debug Options

@Suite("Phase 3 Debug Options")
struct Phase3DebugOptionTests {

    @Test("debug(.net) appends -debug=net")
    func debugNetArg() {
        let args = BitcoinConfig.mainnet().debug(.net).arguments
        #expect(args.contains("-debug=net"))
    }

    @Test("debug(.all) appends -debug=all")
    func debugAllArg() {
        let args = BitcoinConfig.mainnet().debug(.all).arguments
        #expect(args.contains("-debug=all"))
    }

    @Test("debug() called multiple times appends multiple -debug= args")
    func debugMultiValue() {
        let args = BitcoinConfig.mainnet()
            .debug(.net)
            .debug(.mempool)
            .debug(.rpc)
            .arguments
        let debugArgs = args.filter { $0.hasPrefix("-debug=") }
        #expect(debugArgs.count == 3)
        #expect(debugArgs.contains("-debug=net"))
        #expect(debugArgs.contains("-debug=mempool"))
        #expect(debugArgs.contains("-debug=rpc"))
    }

    @Test("debugExclude appends -debugexclude=")
    func debugExcludeArg() {
        let args = BitcoinConfig.mainnet().debugExclude(.libevent).arguments
        #expect(args.contains("-debugexclude=libevent"))
    }

    @Test("logLevel(.trace) appends -loglevel=trace")
    func logLevelArg() {
        let args = BitcoinConfig.mainnet().logLevel(.trace).arguments
        #expect(args.contains("-loglevel=trace"))
    }

    @Test("logIPs appends -logips=1")
    func logIPsArg() {
        let args = BitcoinConfig.mainnet().logIPs().arguments
        #expect(args.contains("-logips=1"))
    }

    @Test("printToConsole appends -printtoconsole=1")
    func printToConsoleArg() {
        let args = BitcoinConfig.mainnet().printToConsole().arguments
        #expect(args.contains("-printtoconsole=1"))
    }

    @Test("checkBlocks appends -checkblocks=")
    func checkBlocksArg() {
        let args = BitcoinConfig.mainnet().checkBlocks(100).arguments
        #expect(args.contains("-checkblocks=100"))
    }

    @Test("checkLevel clamps to 4")
    func checkLevelClamp() {
        let args = BitcoinConfig.mainnet().checkLevel(10).arguments
        #expect(args.contains("-checklevel=4"))
    }

    @Test("mockTime appends -mocktime=")
    func mockTimeArg() {
        let args = BitcoinConfig.mainnet().mockTime(1_700_000_000).arguments
        #expect(args.contains("-mocktime=1700000000"))
    }

    @Test("stopAtHeight appends -stopatheight=")
    func stopAtHeightArg() {
        let args = BitcoinConfig.mainnet().stopAtHeight(840_000).arguments
        #expect(args.contains("-stopatheight=840000"))
    }

    @Test("blockVersion appends -blockversion=")
    func blockVersionArg() {
        let args = BitcoinConfig.regtest().blockVersion(4).arguments
        #expect(args.contains("-blockversion=4"))
    }

    @Test("maxSigCacheSize appends -maxsigcachesize=")
    func maxSigCacheSizeArg() {
        let args = BitcoinConfig.mainnet().maxSigCacheSize(64).arguments
        #expect(args.contains("-maxsigcachesize=64"))
    }
}

// MARK: - Phase 3: Presets

@Suite("Phase 3 Presets")
struct Phase3PresetTests {

    let auth = RPCAuth(username: "111", salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b", passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4")

    @Test("mining preset produces expected args")
    func miningPreset() {
        let args = BitcoinConfig.mining(rpcAuth: auth).arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-txindex=1"))
        #expect(args.contains("-dbcache=4000"))
        #expect(args.contains("-blockmintxfee=0.00001"))
        #expect(args.contains("-blockmaxweight=3996000"))
    }

    @Test("mining preset validates without errors")
    func miningValidation() throws {
        let warnings = try BitcoinConfig.mining(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }

    @Test("nonSyncing preset produces expected args")
    func nonSyncingPreset() {
        let args = BitcoinConfig.nonSyncing(rpcAuth: auth).arguments
        #expect(args.contains("-server=1"))
        #expect(args.contains("-prune=550"))
        #expect(args.contains("-networkactive=0"))
        #expect(args.contains("-listen=0"))
    }

    @Test("nonSyncing preset validates without errors")
    func nonSyncingValidation() throws {
        let warnings = try BitcoinConfig.nonSyncing(rpcAuth: auth).validate()
        #expect(warnings.isEmpty)
    }
}

// MARK: - Phase 4: ZMQEndpoint Value Type

@Suite("Phase 4 ZMQEndpoint")
struct Phase4ZMQEndpointTests {

    @Test("tcp(port:) produces tcp://127.0.0.1:<port>")
    func tcpLocalhost() {
        let endpoint = ZMQEndpoint.tcp(port: 28332)
        #expect(endpoint.description == "tcp://127.0.0.1:28332")
    }

    @Test("tcp(host:port:) produces tcp://<host>:<port>")
    func tcpExplicitHost() {
        let endpoint = ZMQEndpoint.tcp(host: "0.0.0.0", port: 28333)
        #expect(endpoint.description == "tcp://0.0.0.0:28333")
    }

    @Test("different ports produce distinct endpoints")
    func distinctPorts() {
        let a = ZMQEndpoint.tcp(port: 28332)
        let b = ZMQEndpoint.tcp(port: 28333)
        #expect(a.description != b.description)
    }
}

// MARK: - Phase 4: ZMQ Options

@Suite("Phase 4 ZMQ Options")
struct Phase4ZMQOptionTests {

    let blockEndpoint = ZMQEndpoint.tcp(port: 28332)
    let txEndpoint    = ZMQEndpoint.tcp(port: 28333)

    @Test("zmqPubRawBlock appends -zmqpubrawblock=")
    func zmqPubRawBlockArg() {
        let args = BitcoinConfig.mainnet().zmqPubRawBlock(blockEndpoint).arguments
        #expect(args.contains("-zmqpubrawblock=tcp://127.0.0.1:28332"))
    }

    @Test("zmqPubRawTx appends -zmqpubrawtx=")
    func zmqPubRawTxArg() {
        let args = BitcoinConfig.mainnet().zmqPubRawTx(txEndpoint).arguments
        #expect(args.contains("-zmqpubrawtx=tcp://127.0.0.1:28333"))
    }

    @Test("zmqPubHashBlock appends -zmqpubhashblock=")
    func zmqPubHashBlockArg() {
        let args = BitcoinConfig.mainnet().zmqPubHashBlock(blockEndpoint).arguments
        #expect(args.contains("-zmqpubhashblock=tcp://127.0.0.1:28332"))
    }

    @Test("zmqPubHashTx appends -zmqpubhashtx=")
    func zmqPubHashTxArg() {
        let args = BitcoinConfig.mainnet().zmqPubHashTx(txEndpoint).arguments
        #expect(args.contains("-zmqpubhashtx=tcp://127.0.0.1:28333"))
    }

    @Test("zmqPubSequence appends -zmqpubsequence=")
    func zmqPubSequenceArg() {
        let args = BitcoinConfig.mainnet().zmqPubSequence(blockEndpoint).arguments
        #expect(args.contains("-zmqpubsequence=tcp://127.0.0.1:28332"))
    }

    @Test("zmqPubRawBlockHwm appends -zmqpubrawblockhwm=")
    func zmqPubRawBlockHwmArg() {
        let args = BitcoinConfig.mainnet().zmqPubRawBlockHwm(500).arguments
        #expect(args.contains("-zmqpubrawblockhwm=500"))
    }

    @Test("zmqPubRawTxHwm appends -zmqpubrawtxhwm=")
    func zmqPubRawTxHwmArg() {
        let args = BitcoinConfig.mainnet().zmqPubRawTxHwm(2000).arguments
        #expect(args.contains("-zmqpubrawtxhwm=2000"))
    }

    @Test("full ZMQ setup produces all expected args")
    func fullZMQSetup() {
        let args = BitcoinConfig.mainnet()
            .zmqPubRawBlock(blockEndpoint)
            .zmqPubRawTx(txEndpoint)
            .zmqPubHashBlock(blockEndpoint)
            .zmqPubHashTx(txEndpoint)
            .zmqPubSequence(blockEndpoint)
            .arguments
        #expect(args.filter { $0.hasPrefix("-zmq") }.count == 5)
    }
}

// MARK: - Phase 4: conf + rpccookiefile

@Suite("Phase 4 conf and RPC Cookie")
struct Phase4ConfAndCookieTests {

    @Test("conf() appends -conf=")
    func confArg() {
        let path = "/Library/Application Support/Bitcoin/bitcoin.conf"
        let args = BitcoinConfig.mainnet().conf(path).arguments
        #expect(args.contains("-conf=\(path)"))
    }

    @Test("rpcCookieFile() appends -rpccookiefile=")
    func rpcCookieFileArg() {
        let path = "/var/run/bitcoin/.cookie"
        let args = BitcoinConfig.mainnet().rpcCookieFile(path).arguments
        #expect(args.contains("-rpccookiefile=\(path)"))
    }

    @Test("rpcCookiePerms() appends -rpccookieperms=")
    func rpcCookiePermsArg() {
        let args = BitcoinConfig.mainnet().rpcCookiePerms("0640").arguments
        #expect(args.contains("-rpccookieperms=0640"))
    }

    @Test("rpcThreads clamps to 1 at minimum")
    func rpcThreadsClampMin() {
        let args = BitcoinConfig.mainnet().rpcThreads(0).arguments
        #expect(args.contains("-rpcthreads=1"))
    }

    @Test("rpcThreads clamps to 64 at maximum")
    func rpcThreadsClampMax() {
        let args = BitcoinConfig.mainnet().rpcThreads(999).arguments
        #expect(args.contains("-rpcthreads=64"))
    }

    @Test("rpcWorkQueue clamps to 1 at minimum")
    func rpcWorkQueueClampMin() {
        let args = BitcoinConfig.mainnet().rpcWorkQueue(0).arguments
        #expect(args.contains("-rpcworkqueue=1"))
    }

    @Test("rpcWorkQueue clamps to 1024 at maximum")
    func rpcWorkQueueClampMax() {
        let args = BitcoinConfig.mainnet().rpcWorkQueue(9999).arguments
        #expect(args.contains("-rpcworkqueue=1024"))
    }
}

// MARK: - Misconfigured Values

/// Tests that out-of-range values are silently clamped to their documented
/// minimum/maximum rather than producing invalid arguments.
@Suite("Misconfigured Values")
struct MisconfiguredValueTests {

    // MARK: dbCache

    @Test("dbCache(0) clamps to minimum 4 MiB")
    func dbCacheZero() {
        let args = BitcoinConfig.mainnet().dbCache(0).arguments
        #expect(args.contains("-dbcache=4"))
    }

    @Test("dbCache(3) clamps to minimum 4 MiB")
    func dbCacheBelowMin() {
        let args = BitcoinConfig.mainnet().dbCache(3).arguments
        #expect(args.contains("-dbcache=4"))
    }

    @Test("dbCache(4) is accepted as-is (boundary)")
    func dbCacheAtMin() {
        let args = BitcoinConfig.mainnet().dbCache(4).arguments
        #expect(args.contains("-dbcache=4"))
    }

    // MARK: maxMempool

    @Test("maxMempool(0) clamps to minimum 5 MiB")
    func maxMempoolZero() {
        let args = BitcoinConfig.mainnet().maxMempool(0).arguments
        #expect(args.contains("-maxmempool=5"))
    }

    @Test("maxMempool(4) clamps to minimum 5 MiB")
    func maxMempoolBelowMin() {
        let args = BitcoinConfig.mainnet().maxMempool(4).arguments
        #expect(args.contains("-maxmempool=5"))
    }

    @Test("maxMempool(5) is accepted as-is (boundary)")
    func maxMempoolAtMin() {
        let args = BitcoinConfig.mainnet().maxMempool(5).arguments
        #expect(args.contains("-maxmempool=5"))
    }

    // MARK: mempoolExpiry

    @Test("mempoolExpiry(0) clamps to minimum 1 hour")
    func mempoolExpiryZero() {
        let args = BitcoinConfig.mainnet().mempoolExpiry(0).arguments
        #expect(args.contains("-mempoolexpiry=1"))
    }

    @Test("mempoolExpiry(1) is accepted as-is (boundary)")
    func mempoolExpiryAtMin() {
        let args = BitcoinConfig.mainnet().mempoolExpiry(1).arguments
        #expect(args.contains("-mempoolexpiry=1"))
    }

    // MARK: limitDescendantCount

    @Test("limitDescendantCount(0) clamps to minimum 1")
    func limitDescendantCountZero() {
        let args = BitcoinConfig.mainnet().limitDescendantCount(0).arguments
        #expect(args.contains("-limitdescendantcount=1"))
    }

    // MARK: FeeRate

    @Test("FeeRate.satoshisPerByte(0) produces 0 (zero is valid)")
    func feeRateZeroSatPerByte() {
        let rate = FeeRate.satoshisPerByte(0)
        #expect(rate.description == "0")
    }

    @Test("FeeRate.btcPerKvB(0) produces 0 (zero is valid)")
    func feeRateZeroBtcPerKvB() {
        let rate = FeeRate.btcPerKvB(0)
        #expect(rate.description == "0")
    }

    // MARK: PruneMode

    @Test("PruneMode.minimum rawValue is 550")
    func pruneModeMinimumRawValue() {
        #expect(PruneMode.minimum.rawValue == 550)
    }

    @Test("PruneMode.size(mb: 550) rawValue is 550 (boundary)")
    func pruneModeAtMinBoundary() {
        #expect(PruneMode.size(mb: 550).rawValue == 550)
    }

    @Test("PruneMode.disabled rawValue is 0")
    func pruneModeDisabledRawValue() {
        #expect(PruneMode.disabled.rawValue == 0)
    }

    // MARK: blockMaxWeight

    @Test("blockMaxWeight(4_000_001) clamps to consensus limit 4,000,000")
    func blockMaxWeightOverLimit() {
        let args = BitcoinConfig.mainnet().blockMaxWeight(4_000_001).arguments
        #expect(args.contains("-blockmaxweight=4000000"))
    }

    // MARK: checkLevel

    @Test("checkLevel(5) clamps to maximum 4")
    func checkLevelOverMax() {
        let args = BitcoinConfig.mainnet().checkLevel(5).arguments
        #expect(args.contains("-checklevel=4"))
    }
}
