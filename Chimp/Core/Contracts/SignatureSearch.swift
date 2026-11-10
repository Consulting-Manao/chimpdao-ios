import Foundation
import stellarsdk

/// Recherche du `recovery_id` d'une signature Infineon **par simulation**, sans bibliothèque secp256k1
/// (décision de Pamphile du 2026-09-29). Portage de `determineRecoveryId` de
/// `reference/ios-app-tupui/Chimp/Services/BlockchainService.swift` : on simule le même appel avec 0, 1, 2 puis 3 ;
/// le premier accepté par le contrat est le bon. Une signature refusée fait passer au suivant ; toute autre erreur remonte.
enum RecoveryIDSearch {
    /// Codes d'erreur « signature invalide » de chaque contrat : l'ancien numéro, puis le nouveau (contrats renumérotés,
    /// `CLIENT-INTEGRATION.md` §10, valeurs relues dans les wasm du testnet le 2026-11-10). Les deux tournent en même temps :
    /// un compte ou une Pocket garde son code tant qu'il n'est pas mis à jour.
    enum RejectionCode {
        /// `nfc-nft` : `InvalidSignature` = 200, puis 101 (mint).
        static let nfcNft: Set<Int> = [200, 101]
        /// `pocket` : `PocketError::InvalidSignature` = 201, puis 402.
        static let pocket: Set<Int> = [201, 402]
        /// `account` : `AccountError::InvalidSignature` = 301, puis 502.
        static let account: Set<Int> = [301, 502]
    }

    /// Essaie `attempt` avec les `recovery_id` 0 à 3 et renvoie le premier résultat accepté.
    /// `onRejected` reçoit chaque refus (diagnostic : texte exact renvoyé par le réseau).
    static func first<T>(
        rejectionCodes: Set<Int>,
        onRejected: ((UInt32, Error) -> Void)? = nil,
        attempt: (UInt32) async throws -> T
    ) async throws -> (result: T, recoveryID: UInt32) {
        var lastError: Error?
        for recoveryID: UInt32 in 0...3 {
            do {
                return (try await attempt(recoveryID), recoveryID)
            } catch {
                lastError = error
                if isRejectedSignature(error, contractCodes: rejectionCodes) {
                    onRejected?(recoveryID, error)
                    continue
                }
                throw error
            }
        }
        throw StellarError.signatureRejected((lastError as? LocalizedError)?.errorDescription ?? "no recovery id accepted")
    }

    /// Erreurs qui veulent dire « mauvais `recovery_id` » (ancienne app : `InvalidSignature`, `InvalidInput`,
    /// `recovery failed`, `recover_key_ecdsa`). Seul le code exact du contrat appelé est reconnu, pas le motif
    /// « n'importe quel nombre de 3 chiffres entre 200 et 220 » de l'ancienne app.
    /// `contractCodes` à `nil` : seulement l'échec de la récupération de clé par l'hôte (`secp256k1_recover` qui « trappe »
    /// sur une entrée mal formée, cas possible avec un mauvais `recovery_id`, d'après `chip-auth/src/verify.rs`).
    static func isRejectedSignature(_ error: Error, contractCodes: Set<Int>?) -> Bool {
        guard case StellarError.simulationFailed(let message) = error else { return false }
        if let contractCodes, !contractCodes.isEmpty {
            let codes = contractCodes.sorted().map(String.init).joined(separator: "|")
            if message.range(of: #"Error\(Contract,\s*#?(?:\#(codes))\)"#, options: .regularExpression) != nil { return true }
            if message.range(of: #"\["failing with contract error", (?:\#(codes))\]"#, options: .regularExpression) != nil { return true }
        }
        return message.contains("InvalidInput") || message.contains("recovery failed") || message.contains("recover_key_ecdsa")
    }
}
