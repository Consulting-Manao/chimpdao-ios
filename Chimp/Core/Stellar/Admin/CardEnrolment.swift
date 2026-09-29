#if CHIMP_ADMIN
import Foundation
import stellarsdk

/// Enregistrement (mint) d'une carte sur **testnet**, signé et payé par la clé admin — mode admin uniquement.
/// Portage de `enrolCard` (`reference/terminal/src/modules/onboarding/enrol.ts`) et de `mintCardNft`,
/// `readCardState`, `nftContractFor`, `predictPocket` (`reference/terminal/src/chain/provisioning.ts`).
/// Une seule écriture : `nfc-nft.mint(auth, public_key, curve, Managed, nonce)` crée le NFT, la Pocket et le lien.
/// Jamais via le serveur de frais : l'admin est la source de la transaction et la signe lui-même.
protocol CardEnrolmentService {
    /// Tap 1 fait : lit l'état de la carte sur la chaîne (sans rien écrire) et prépare ce que la carte signera.
    func inspect(_ card: ChipKeyInfo) async throws -> EnrolmentInspection
    /// Tap 2 fait : construit, simule, signe (admin) et envoie `mint`, puis relit l'état.
    func enrol(_ plan: EnrolmentPlan, signed: ChipSignedDigest) async throws -> EnrolmentResult
}

enum EnrolmentInspection: Equatable {
    /// La carte a déjà un NFT : rien à écrire (`minted: false` dans `enrolCard`).
    case alreadyEnrolled(tokenID: UInt32, pocket: String)
    /// Prête à être enregistrée.
    case ready(EnrolmentPlan)
}

/// Tout ce qui est montré avant le tap 2 (règle 8) et ce que la carte signe.
struct EnrolmentPlan: Equatable {
    let card: ChipKeyInfo
    /// Contrat `nfc-nft` de la campagne (testnet : `chi4`).
    let nfcNft: String
    /// Compte admin qui autorise et paie.
    let admin: String
    /// `get_nonce(clé) + 1`.
    let nonce: UInt32
    /// Politique de mise à jour de la Pocket : toujours `Managed` à l'enregistrement (`upgrade: "managed"`).
    let managed: Bool
    /// Digest que la carte signe (attestation, modèle B).
    let digest: Data
    /// Adresse de la Pocket, calculée hors ligne (`predictPocket`).
    let predictedPocket: String
}

struct EnrolmentResult: Equatable {
    let transactionHash: String
    let explorerURL: URL
    /// Numéro du NFT, relu après l'envoi (`nil` si la relecture n'a rien rendu).
    let tokenID: UInt32?
    let pocket: String
    /// `recovery_id` retenu (Infineon uniquement).
    let recoveryID: UInt32?
}

enum CardEnrolmentError: Error, Equatable, LocalizedError {
    /// Le mode admin refuse tout autre réseau que testnet.
    case notTestnet
    /// Aucune clé admin enregistrée sur cet appareil.
    case noAdminKey
    /// Aucun des 4 `recovery_id` n'est accepté par le contrat (signature refusée).
    case signatureRejected(String)
    /// La signature ne correspond pas au type de puce lu au tap 1.
    case curveMismatch

    var errorDescription: String? {
        switch self {
        case .notTestnet: "Admin mode only works on Stellar Testnet."
        case .noAdminKey: "No admin key on this device. Enter it first."
        case .signatureRejected(let detail): "The contract rejected the card's signature: \(detail)"
        case .curveMismatch: "The signature doesn't match the chip type read before."
        }
    }
}

struct CardEnrolment: CardEnrolmentService {
    let config: ChimpNetworkConfig
    let keyStore: AdminKeyStore
    private let client: SorobanClient

    /// Refuse de fonctionner hors testnet (garde-fou 2) : réseau, passphrase et serveur RPC doivent tous être ceux de testnet.
    init(config: ChimpNetworkConfig, keyStore: AdminKeyStore) throws {
        try Self.requireTestnet(config)
        self.config = config
        self.keyStore = keyStore
        client = SorobanClient(config: config)
    }

    static let testnetPassphrase = "Test SDF Network ; September 2015"
    static let testnetRPCHost = "soroban-testnet.stellar.org"

