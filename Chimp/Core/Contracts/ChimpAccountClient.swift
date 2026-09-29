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

    /// Sel du Main account d'une carte fondatrice (`ensureAccount` : `hash(pubBytesFromHex(publicKey))`).
    static func salt(for publicKey: ChipPublicKey) -> Data {
        Data(SHA256.hash(data: publicKey.bytes))
    }

    /// Sel d'une carte orpheline qui repart sur un nouveau compte (`recoverySalt` du terminal) :
    /// `sha256("chimp.recover.v1" ‖ clé publique ‖ 32 octets de l'ancien compte)`. Fixé par le couple (carte, ancien
    /// compte) : refaire la même reprise retombe sur le même compte, au lieu d'en déployer un second.
    static func recoverySalt(publicKey: ChipPublicKey, escapedFrom: String) throws -> Data {
        guard case .contract(let id) = try SCAddressXDR(contractId: escapedFrom) else {
            throw StellarError.invalidResponse("not a contract address: \(escapedFrom)")
        }
        return Data(SHA256.hash(data: Data("chimp.recover.v1".utf8) + publicKey.bytes + id.wrapped))
    }

    /// Adresse prévue : `HashIdPreimageContractId{ networkId, fromAddress{ payeur de frais, sel } }`.
    static func predictedAddress(feePayer: String, salt: Data, network: Network) throws -> String {
        try ContractIdUtils.deriveContractId(deployer: try SCAddressXDR(accountId: feePayer), salt: salt, network: network)
    }

    /// Adresse prévue du Main account fondé par cette carte (sel = `sha256(clé)`).
    static func predictedAddress(feePayer: String, publicKey: ChipPublicKey, network: Network) throws -> String {
        try predictedAddress(feePayer: feePayer, salt: salt(for: publicKey), network: network)
    }

    /// `createCustomContract{ wasmHash, address = payeur de frais, salt, constructorArgs = [Vec[CardSigner{curve, key}]] }` :
    /// `__constructor(cards: Vec<CardSigner>)` reçoit la carte fondatrice, et rien d'autre.
    static func deployOperation(wasmHash: String, feePayer: String, publicKey: ChipPublicKey, curve: ChipCurve, salt: Data? = nil) throws -> InvokeHostFunctionOperation {
        try InvokeHostFunctionOperation.forCreatingContractWithConstructor(
            wasmId: wasmHash,
            address: try SCAddressXDR(accountId: feePayer),
            constructorArguments: [.vec([ChipAuthEncoding.cardSigner(publicKey: publicKey, curve: curve)])],
            salt: WrappedData32(salt ?? Self.salt(for: publicKey))
        )
    }

    func predictedAddress(for publicKey: ChipPublicKey) throws -> String {
        try Self.predictedAddress(feePayer: config.feePayer, publicKey: publicKey, network: client.network)
    }

    func predictedAddress(salt: Data) throws -> String {
        try Self.predictedAddress(feePayer: config.feePayer, salt: salt, network: client.network)
    }

    /// Transaction de déploiement, source = payeur de frais (séquence fraîche). `salt` : `nil` = sel de la carte fondatrice.
    func deployTransaction(for card: ChipKeyInfo, salt: Data? = nil) async throws -> Transaction {
        let source = try await client.account(config.feePayer)
        let operation = try Self.deployOperation(
            wasmHash: config.contracts.accountWasmHash, feePayer: config.feePayer, publicKey: card.publicKey, curve: card.curve, salt: salt
        )
        return try client.singleOperation(source: source, operation: operation)
    }

    /// Répétition à blanc : simule le déploiement sans rien envoyer. Renvoie les frais qui seraient payés (stroops).
    func simulateDeployment(for card: ChipKeyInfo, salt: Data? = nil) async throws -> UInt32 {
        let transaction = try await deployTransaction(for: card, salt: salt)
        try client.assemble(transaction, with: try await client.simulate(transaction))
        return transaction.fee
    }

    /// `ensureAccount` / `createFreshAccount` : réutilise le Main account s'il est déjà déployé, sinon le déploie (frais
    /// signés par le serveur de frais). Renvoie son adresse et le hash de la transaction (`nil` si rien n'a été envoyé).
    func ensureAccount(for card: ChipKeyInfo, salt: Data? = nil, feeSigner: FeeSigner) async throws -> (address: String, transactionHash: String?) {
        let address = try predictedAddress(salt: salt ?? Self.salt(for: card.publicKey))
        if try await client.isDeployed(address) { return (address, nil) }
        let hash = try await client.prepareAndSubmit(try await deployTransaction(for: card, salt: salt), feeSigner: feeSigner)
        return (address, hash)
    }

    /// `has_card(clé)` : un booléen. Une simulation sans valeur n'est pas `false` : elle lève une erreur, pour que
    /// l'appelant distingue « non » de « pas de réponse ». Sur une adresse qui n'est pas un compte, le contrat « trappe ».
    func hasCard(account: String, publicKey: ChipPublicKey, source: Account) async throws -> Bool {
        let value = try await client.readValue(source: source, contract: account, function: "has_card", arguments: [.bytes(publicKey.bytes)])
        guard let member = value.bool else { throw StellarError.invalidResponse("has_card returned \(value)") }
        return member
    }

    /// `cards()` : toutes les cartes du compte (`readAccountCards` de `provisioning.ts`), dans l'ordre du contrat.
    func cards(account: String, source: Account) async throws -> [(publicKey: ChipPublicKey, curve: ChipCurve)] {
        try Self.decodeCards(try await client.readValue(source: source, contract: account, function: "cards"))
    }

    /// `Vec<CardSigner { curve, key }>` → cartes. Une forme inattendue ou une courbe inconnue est une erreur,
    /// jamais une liste raccourcie (`Malformed card`, `Unknown curve on account card`).
    static func decodeCards(_ value: SCValXDR) throws -> [(publicKey: ChipPublicKey, curve: ChipCurve)] {
        guard case .vec(let items) = value else { throw StellarError.invalidResponse("cards returned \(value)") }
        return try (items ?? []).map { item in
            guard case .map(let entries) = item else { throw StellarError.invalidResponse("Malformed card \(item)") }
            func field(_ name: String) -> SCValXDR? {
                entries?.first { if case .symbol(name) = $0.key { true } else { false } }?.val
            }
            guard case .bytes(let key) = field("key") else { throw StellarError.invalidResponse("Malformed card \(item)") }
            // `chipCurveOf` : le nom est le premier élément du `Vec` (variante d'enum sans donnée).
            let name: String? = switch field("curve") {
            case .vec(let parts): parts?.first.flatMap { if case .symbol(let s) = $0 { s } else { nil } }
            case .symbol(let s): s
            default: nil
            }
            let curve: ChipCurve
            switch name {
            case "Secp256r1": curve = .p256
            case "Secp256k1": curve = .secp256k1
            default: throw StellarError.invalidResponse("Unknown curve on account card: \(name ?? "nil")")
            }
            do {
                return (try ChipPublicKey(key), curve)
            } catch {
                throw StellarError.invalidResponse("Malformed card key (\(key.count) bytes)")
            }
        }
    }
}
