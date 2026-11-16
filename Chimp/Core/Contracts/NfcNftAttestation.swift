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
    static func callDigest(domain: String, contractID: String, function: String, arguments: [SCValXDR], nonce: UInt32) throws -> Data {
        var preimage = Data(domain.utf8)
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.address(try SCAddressXDR(contractId: contractID))))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.symbol(function)))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.vec(arguments)))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.u32(nonce)))
        return Data(SHA256.hash(data: preimage))
    }

    /// Arguments attestés par `mint` : `[clé publique, courbe, politique, uri]` (tout fait partie de ce que la carte signe).
    /// `uri` : `Option<String>` du contrat nfc-nft (`reference/chimp-contracts`, `mint_digest` de ses tests ;
    /// `uri.into_val(e)`, donc la chaîne telle quelle pour `Some`, `ScVal::Void` pour `None`).
    ///
    /// - `nil` : la carte prend l'image par défaut de la campagne, `{base_uri}/{token_id}`.
    /// - une adresse : le **dessin choisi** dans Chimp Admin (décision de Barth du 2026-11-16). Les cartes d'un même
    ///   dessin partagent la même adresse de métadonnées, comme les cartes imprimées.
    static func mintAttestedArguments(publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool, uri: String?) -> [SCValXDR] {
        [
            .bytes(publicKey.bytes),
            ChipAuthEncoding.curve(curve),
            ChipAuthEncoding.upgradePolicy(managed: managed),
            uri.map { SCValXDR.string($0) } ?? .void,
        ]
    }

    /// Digest que la carte signe pour `mint`.
    static func mintDigest(
        nfcNft: String, publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool, uri: String?, nonce: UInt32
    ) throws -> Data {
        try callDigest(
            domain: domain,
            contractID: nfcNft,
            function: "mint",
            arguments: mintAttestedArguments(publicKey: publicKey, curve: curve, managed: managed, uri: uri),
            nonce: nonce
        )
    }

    /// Arguments complets de `mint(auth, public_key, curve, upgrade_policy, uri, nonce)`.
    static func mintArguments(
        auth: SCValXDR, publicKey: ChipPublicKey, curve: ChipCurve, managed: Bool, uri: String?, nonce: UInt32
    ) -> [SCValXDR] {
        [auth] + mintAttestedArguments(publicKey: publicKey, curve: curve, managed: managed, uri: uri) + [.u32(nonce)]
    }
}
#endif
