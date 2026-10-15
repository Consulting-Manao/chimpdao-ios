import Foundation
import stellarsdk

/// Message Circle CCTP V2 (tranche 2, D4), lu tel que l'attestation de Circle le fige : c'est ce que reçoit
/// `CctpForwarder.mint_and_forward(message, attestation)` sur Stellar. **Absent de `reference/`** : écrit d'après la
/// documentation de Circle (« CCTP on Stellar », hook data du forwarder) et vérifié octet par octet sur de vrais transferts
/// Ethereum Sepolia → Stellar finalisés sur testnet (`CCTPMessageTests`).
///
/// En-tête : version (4) · domaine source (4) · domaine destination (4) · nonce (32) · sender (32) · recipient (32) ·
/// destinationCaller (32) · minFinalityThreshold (4) · finalityThresholdExecuted (4) · corps.
/// Corps d'un burn : version (4) · burnToken (32) · mintRecipient (32) · amount (32) · messageSender (32) · maxFee (32) ·
/// feeExecuted (32) · expirationBlock (32) · hookData.
/// Hook data du forwarder : 24 octets nuls · version 0 (4, big-endian) · longueur L (4, big-endian) · adresse du
/// destinataire en texte (L octets, G…, M… ou C…).
struct CCTPMessage: Equatable, Sendable {
    let version: UInt32
    let sourceDomain: UInt32
    let destinationDomain: UInt32
    let nonce: Data
    let sender: Data
    let recipient: Data
    let destinationCaller: Data
    let minFinalityThreshold: UInt32
    let finalityThresholdExecuted: UInt32
    let burn: Burn

    struct Burn: Equatable, Sendable {
        let version: UInt32
        let burnToken: Data
        let mintRecipient: Data
        /// Unités USDC à 6 décimales (toujours, quel que soit le réseau).
        let amount: UInt64
        let messageSender: Data
        let maxFee: UInt64
        let feeExecuted: UInt64
        let hookData: Data
    }

    enum DecodeError: Error, Equatable {
        case tooShort
        case amountTooLarge
        case malformedHookData(String)
        case invalidRecipient(String)
    }

    /// Octets 0 à 23 du hook data, réservés par Circle : tous nuls pour une arrivée sur Stellar.
    static let hookMagicLength = 24
    static let headerLength = 148
    static let burnHeaderLength = 228

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerLength + Self.burnHeaderLength else { throw DecodeError.tooShort }
        func u32(_ at: Int) -> UInt32 { bytes[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func b32(_ at: Int) -> Data { Data(bytes[at..<at + 32]) }
        /// Un `uint256` qui doit tenir dans 64 bits (montants USDC) : sinon, refusé.
        func u256(_ at: Int) throws -> UInt64 {
            guard bytes[at..<at + 24].allSatisfy({ $0 == 0 }) else { throw DecodeError.amountTooLarge }
            return bytes[at + 24..<at + 32].reduce(0) { $0 << 8 | UInt64($1) }
        }
        version = u32(0)
        sourceDomain = u32(4)
        destinationDomain = u32(8)
        nonce = b32(12)
        sender = b32(44)
        recipient = b32(76)
        destinationCaller = b32(108)
        minFinalityThreshold = u32(140)
        finalityThresholdExecuted = u32(144)
        let b = Self.headerLength
        burn = Burn(
            version: u32(b), burnToken: b32(b + 4), mintRecipient: b32(b + 36), amount: try u256(b + 68),
            messageSender: b32(b + 100), maxFee: try u256(b + 132), feeExecuted: try u256(b + 164),
            hookData: Data(bytes[(b + Self.burnHeaderLength)...])
        )
    }

    // MARK: Hook data du forwarder

    /// L'adresse du destinataire écrite dans le hook data, vérifiée (octets réservés nuls, version 0, longueur exacte,
    /// adresse Stellar valide avec sa somme de contrôle).
    static func forwardRecipient(in hookData: Data) throws -> String {
        let bytes = [UInt8](hookData)
        guard bytes.count >= 32 else { throw DecodeError.malformedHookData("shorter than 32 bytes") }
        guard bytes[0..<hookMagicLength].allSatisfy({ $0 == 0 }) else { throw DecodeError.malformedHookData("reserved bytes are not zero") }
        let version = bytes[24..<28].reduce(0) { $0 << 8 | UInt32($1) }
        guard version == 0 else { throw DecodeError.malformedHookData("version \(version)") }
        let length = Int(bytes[28..<32].reduce(0) { $0 << 8 | UInt32($1) })
        guard bytes.count >= 32 + length, let text = String(bytes: bytes[32..<32 + length], encoding: .utf8) else {
            throw DecodeError.malformedHookData("recipient length \(length)")
        }
        try validate(recipient: text)
        return text
    }

    /// Hook data pour un destinataire Stellar (G…, M… ou C…), après vérification de son adresse. **Une erreur ici perd
    /// l'argent** : la même fonction côté site doit produire exactement ces octets (vecteurs de `CCTPMessageTests`).
    static func hookData(forwardRecipient: String) throws -> Data {
        try validate(recipient: forwardRecipient)
        let text = Data(forwardRecipient.utf8)
        var data = Data(count: hookMagicLength)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(text.count).bigEndian, Array.init))
        data.append(text)
        return data
    }

    /// Une adresse de contrat (C…) en 32 octets : `mintRecipient` et `destinationCaller` d'une arrivée sur Stellar.
    static func bytes32(contract: String) throws -> Data {
        guard contract.hasPrefix("C"), let data = try? contract.decodeContractId(), data.count == 32 else {
            throw DecodeError.invalidRecipient(contract)
        }
        return data
    }

    /// G… (compte), M… (compte avec memo) ou C… (contrat), somme de contrôle comprise.
    static func validate(recipient: String) throws {
        let valid: Bool
        switch recipient.first {
        case "G": valid = (try? KeyPair(accountId: recipient)) != nil
        case "M": valid = recipient.isValidMed25519PublicKey()
        case "C": valid = (try? recipient.decodeContractId())?.count == 32
        default: valid = false
        }
        guard valid else { throw DecodeError.invalidRecipient(recipient) }
    }

    // MARK: Lecture pour l'Activity

    /// L'adresse EVM (« 0x… ») d'un champ de 32 octets, si c'en est une (12 premiers octets nuls).
    static func evmAddress(_ field: Data) -> String? {
        guard field.count == 32, field.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
        return "0x" + field.suffix(20).map { String(format: "%02x", $0) }.joined()
    }

    /// Montant à 6 décimales du message → quantité USDC sur Stellar (7 décimales, ×10, exacte).
    static func stellarAmount(_ units: UInt64) -> Decimal {
        Decimal(units) / 1_000_000
    }
}
