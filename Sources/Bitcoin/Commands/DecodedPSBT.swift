import Foundation

public struct DecodedPSBT: Codable {
    public let tx: Transaction
    public let unknown: [String: String]?
    public let inputs: [PSBTInput]
    public let outputs: [PSBTOutput]
    public let fee: Double?
    
    public struct Transaction: Codable {
        // Add fields from decoderawtransaction output
    }
    
    public struct PSBTInput: Codable {
        public let nonWitnessUtxo: Transaction?
        public let witnessUtxo: WitnessUtxo?
        public let partialSignatures: [String: String]?
        public let sighash: String?
        public let redeemScript: Script?
        public let witnessScript: Script?
        public let bip32Derivs: [BIP32Deriv]?
        public let finalScriptSig: Script?
        public let finalScriptWitness: [String]?
        public let unknown: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case nonWitnessUtxo = "non_witness_utxo"
            case witnessUtxo = "witness_utxo"
            case partialSignatures = "partial_signatures"
            case sighash
            case redeemScript = "redeem_script"
            case witnessScript = "witness_script"
            case bip32Derivs = "bip32_derivs"
            case finalScriptSig = "final_scriptsig"
            case finalScriptWitness = "final_scriptwitness"
            case unknown
        }
    }
    
    public struct WitnessUtxo: Codable {
        public let amount: Double
        public let scriptPubKey: Script
    }
    
    public struct Script: Codable {
        public let asm: String
        public let hex: String
        public let type: String
        public let address: String?
    }
    
    public struct BIP32Deriv: Codable {
        public let masterFingerprint: String
        public let path: String
        
        enum CodingKeys: String, CodingKey {
            case masterFingerprint = "master_fingerprint"
            case path
        }
    }
    
    public struct PSBTOutput: Codable {
        public let redeemScript: Script?
        public let witnessScript: Script?
        public let bip32Derivs: [BIP32Deriv]?
        public let unknown: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case redeemScript = "redeem_script"
            case witnessScript = "witness_script"
            case bip32Derivs = "bip32_derivs"
            case unknown
        }
    }
}