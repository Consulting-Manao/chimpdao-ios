#if CHIMP_ADMIN
import CryptoKit
import Foundation
import stellarsdk

/// Attestation de présence de la puce pour `nfc-nft` (modèle B, ARCHITECTURE §3.2) — utilisée seulement par
/// l'enregistrement (mint), donc compilée uniquement en mode admin (`CHIMP_ADMIN`).
/// Portage de `callDigest`, `NFC_NFT_DOMAIN` et des arguments de `mintCardNft` (`chip-auth.ts`, `provisioning.ts`),
/// identique octet pour octet à `chimpdao_chip_auth::call_digest` (Rust).
enum NfcNftAttestation {
    /// Séparateur de domaine du contrat nfc-nft (`contract::DOMAIN`).
    static let domain = "chimpdao.nfc-nft.v3"

    /// `sha256(domain ‖ XDR(adresse du contrat) ‖ XDR(Symbol fonction) ‖ XDR(Vec arguments) ‖ XDR(u32 nonce))`.
    /// Le calcul lui-même est partagé avec le contrat `prize` (`ChipCallDigest`, compilé aussi hors du mode admin).
    static func callDigest(domain: String, contractID: String, function: String, arguments: [SCValXDR], nonce: UInt32) throws -> Data {
        try ChipCallDigest.callDigest(domain: domain, contractID: contractID, function: function, arguments: arguments, nonce: nonce)
    }

    /// Arguments attestés par `mint` : `[clé publique, courbe, politique, uri]` (tout fait partie de ce que la carte signe).
    /// `uri` : `Option<String>` ajouté au contrat nfc-nft déployé sur testnet (`reference/chimp-contracts` e9e6c84,
    /// `mint_digest` des tests du contrat). Toujours `None` (`ScVal::Void`) : la carte garde l'image par défaut
    /// `{base_uri}/{token_id}`, comme avant (décision de Barth du 2026-10-23 : le même système qu'avant).
    static func mintAttestedArguments(publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool) -> [SCValXDR] {
        [.bytes(publicKey.bytes), ChipAuthEncoding.curve(curve), ChipAuthEncoding.upgradePolicy(managed: managed), .void]
    }

    /// Digest que la carte signe pour `mint`.
    static func mintDigest(nfcNft: String, publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool, nonce: UInt32) throws -> Data {
        try callDigest(
            domain: domain,
            contractID: nfcNft,
            function: "mint",
            arguments: mintAttestedArguments(publicKey: publicKey, curve: curve, managed: managed),
            nonce: nonce
        )
    }

    /// Arguments complets de `mint(auth, public_key, curve, upgrade_policy, uri, nonce)`.
    static func mintArguments(auth: SCValXDR, publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool, nonce: UInt32) -> [SCValXDR] {
        [auth] + mintAttestedArguments(publicKey: publicKey, curve: curve, managed: managed) + [.u32(nonce)]
    }
}
#endif
