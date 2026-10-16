import CryptoKit
import Foundation
import stellarsdk

/// Contrat `pocket-factory` : « quelle est la Pocket de cette puce ? » (ARCHITECTURE §2.3).
/// Portage de `lookupPocket` (`reference/terminal/src/chain/pocket.ts`) et de `predictPocket` (`provisioning.ts`).
struct PocketFactoryClient {
    let client: SorobanClient
    let contract: String

    /// `get_account(clé)` → `Option<Address>`. `None` est une vraie réponse (carte jamais enregistrée) ;
    /// une simulation sans valeur est une erreur, jamais « pas de Pocket ».
    ///
    /// Revue de sécurité F2 (2026-10-16) : l'adresse lue doit être celle que la factory déploie pour cette clé
    /// (`predictedPocket`) ; un RPC qui en annonce une autre est refusé (sinon un Move enverrait l'argent du Main ailleurs).
    func pocket(of publicKey: ChipPublicKey, source: Account) async throws -> String? {
        let value = try await client.readValue(source: source, contract: contract, function: "get_account", arguments: [.bytes(publicKey.bytes)])
        if case .void = value { return nil }
        guard let address = value.address, case .contract = address else {
            throw StellarError.invalidResponse("get_account returned \(value)")
        }
        return try Self.checked(try address.toStrKey(), publicKey: publicKey, factory: contract, network: client.network)
    }

    /// La Pocket d'une carte n'a qu'une adresse possible : celle que la factory déploie pour sa clé. Toute autre adresse
    /// (lue sur le réseau, ou gardée sur le téléphone) est refusée.
    static func checked(_ address: String, publicKey: ChipPublicKey, factory: String, network: Network) throws -> String {
        let expected = try predictedPocket(factory: factory, publicKey: publicKey, network: network)
        guard address == expected else { throw PocketAddressError.mismatch(expected: expected, got: address) }
        return address
    }

    /// Adresse de la Pocket hors ligne (`predictPocket`) : déployeur = factory, sel = `sha256(clé publique)`.
    static func predictedPocket(factory: String, publicKey: ChipPublicKey, network: Network) throws -> String {
        try ContractIdUtils.deriveContractId(
            deployer: try SCAddressXDR(contractId: factory),
            salt: Data(SHA256.hash(data: publicKey.bytes)),
            network: network
        )
    }
}

/// Une adresse de Pocket qui n'est pas celle de la carte (revue de sécurité F2).
enum PocketAddressError: Error, Equatable, LocalizedError {
    case mismatch(expected: String, got: String)

    var errorDescription: String? {
        "This card's wallet address doesn't match the card. For your safety, nothing is read from it or sent to it."
    }
}

extension ChimpNetworkConfig {
    /// La Pocket de `publicKey` si `address` est bien la sienne sur ce réseau, sinon une erreur (F2).
    func checkedPocket(_ address: String, of publicKey: ChipPublicKey) throws -> String {
        try PocketFactoryClient.checked(address, publicKey: publicKey, factory: contracts.factory, network: .custom(passphrase: passphrase))
    }
}