    static func requireTestnet(_ config: ChimpNetworkConfig) throws {
        guard config.network == .testnet,
              config.passphrase == testnetPassphrase,
              config.endpoints.rpc.host() == testnetRPCHost
        else { throw CardEnrolmentError.notTestnet }
    }

    // MARK: Tap 1 → état et plan

    func inspect(_ card: ChipKeyInfo) async throws -> EnrolmentInspection {
        let admin = try adminKeyPair()
        let source = try await client.account(admin.accountId)
        let predicted = try Self.predictPocket(factory: config.contracts.factory, publicKey: card.publicKey, network: client.network)

        let state = try await readCardState(card.publicKey, source: source)
        if let tokenID = state.tokenID {
            return .alreadyEnrolled(tokenID: tokenID, pocket: state.pocket ?? predicted)
        }

        let nfcNft = config.contracts.nfcNft
        let stored = try await client.readValue(source: source, contract: nfcNft, function: "get_nonce", arguments: [.bytes(card.publicKey.bytes)])
        guard let storedNonce = stored.u32 else { throw StellarError.invalidResponse("get_nonce returned \(stored)") }
        let nonce = storedNonce + 1
        let digest = try NfcNftAttestation.mintDigest(nfcNft: nfcNft, publicKey: card.publicKey, curve: card.curve, managed: true, nonce: nonce)
        return .ready(EnrolmentPlan(
            card: card, nfcNft: nfcNft, admin: admin.accountId, nonce: nonce, managed: true,
            digest: digest, predictedPocket: predicted
        ))
    }

    // MARK: Tap 2 → mint

    func enrol(_ plan: EnrolmentPlan, signed: ChipSignedDigest) async throws -> EnrolmentResult {
        let admin = try adminKeyPair()
        guard admin.accountId == plan.admin else { throw CardEnrolmentError.noAdminKey }
        let source = try await client.account(admin.accountId)

        let transaction: Transaction
        var recoveryID: UInt32?
        switch (plan.card.curve, signed) {
        case (.secp256k1, .secp256k1(let signature)):
            let found = try await mintWithRecoveryID(plan, signature: signature, source: source)
            transaction = found.transaction
            recoveryID = found.recoveryID
        case (.p256, .p256(let signature, let rndB)):
            let auth = try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB)
            let candidate = try Self.mintTransaction(source: Self.copy(source), plan: plan, auth: auth, maxTime: Self.maxTime())
            try client.assemble(candidate, with: try await client.simulate(candidate))
            transaction = candidate
        default:
            throw CardEnrolmentError.curveMismatch
        }

        try transaction.sign(keyPair: admin, network: client.network)
        let hash = try await client.submitAndWait(transaction)

