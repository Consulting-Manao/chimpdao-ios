import CryptoKit
import Foundation
import stellarsdk

/// Contrat `account` : le Main account, partagé par toutes les cartes du compte (ARCHITECTURE §2.3 et §3.5).
/// Portage de `ensureAccount` / `deployAccount` et de `hasCard` (`reference/terminal/src/chain/provisioning.ts`).
///
/// L'adresse est déterministe : déployeur = **payeur de frais** (compte G), sel = `sha256(clé publique)`.
/// Le déploiement ne demande aucune signature de la puce : la carte fondatrice est passée au constructeur.
struct ChimpAccountClient {
    let client: SorobanClient
    let config: ChimpNetworkConfig

    /// Sel du Main account d'une carte fondatrice (`hash(pubBytesFromHex(publicKey))`).
    static func salt(for publicKey: ChipPublicKey) -> Data {
        Data(SHA256.hash(data: publicKey.bytes))
    }

    /// Adresse prévue : `HashIdPreimageContractId{ networkId, fromAddress{ payeur de frais, sel } }`.
    static func predictedAddress(feePayer: String, publicKey: ChipPublicKey, network: Network) throws -> String {
        try ContractIdUtils.deriveContractId(
            deployer: try SCAddressXDR(accountId: feePayer),
            salt: salt(for: publicKey),
            network: network
        )
    }

    /// `createCustomContract{ wasmHash, address = payeur de frais, salt, constructorArgs = [Vec[CardSigner{curve, key}]] }` :
    /// `__constructor(cards: Vec<CardSigner>)` reçoit la carte fondatrice, et rien d'autre.
    static func deployOperation(wasmHash: String, feePayer: String, publicKey: ChipPublicKey, curve: ChipCurve) throws -> InvokeHostFunctionOperation {
        try InvokeHostFunctionOperation.forCreatingContractWithConstructor(
            wasmId: wasmHash,
            address: try SCAddressXDR(accountId: feePayer),
            constructorArguments: [.vec([ChipAuthEncoding.cardSigner(publicKey: publicKey, curve: curve)])],
            salt: WrappedData32(salt(for: publicKey))
        )
    }

    func predictedAddress(for publicKey: ChipPublicKey) throws -> String {
        try Self.predictedAddress(feePayer: config.feePayer, publicKey: publicKey, network: client.network)
    }

    /// Transaction de déploiement, source = payeur de frais (séquence fraîche).
    func deployTransaction(for card: ChipKeyInfo) async throws -> Transaction {
        let source = try await client.account(config.feePayer)
        let operation = try Self.deployOperation(
            wasmHash: config.contracts.accountWasmHash, feePayer: config.feePayer, publicKey: card.publicKey, curve: card.curve
        )
        return try client.singleOperation(source: source, operation: operation)
    }

    /// Répétition à blanc : simule le déploiement sans rien envoyer. Renvoie les frais qui seraient payés (stroops).
    func simulateDeployment(for card: ChipKeyInfo) async throws -> UInt32 {
        let transaction = try await deployTransaction(for: card)
        try client.assemble(transaction, with: try await client.simulate(transaction))
        return transaction.fee
    }

    /// `ensureAccount` : réutilise le Main account s'il est déjà déployé, sinon le déploie (frais signés par le
    /// serveur de frais). Renvoie son adresse et le hash de la transaction (`nil` si rien n'a été envoyé).
    func ensureAccount(for card: ChipKeyInfo, feeSigner: FeeSigner) async throws -> (address: String, transactionHash: String?) {
        let address = try predictedAddress(for: card.publicKey)
        if try await client.isDeployed(address) { return (address, nil) }
        let hash = try await client.prepareAndSubmit(try await deployTransaction(for: card), feeSigner: feeSigner)
        return (address, hash)
    }

    /// `has_card(clé)` : un booléen. Une simulation sans valeur n'est pas `false` : elle lève une erreur, pour que
    /// l'appelant distingue « non » de « pas de réponse ». Sur une adresse qui n'est pas un compte, le contrat « trappe ».
    func hasCard(account: String, publicKey: ChipPublicKey, source: Account) async throws -> Bool {
        let value = try await client.readValue(source: source, contract: account, function: "has_card", arguments: [.bytes(publicKey.bytes)])
        guard let member = value.bool else { throw StellarError.invalidResponse("has_card returned \(value)") }
        return member
    }
}
