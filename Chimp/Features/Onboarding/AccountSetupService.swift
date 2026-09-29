import Foundation
import stellarsdk

/// Ce que la carte signera au tap d'A6, préparé **avant** d'ouvrir la session NFC (règles 8 et 9) :
/// la preuve de possession et `set_owner` vers le Main account à créer (ARCHITECTURE §3.5).
struct AccountSetupPlan {
    let card: ChipKeyInfo
    /// Wallet de la carte (Pocket), qui autorise `set_owner`.
    let pocket: String
    /// Campagne `nfc-nft` qui connaît la carte (preuve de possession Infineon par `verify_for_card`).
    let nftContract: String?
    /// Sel et adresse du Main account à créer.
    let accountSalt: Data
    let account: String
    /// Défi aléatoire de la preuve de possession.
    let challenge: Data
    /// Entrée `set_owner` déclarée (ordre 1), et son digest.
    let setOwner: DeclaredAuthorization

    /// Dans l'ordre du tap : preuve de possession, puis `set_owner` (DESIGN_NOTES §13).
    var digests: [Data] { [challenge, setOwner.digest] }
}

/// Résultat de la répétition à blanc : tout ce qui a été vérifié, sans rien envoyer.
struct RehearsalReport: Equatable {
    let account: String
    let accountAlreadyDeployed: Bool
    /// Frais simulés du déploiement (stroops), `nil` si le compte existe déjà.
    let deploymentFee: UInt32?
    /// `recovery_id` de la preuve de possession (Infineon) ; `nil` pour une DUOX (vérification locale).
    let possessionRecoveryID: UInt32?
    /// `recovery_id` accepté pour `set_owner` (Infineon) ; `nil` pour une DUOX.
    let setOwnerRecoveryID: UInt32?
    /// Frais simulés de `set_owner` après `refitAuth` (stroops).
    let setOwnerFee: UInt32
    /// Texte exact d'un refus de signature par la Pocket (question 21 de DESIGN_NOTES §12), s'il a été observé.
    let rejectionSamples: [String]
}

/// Création du compte, vue par l'onboarding. Étape 3 : **répétition à blanc seulement**.
/// Implémenté par `ChainAccountSetupService` (testnet, lectures et simulations) et `MockAccountSetupService`.
protocol AccountSetupService {
    /// Avant le tap : dernier ledger, adresse du compte, entrée `set_owner`, défi. Lectures seulement.
    func prepare(card: ChipKeyInfo, pocket: String, accountSalt: Data) async throws -> AccountSetupPlan
    /// Après le tap : vérifie la preuve de possession, simule le déploiement et `set_owner` (avec la recherche du
    /// `recovery_id`). **N'envoie rien** : ce service n'a pas de serveur de frais et n'appelle jamais `sendTransaction`.
    func rehearse(_ plan: AccountSetupPlan, signatures: [ChipSignedDigest]) async throws -> RehearsalReport
}

enum AccountSetupError: Error, Equatable, LocalizedError {
    /// La carte n'a pas rendu autant de signatures que de digests.
    case missingSignatures(Int)

    var errorDescription: String? {
        switch self {
        case .missingSignatures(let count): "The card returned \(count) signature(s) instead of 2."
        }
    }
}

struct ChainAccountSetupService: AccountSetupService {
    let config: ChimpNetworkConfig

    func prepare(card: ChipKeyInfo, pocket: String, accountSalt: Data) async throws -> AccountSetupPlan {
        let client = SorobanClient(config: config)
        let resolver = ChainCardResolver(config: config)
        let state = try await resolver.state(of: card.publicKey)
        let account = try ChimpAccountClient(client: client, config: config).predictedAddress(salt: accountSalt)
        let ledger = try await client.latestLedger()
        let setOwner = try PocketClient.declareSetOwner(
            pocket: pocket, newOwner: account, passphrase: config.passphrase,
            currentLedger: ledger, nonce: try SorobanAuth.randomNonce()
        )
        return AccountSetupPlan(
            card: card, pocket: pocket, nftContract: state.nftContract, accountSalt: accountSalt,
            account: account, challenge: try CardPossession.challenge(), setOwner: setOwner
        )
    }