        // Relire plutôt que se fier à l'état d'avant : le numéro du NFT n'existe qu'après le mint.
        let after = try? await readCardState(plan.card.publicKey, source: source)
        return EnrolmentResult(
            transactionHash: hash,
            explorerURL: config.explorerURL(transactionHash: hash),
            tokenID: after?.tokenID,
            pocket: after?.pocket ?? plan.predictedPocket,
            recoveryID: recoveryID
        )
    }

    /// Recherche du `recovery_id` par simulation (`RecoveryIDSearch`, choix de Pamphile, sans bibliothèque secp256k1) :
    /// on simule le même `mint` avec 0, 1, 2 puis 3 ; le premier accepté est le bon et sa simulation sert directement
    /// à assembler la transaction envoyée. Refus du contrat `nfc-nft` : `#200`.
    private func mintWithRecoveryID(_ plan: EnrolmentPlan, signature: Data, source: Account) async throws -> (transaction: Transaction, recoveryID: UInt32) {
        let maxTime = Self.maxTime()
        do {
            let found = try await RecoveryIDSearch.first(rejectionCode: RecoveryIDSearch.RejectionCode.nfcNft) { recoveryID in
                let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID)
                let candidate = try Self.mintTransaction(source: Self.copy(source), plan: plan, auth: auth, maxTime: maxTime)
                try client.assemble(candidate, with: try await client.simulate(candidate))
                return candidate
            }
            return (found.result, found.recoveryID)
        } catch StellarError.signatureRejected(let detail) {
            throw CardEnrolmentError.signatureRejected(detail)
        }
    }

    /// Signature refusée par `nfc-nft` (`#200`) ou récupération de clé impossible.
    static func isRejectedSignature(_ error: Error) -> Bool {
        RecoveryIDSearch.isRejectedSignature(error, contractCode: RecoveryIDSearch.RejectionCode.nfcNft)
    }

    // MARK: Transaction

    /// `nfc-nft.mint(auth, public_key, curve, Managed, nonce)`, source = admin, frais de base 100 stroops.
    static func mintTransaction(source: Account, plan: EnrolmentPlan, auth: SCValXDR, maxTime: UInt64) throws -> Transaction {
        let operation = try InvokeHostFunctionOperation.forInvokingContract(
            contractId: plan.nfcNft,
            functionName: "mint",
            functionArguments: NfcNftAttestation.mintArguments(
                auth: auth, publicKey: plan.card.publicKey, curve: plan.card.curve, managed: plan.managed, nonce: plan.nonce
            )
        )
        return try Transaction(
            sourceAccount: source,
            operations: [operation],
            memo: Memo.none,
            preconditions: TransactionPreconditions(timeBounds: TimeBounds(minTime: 0, maxTime: maxTime))
        )
    }

    static func maxTime() -> UInt64 {
        UInt64(Date().timeIntervalSince1970) + SorobanClient.transactionTimeout
    }

    /// Copie du compte : `Transaction` incrémente la séquence du compte qu'on lui donne.
    static func copy(_ account: Account) throws -> Account {
        try Account(accountId: account.accountId, sequenceNumber: account.sequenceNumber)
    }

    /// Adresse de la Pocket hors ligne (`predictPocket`).
    static func predictPocket(factory: String, publicKey: ChipPublicKey, network: Network) throws -> String {
        try PocketFactoryClient.predictedPocket(factory: factory, publicKey: publicKey, network: network)
    }

    // MARK: État de la carte

    /// `readCardState` partagé avec l'onboarding (`ChainCardResolver`), la clé admin servant de source aux simulations.
    func readCardState(_ publicKey: ChipPublicKey, source: Account) async throws -> CardState {
        try await ChainCardResolver.readCardState(
            publicKey,
            source: source,
            factory: PocketFactoryClient(client: client, contract: config.contracts.factory),
            nfcNft: NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection),
            pocketClient: PocketClient(client: client)
        )
    }

    private func adminKeyPair() throws -> KeyPair {
        guard let keyPair = try keyStore.keyPair() else { throw CardEnrolmentError.noAdminKey }
        return keyPair
    }
}

/// Faux service pour le simulateur : aucune requête réseau.
struct MockCardEnrolmentService: CardEnrolmentService {
    var alreadyEnrolled = false
    var delay: Duration = .milliseconds(800)

    func inspect(_ card: ChipKeyInfo) async throws -> EnrolmentInspection {
        try await Task.sleep(for: delay)
        let pocket = try CardEnrolment.predictPocket(
            factory: ChimpNetworkConfig.testnet.contracts.factory, publicKey: card.publicKey, network: .testnet
        )
        if alreadyEnrolled { return .alreadyEnrolled(tokenID: 42, pocket: pocket) }
        let digest = try NfcNftAttestation.mintDigest(
            nfcNft: ChimpNetworkConfig.testnet.contracts.nfcNft, publicKey: card.publicKey, curve: card.curve, managed: true, nonce: 1
        )
        return .ready(EnrolmentPlan(
            card: card, nfcNft: ChimpNetworkConfig.testnet.contracts.nfcNft,
            admin: ChimpNetworkConfig.testnet.contracts.admin,
            nonce: 1, managed: true, digest: digest, predictedPocket: pocket
        ))
    }

    func enrol(_ plan: EnrolmentPlan, signed: ChipSignedDigest) async throws -> EnrolmentResult {
        try await Task.sleep(for: delay)
        let hash = String(repeating: "0", count: 64)
        return EnrolmentResult(
            transactionHash: hash, explorerURL: ChimpNetworkConfig.testnet.explorerURL(transactionHash: hash),
            tokenID: 42, pocket: plan.predictedPocket, recoveryID: plan.card.curve == .secp256k1 ? 1 : nil
        )
    }
}
#endif
