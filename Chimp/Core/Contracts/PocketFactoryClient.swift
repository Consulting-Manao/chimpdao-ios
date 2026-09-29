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
    func pocket(of publicKey: ChipPublicKey, source: Account) async throws -> String? {
        let value = try await client.readValue(source: source, contract: contract, function: "get_account", arguments: [.bytes(publicKey.bytes)])
        if case .void = value { return nil }
        guard let address = value.address, case .contract = address else {
            throw StellarError.invalidResponse("get_account returned \(value)")
        }
        return try address.toStrKey()
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