    func rehearse(_ plan: AccountSetupPlan, signatures: [ChipSignedDigest]) async throws -> RehearsalReport {
        guard signatures.count == 2 else { throw AccountSetupError.missingSignatures(signatures.count) }
        let client = SorobanClient(config: config)
        let source = try await client.account(config.feePayer)

        // 1. Preuve de possession, avant tout ce qui coûterait au payeur de frais.
        let nfcNft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        let possessionID = try await CardPossession.verify(
            card: plan.card, challenge: plan.challenge, signed: signatures[0],
            nfcNft: nfcNft, nftContract: plan.nftContract, source: source
        )

        // 2. Déploiement du Main account : simulé seulement.
        let accounts = ChimpAccountClient(client: client, config: config)
        let deployed = try await client.isDeployed(plan.account)
        let deploymentFee = deployed ? nil : try await accounts.simulateDeployment(for: plan.card, salt: plan.accountSalt)

        // 3. set_owner : simulation avec recherche du recovery_id, puis refitAuth (une simulation de plus).
        var rejections: [String] = []
        let pocketClient = PocketClient(client: client)
        let prepared = try await pocketClient.prepareSetOwner(
            declared: plan.setOwner, pocket: plan.pocket, newOwner: plan.account, curve: plan.card.curve,
            signed: signatures[1], feePayer: config.feePayer,
            onRejected: { id, error in rejections.append("recovery_id \(id): \(Self.details(error))") }
        )
        try await client.refit(prepared.transaction)

        // 4. Diagnostic : si le premier recovery_id était le bon, on provoque un refus pour lire son texte exact.
        if rejections.isEmpty, let found = prepared.recoveryID, case .secp256k1(let signature) = signatures[1] {
            let wrong = (found + 1) % 4
            let error = try await pocketClient.setOwnerSimulationError(
                declared: plan.setOwner, pocket: plan.pocket, newOwner: plan.account,
                signature: signature, recoveryID: wrong, feePayer: config.feePayer
            )
            rejections.append("recovery_id \(wrong): \(error.map(Self.details) ?? "accepted too (unexpected)")")
        }

        return RehearsalReport(
            account: plan.account, accountAlreadyDeployed: deployed, deploymentFee: deploymentFee,
            possessionRecoveryID: possessionID, setOwnerRecoveryID: prepared.recoveryID,
            setOwnerFee: prepared.transaction.fee, rejectionSamples: rejections
        )
    }

    static func details(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}

/// Faux service pour le simulateur, le catalogue et les tests : aucune requête réseau.
final class MockAccountSetupService: AccountSetupService, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        case success
        case networkError
        case signatureRejected
        var id: String { rawValue }
    }

    var scenario: Scenario
    var delay: Duration
    private(set) var prepareCount = 0
    private(set) var rehearseCount = 0
    /// Dernier plan préparé (tests).
    private(set) var lastPlan: AccountSetupPlan?

    init(scenario: Scenario = .success, delay: Duration = .milliseconds(900)) {
        self.scenario = scenario
        self.delay = delay
    }

    func prepare(card: ChipKeyInfo, pocket: String, accountSalt: Data) async throws -> AccountSetupPlan {
        prepareCount += 1
        try await Task.sleep(for: delay)
        let account = try ChimpAccountClient.predictedAddress(feePayer: ChimpNetworkConfig.testnet.feePayer, salt: accountSalt, network: .testnet)
        let setOwner = try PocketClient.declareSetOwner(
            pocket: pocket, newOwner: account, passphrase: ChimpNetworkConfig.testnet.passphrase, currentLedger: 1_000, nonce: 42
        )
        let plan = AccountSetupPlan(
            card: card, pocket: pocket, nftContract: ChimpNetworkConfig.testnet.contracts.nfcNft, accountSalt: accountSalt,
            account: account, challenge: Data(repeating: 0x5A, count: 32), setOwner: setOwner
        )
        lastPlan = plan
        return plan
    }

    func rehearse(_ plan: AccountSetupPlan, signatures: [ChipSignedDigest]) async throws -> RehearsalReport {
        rehearseCount += 1
        try await Task.sleep(for: delay)
        switch scenario {
        case .success:
            return RehearsalReport(
                account: plan.account, accountAlreadyDeployed: false, deploymentFee: 29_353_225,
                possessionRecoveryID: plan.card.curve == .secp256k1 ? 1 : nil,
                setOwnerRecoveryID: plan.card.curve == .secp256k1 ? 0 : nil,
                setOwnerFee: 180_000, rejectionSamples: ["recovery_id 1: Simulation failed: HostError: Error(Contract, #201)"]
            )
        case .networkError:
            throw StellarError.rpc("The request timed out.")
        case .signatureRejected:
            throw StellarError.signatureRejected("Simulation failed: HostError: Error(Contract, #201)")
        }
    }
}
