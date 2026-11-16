import Foundation
import stellarsdk

/// Contrats `nfc-nft` (une campagne chacun) et registre `collection` (ARCHITECTURE §2.3).
/// Portage de `nftContractFor` et de la partie NFT de `readCardState` (`reference/terminal/src/chain/provisioning.ts`).
struct NfcNftClient {
    let client: SorobanClient
    /// Campagne par défaut (testnet : `chi4`).
    let defaultContract: String
    /// Registre des campagnes.
    let collection: String

    /// `nftContractFor` : la campagne par défaut d'abord, puis chaque campagne de `collection.collections()`.
    /// Lève l'erreur de la campagne par défaut si aucune ne connaît la carte (`token_id` refuse une carte jamais
    /// enregistrée : c'est un « trap » du contrat, que l'appelant distingue d'une panne réseau).
    func token(of publicKey: ChipPublicKey, source: Account) async throws -> (contract: String, tokenID: UInt32) {
        var candidates = [defaultContract]
        if let registry = try? await client.read(source: source, contract: collection, function: "collections"),
           let entries = registry.vec {
            for entry in entries {
                if let strkey = try? entry.address?.toStrKey(), strkey.hasPrefix("C"), !candidates.contains(strkey) {
                    candidates.append(strkey)
                }
            }
        }
        var firstError: Error?
        for contract in candidates {
            do {
                let value = try await client.readValue(source: source, contract: contract, function: "token_id", arguments: [.bytes(publicKey.bytes)])
                // `Number(null)` vaut 0 et 0 est un vrai numéro : sans valeur, c'est « pas de réponse », pas zéro.
                guard let tokenID = value.u32 else { throw StellarError.invalidResponse("token_id returned \(value)") }
                return (contract, tokenID)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? StellarError.invalidResponse("no collection knows this card")
    }

    /// `owner_of(token_id)` : propriétaire du NFT (la Pocket de la carte).
    func owner(ofToken tokenID: UInt32, contract: String, source: Account) async throws -> String {
        let value = try await client.readValue(source: source, contract: contract, function: "owner_of", arguments: [.u32(tokenID)])
        guard let address = value.address else { throw StellarError.invalidResponse("owner_of returned \(value)") }
        return try address.toStrKey()
    }

    /// `token_uri(token_id)` (SEP-50) : où sont les métadonnées du NFT de cette carte (son dessin). Les cartes d'un même
    /// dessin partagent le même fichier.
    func tokenURI(tokenID: UInt32, contract: String, source: Account) async throws -> String {
        let value = try await client.readValue(source: source, contract: contract, function: "token_uri", arguments: [.u32(tokenID)])
        guard let uri = value.string, !uri.isEmpty else { throw StellarError.invalidResponse("token_uri returned \(value)") }
        return uri
    }

    /// `verify_for_card(public_key, digest, auth) -> bool`, en lecture seule (simulation, rien n'est payé).
    /// `false` pour une carte inconnue, une variante qui ne correspond pas à la courbe, ou une mauvaise signature k1.
    func verifyForCard(publicKey: ChipPublicKey, digest: Data, auth: SCValXDR, contract: String, source: Account) async throws -> Bool {
        let value = try await client.readValue(
            source: source, contract: contract, function: "verify_for_card",
            arguments: [.bytes(publicKey.bytes), .bytes(digest), auth]
        )
        guard let verified = value.bool else { throw StellarError.invalidResponse("verify_for_card returned \(value)") }
        return verified
    }
}
