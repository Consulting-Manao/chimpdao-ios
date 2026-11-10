import CryptoKit
import Foundation
import stellarsdk

/// Preuve de possession : la puce signe un défi aléatoire tout neuf, et on vérifie la signature contre la clé
/// publique qu'elle a annoncée. Faite **avant** de déployer un Main account, pour que le payeur de frais ne paie
/// jamais pour une clé simplement annoncée. Portage de `verifyCardPossession` (`reference/terminal/src/chain/possession.ts`).
///
/// - DUOX (P-256) : vérification locale avec CryptoKit, comme le terminal.
/// - Infineon (secp256k1) : le terminal retrouve la clé avec une bibliothèque secp256k1, que l'app n'a pas.
///   Adaptation validée par Pamphile (2026-09-29) : simulation gratuite de `nfc-nft.verify_for_card` avec les
///   `recovery_id` 0 à 3 (même méthode que pour le mint). Rien n'est signé ni payé.
enum CardPossession {
    enum PossessionError: Error, Equatable, LocalizedError {
        /// La signature ne correspond pas à la clé annoncée par la carte.
        case signatureMismatch
        /// La carte n'est connue d'aucune campagne : impossible de vérifier par `verify_for_card`.
        case unknownCard

        var errorDescription: String? {
            switch self {
            case .signatureMismatch: "Card check failed: the signature doesn't match this card."
            case .unknownCard: "Card check failed: this card isn't registered."
            }
        }
    }

    /// Défi : 32 octets aléatoires (`crypto.getRandomValues(new Uint8Array(32))`).
    static func challenge() throws -> Data {
        try SorobanAuth.randomBytes(count: 32)
    }

    /// Ce que la DUOX signe réellement pour un défi (Internal Authenticate) : `F0F0 ‖ 8000 ‖ RndB(16) ‖ défi[0..16]`.
    /// Le terminal reçoit ce préimage du bridge et vérifie qu'il contient bien *son* défi ; ici on le reconstruit
    /// à partir de notre propre défi, ce qui fait la même vérification.
    static func p256Payload(rndB: Data, challenge: Data) -> Data {
        Data([0xF0, 0xF0, 0x80, 0x00]) + rndB + challenge.prefix(16)
    }

    /// Vérification locale DUOX : `p256.verify(signature, sha256(payload), clé)`, sans exigence low-S.
    static func verifyP256(publicKey: ChipPublicKey, challenge: Data, signature: Data, rndB: Data) throws {
        guard rndB.count == 16, signature.count == 64, challenge.count == 32 else { throw PossessionError.signatureMismatch }
        let key: P256.Signing.PublicKey
        let ecdsa: P256.Signing.ECDSASignature
        do {
            key = try P256.Signing.PublicKey(x963Representation: publicKey.bytes)
            ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        } catch {
            throw PossessionError.signatureMismatch
        }
        let digest = SHA256.hash(data: p256Payload(rndB: rndB, challenge: challenge))
        guard key.isValidSignature(ecdsa, for: digest) else { throw PossessionError.signatureMismatch }
    }

    /// Vérifie la signature du défi. Pour Infineon, `nfcNft` et `nftContract` (la campagne qui connaît la carte,
    /// lue par `readCardState`) servent à la simulation de `verify_for_card`. Renvoie le `recovery_id` trouvé (Infineon).
    @discardableResult
    static func verify(
        card: ChipKeyInfo,
        challenge: Data,
        signed: ChipSignedDigest,
        nfcNft: NfcNftClient,
        nftContract: String?,
        source: Account
    ) async throws -> UInt32? {
        switch (card.curve, signed) {
        case (.p256, .p256(let signature, let rndB)):
            try verifyP256(publicKey: card.publicKey, challenge: challenge, signature: signature, rndB: rndB)
            return nil
        case (.secp256k1, .secp256k1(let signature)):
            guard let nftContract else { throw PossessionError.unknownCard }
            for recoveryID: UInt32 in 0...3 {
                let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID)
                do {
                    if try await nfcNft.verifyForCard(publicKey: card.publicKey, digest: challenge, auth: auth, contract: nftContract, source: source) {
                        return recoveryID
                    }
                } catch where RecoveryIDSearch.isRejectedSignature(error, contractCodes: nil) {
                    // `verify_k1` renvoie `false` pour une autre clé, mais « trappe » sur une entrée mal formée : même sens.
                    continue
                }
            }
            throw PossessionError.signatureMismatch
        default:
            throw PossessionError.signatureMismatch
        }
    }
}
