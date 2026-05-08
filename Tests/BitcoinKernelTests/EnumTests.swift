//
//  EnumTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel

@Test func chainTypeRawValues() {
    #expect(ChainType.mainnet.rawValue  == 0)
    #expect(ChainType.testnet.rawValue  == 1)
    #expect(ChainType.testnet4.rawValue == 2)
    #expect(ChainType.signet.rawValue   == 3)
    #expect(ChainType.regtest.rawValue  == 4)
}

@Test func logLevelRawValues() {
    #expect(LogLevel.trace.rawValue == 0)
    #expect(LogLevel.debug.rawValue == 1)
    #expect(LogLevel.info.rawValue  == 2)
}

@Test func logCategoryRawValues() {
    #expect(LogCategory.all.rawValue          == 0)
    #expect(LogCategory.bench.rawValue        == 1)
    #expect(LogCategory.blockStorage.rawValue == 2)
    #expect(LogCategory.coinDB.rawValue       == 3)
    #expect(LogCategory.levelDB.rawValue      == 4)
    #expect(LogCategory.mempool.rawValue      == 5)
    #expect(LogCategory.prune.rawValue        == 6)
    #expect(LogCategory.rand.rawValue         == 7)
    #expect(LogCategory.reindex.rawValue      == 8)
    #expect(LogCategory.validation.rawValue   == 9)
    #expect(LogCategory.kernel.rawValue       == 10)
}

@Test func scriptVerificationFlagsRawValues() {
    #expect(ScriptVerificationFlags.none.rawValue    == 0)
    #expect(ScriptVerificationFlags.p2sh.rawValue    == 1 << 0)
    #expect(ScriptVerificationFlags.derSig.rawValue  == 1 << 2)
    #expect(ScriptVerificationFlags.nullDummy.rawValue == 1 << 4)
    #expect(ScriptVerificationFlags.checkLockTimeVerify.rawValue == 1 << 9)
    #expect(ScriptVerificationFlags.checkSequenceVerify.rawValue == 1 << 10)
    #expect(ScriptVerificationFlags.witness.rawValue == 1 << 11)
    #expect(ScriptVerificationFlags.taproot.rawValue == 1 << 17)
}

@Test func scriptVerificationFlagsAllComposition() {
    let all = ScriptVerificationFlags.all
    #expect(all.contains(.p2sh))
    #expect(all.contains(.derSig))
    #expect(all.contains(.witness))
    #expect(all.contains(.taproot))
}

@Test func scriptVerifyStatusRawValues() {
    #expect(ScriptVerifyStatus.ok.rawValue == 0)
    #expect(ScriptVerifyStatus.errorInvalidFlagsCombination.rawValue == 1)
    #expect(ScriptVerifyStatus.errorSpentOutputsRequired.rawValue == 2)
}

// MARK: - Phase 3 Enums

@Test func synchronizationStateRawValues() {
    #expect(SynchronizationState.initReindex.rawValue  == 0)
    #expect(SynchronizationState.initDownload.rawValue == 1)
    #expect(SynchronizationState.postInit.rawValue     == 2)
}

@Test func warningRawValues() {
    #expect(Warning.unknownNewRulesActivated.rawValue == 0)
    #expect(Warning.largeWorkInvalidChain.rawValue    == 1)
}

@Test func validationModeRawValues() {
    #expect(ValidationMode.valid.rawValue         == 0)
    #expect(ValidationMode.invalid.rawValue       == 1)
    #expect(ValidationMode.internalError.rawValue == 2)
}

@Test func blockValidationResultRawValues() {
    #expect(BlockValidationResult.unset.rawValue         == 0)
    #expect(BlockValidationResult.consensus.rawValue     == 1)
    #expect(BlockValidationResult.cachedInvalid.rawValue == 2)
    #expect(BlockValidationResult.invalidHeader.rawValue == 3)
    #expect(BlockValidationResult.mutated.rawValue       == 4)
    #expect(BlockValidationResult.missingPrev.rawValue   == 5)
    #expect(BlockValidationResult.invalidPrev.rawValue   == 6)
    #expect(BlockValidationResult.timeFuture.rawValue    == 7)
    #expect(BlockValidationResult.headerLowWork.rawValue == 8)
}

// MARK: - Comparable

@Test func logLevelComparable() {
    #expect(LogLevel.trace < .debug)
    #expect(LogLevel.debug < .info)
    #expect(!(LogLevel.info < .trace))
}

// MARK: - CustomStringConvertible

@Test func chainTypeDescription() {
    #expect(ChainType.mainnet.description  == "mainnet")
    #expect(ChainType.testnet.description  == "testnet")
    #expect(ChainType.testnet4.description == "testnet4")
    #expect(ChainType.signet.description   == "signet")
    #expect(ChainType.regtest.description  == "regtest")
}

@Test func validationModeDescription() {
    #expect(ValidationMode.valid.description         == "valid")
    #expect(ValidationMode.invalid.description       == "invalid")
    #expect(ValidationMode.internalError.description == "internal error")
}

@Test func scriptVerifyStatusDescription() {
    #expect(ScriptVerifyStatus.ok.description                          == "ok")
    #expect(ScriptVerifyStatus.errorInvalidFlagsCombination.description == "invalid flags combination")
    #expect(ScriptVerifyStatus.errorSpentOutputsRequired.description   == "spent outputs required")
}

@Test func synchronizationStateDescription() {
    #expect(SynchronizationState.initReindex.description  == "reindexing")
    #expect(SynchronizationState.initDownload.description == "downloading")
    #expect(SynchronizationState.postInit.description     == "synchronized")
}

@Test func blockValidationResultDescription() {
    #expect(BlockValidationResult.unset.description         == "unset")
    #expect(BlockValidationResult.consensus.description     == "consensus")
    #expect(BlockValidationResult.cachedInvalid.description == "cached invalid")
    #expect(BlockValidationResult.invalidHeader.description == "invalid header")
    #expect(BlockValidationResult.mutated.description       == "mutated")
    #expect(BlockValidationResult.missingPrev.description   == "missing previous block")
    #expect(BlockValidationResult.invalidPrev.description   == "invalid previous block")
    #expect(BlockValidationResult.timeFuture.description    == "time too far in future")
    #expect(BlockValidationResult.headerLowWork.description == "header low work")
}

@Test func warningDescription() {
    #expect(Warning.unknownNewRulesActivated.description == "unknown new rules activated")
    #expect(Warning.largeWorkInvalidChain.description    == "large-work invalid chain detected")
}

// MARK: - LocalizedError

@Test func kernelErrorDescription() {
    #expect(KernelError.contextCreationFailed.description == "Kernel context creation failed.")
    #expect(KernelError.contextCreationFailed.errorDescription == KernelError.contextCreationFailed.description)
}
