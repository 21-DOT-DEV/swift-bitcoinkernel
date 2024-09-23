//
//  Commands.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

public enum Commands: String, CaseIterable {
    // Blockchain RPCs
    case getBestBlockHash
    case getBlockchainInfo
    case getBlock
    case getBlockFilter
    case getBlockHash
    case getBlockHeader
    case getBlockStats
    case getChainTips
    case getChainTxStats
    case getDifficulty
    case getMempoolAncestors
    case getMempoolDescendants
    case getMempoolEntry
    case getMempoolInfo
    case getRawMempool
    case getTxOut
    case getTxOutProof
    case getTxOutSetInfo
    case preciousBlock
    case pruneBlockchain
    case saveMempool
    case scanTxOutSet
    case verifyChain
    case verifyTxOutProof
    
    // Control RPCs
    case getMemoryInfo
    case getRPCInfo = "getrpcinfo"
    case help
    case logging
    case stop
    case uptime
    
    // Generating RPCs
    case generateBlock = "generateblock"
    case generateToAddress = "generatetoaddress"
    case generateToDescriptor = "generatetodescriptor"
    
    // Mining RPCs
    case getBlockTemplate = "getblocktemplate"
    case getMiningInfo
    case getNetworkHashPS = "getnetworkhashps"
    case prioritiseTransaction = "prioritisetransaction"
    case submitBlock = "submitblock"
    case submitHeader = "submitheader"
    
    // Network RPCs
    case addNode = "addnode"
    case clearBanned = "clearbanned"
    case disconnectNode = "disconnectnode"
    case getAddedNodeInfo = "getaddednodeinfo"
    case getConnectionCount = "getconnectioncount"
    case getNetTotals = "getnettotals"
    case getNetworkInfo = "getnetworkinfo"
    case getNodeAddresses = "getnodeaddresses"
    case getPeerInfo = "getpeerinfo"
    case listBanned = "listbanned"
    case ping
    case setBan = "setban"
    case setNetworkActive = "setnetworkactive"
    
    // Rawtransactions RPCs
    case analyzePSBT = "analyzepsbt"
    case combinePSBT = "combinepsbt"
    case combineRawTransaction = "combinerawtransaction"
    case convertToPSBT = "converttopsbt"
    case createPSBT = "createpsbt"
    case createRawTransaction = "createrawtransaction"
    case decodePSBT = "decodepsbt"
    case decodeRawTransaction = "decoderawtransaction"
    case decodeScript = "decodescript"
    case finalizePSBT = "finalizepsbt"
    case fundRawTransaction = "fundrawtransaction"
    case getRawTransaction = "getrawtransaction"
    case joinPSBTs = "joinpsbts"
    case sendRawTransaction = "sendrawtransaction"
    case signRawTransactionWithKey = "signrawtransactionwithkey"
    case testMempoolAccept = "testmempoolaccept"
    case utxoUpdatePSBT = "utxoupdatepsbt"
    
    // Util RPCs
    case createMultisig
    case deriveAddresses
    case estimateSmartFee
    case getDescriptorInfo
    case getIndexInfo
    case signMessageWithPrivKey
    case validateAddress
    case verifyMessage
    
    // Wallet RPCs
    case getBlockCount
    case getNewAddress
    case listUnspent
    case sendToAddress
}
