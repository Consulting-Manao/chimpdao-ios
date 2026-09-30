import Foundation
import stellarsdk

/// Étapes de la création du compte, dans l'ordre (ARCHITECTURE §3.5, `startCreate` du terminal).
enum CreationStep: Int, CaseIterable, Comparable, Sendable {
    /// Preuve de possession (avant tout ce qui coûte au payeur de frais).
    case checkingCard
    /// Déploiement du Main account (payé par ChimpDAO via le serveur de frais).
    case creatingAccount
    /// `pocket.set_owner(Main account)` (payé par ChimpDAO).
    case linkingCard
    /// Relecture sur la chaîne : la Pocket pointe vers le compte et le compte connaît la carte.
    case confirming

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct CreationResult: Equatable, Sendable {
    let account: String
    /// Hash du déploiement, `nil` s'il était déjà fait (reprise).
    let deploymentHash: String?
    /// Hash de `set_owner`, `nil` si la carte pointait déjà vers le compte (reprise).
    let linkHash: String?
}

enum AccountCreationError: Error, Equatable, LocalizedError {
    /// La signature `set_owner` de la carte expire bientôt ou a expiré : il faut un nouveau tap.
    case signatureExpired
    /// Tout a été envoyé, mais la relecture ne montre pas encore le résultat attendu.
    case notConfirmedOnChain(String)

    var errorDescription: String? {
        switch self {
        case .signatureExpired: "The card's signature for the link has expired. A new tap is needed."
        case .notConfirmedOnChain(let detail): "Sent, but not visible on Stellar yet: \(detail)"
        }
    }
}

/// Ce dont la création a besoin sur la chaîne. Implémenté par `ChainAccountCreation` (testnet, serveur de frais)
/// et par de faux services dans les tests (reprise, erreurs).
protocol AccountCreationChain {
    func verifyPossession(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws
    func isDeployed(_ account: String) async throws -> Bool
    /// Déploie le Main account ; renvoie le hash.
    func deployAccount(_ plan: AccountSetupPlan) async throws -> String
    func pocketOwner(_ pocket: String) async throws -> String
    func latestLedger() async throws -> UInt32
    /// Envoie `set_owner` (ordre 1, `recovery_id` par simulation) ; renvoie le hash.
    func linkCard(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws -> String
    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool
}

/// La création, pas à pas. Chaque étape relit la chaîne et **se saute si elle est déjà faite** (`ceremonies.ts` :
/// « a failed run resumes instead of duplicating ») : relancer après une coupure reprend là où ça s'est arrêté.
struct AccountCreator {
    let chain: AccountCreationChain

    func create(
        _ plan: AccountSetupPlan,
        signatures: [ChipSignedDigest],
        progress: (CreationStep) -> Void
    ) async throws -> CreationResult {
        guard signatures.count == 2 else { throw AccountSetupError.missingSignatures(signatures.count) }

        progress(.checkingCard)
        try await chain.verifyPossession(plan, signed: signatures[0])

        progress(.creatingAccount)
        var deploymentHash: String?
        if try await !chain.isDeployed(plan.account) {
            deploymentHash = try await chain.deployAccount(plan)
        }

        progress(.linkingCard)
        var linkHash: String?
        if try await chain.pocketOwner(plan.pocket) != plan.account {
            // La signature de la carte ne vaut que 120 ledgers : trop près de la fin, l'envoi échouerait.
            if plan.setOwner.needsRefresh(currentLedger: try await chain.latestLedger()) {
                throw AccountCreationError.signatureExpired
            }
            linkHash = try await chain.linkCard(plan, signed: signatures[1])
        }

        progress(.confirming)
        guard try await chain.pocketOwner(plan.pocket) == plan.account else {
            throw AccountCreationError.notConfirmedOnChain("the card doesn't point to the account yet")
        }
        guard try await chain.hasCard(account: plan.account, publicKey: plan.card.publicKey) else {
            throw AccountCreationError.notConfirmedOnChain("the account doesn't list the card yet")
        }
        return CreationResult(account: plan.account, deploymentHash: deploymentHash, linkHash: linkHash)
    }
}

/// Branché sur `Core/` : lectures et simulations sur testnet, envois **uniquement** via le serveur de frais.
struct ChainAccountCreation: AccountCreationChain {
    let config: ChimpNetworkConfig
    let feeSigner: FeeSigner

    init(config: ChimpNetworkConfig, feeSigner: FeeSigner? = nil) {
        self.config = config
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private var client: SorobanClient { SorobanClient(config: config) }

    func verifyPossession(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws {
        let client = client
        let nfcNft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        try await CardPossession.verify(
            card: plan.card, challenge: plan.challenge, signed: signed,
            nfcNft: nfcNft, nftContract: plan.nftContract, source: try await client.account(config.feePayer)
        )
    }

    func isDeployed(_ account: String) async throws -> Bool {
        try await client.isDeployed(account)
    }

    func deployAccount(_ plan: AccountSetupPlan) async throws -> String {
        let client = client
        let transaction = try await ChimpAccountClient(client: client, config: config).deployTransaction(for: plan.card, salt: plan.accountSalt)
        return try await client.prepareAndSubmit(transaction, feeSigner: feeSigner)
    }

    func pocketOwner(_ pocket: String) async throws -> String {
        let client = client
        return try await PocketClient(client: client).owner(of: pocket, source: try await client.account(config.feePayer))
    }

    func latestLedger() async throws -> UInt32 {
        try await client.latestLedger()
    }

    func linkCard(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws -> String {
        try await CardMembershipClient(client: client, config: config).submitLink(
            plan.setOwner, pocket: plan.pocket, account: plan.account, curve: plan.card.curve,
            signed: signed, feeSigner: feeSigner
        )
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool {
        let client = client
        return try await ChimpAccountClient(client: client, config: config)
            .hasCard(account: account, publicKey: publicKey, source: try await client.account(config.feePayer))
    }
}

/// Fausse chaîne pour le simulateur et le catalogue : chaque étape attend un peu, rien ne part.
final class MockAccountCreationChain: AccountCreationChain, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        case success
        case networkErrorWhileLinking
        case feeSignerBusy
        case notConfirmed
        case signatureExpired
        var id: String { rawValue }
    }

    var scenario: Scenario
    var delay: Duration
    private(set) var deployed = false
    /// Compte vers lequel la fausse Pocket pointe une fois liée.
    private(set) var linkedAccount: String?
    private var failuresLeft = 1

    init(scenario: Scenario = .success, delay: Duration = .milliseconds(900)) {
        self.scenario = scenario
        self.delay = delay
    }

    func verifyPossession(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws {
        try await Task.sleep(for: delay)
    }

    func isDeployed(_ account: String) async throws -> Bool { deployed }

    func deployAccount(_ plan: AccountSetupPlan) async throws -> String {
        try await Task.sleep(for: delay)
        if scenario == .feeSignerBusy, failuresLeft > 0 {
            failuresLeft -= 1
            throw FeeSignerError.busy
        }
        deployed = true
        return String(repeating: "a", count: 64)
    }

    func pocketOwner(_ pocket: String) async throws -> String {
        linkedAccount ?? pocket
    }

    func latestLedger() async throws -> UInt32 {
        scenario == .signatureExpired ? 2_000 : 900
    }

    func linkCard(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws -> String {
        try await Task.sleep(for: delay)
        if scenario == .networkErrorWhileLinking, failuresLeft > 0 {
            failuresLeft -= 1
            throw StellarError.rpc("The request timed out.")
        }
        if scenario == .notConfirmed, failuresLeft > 0 {
            failuresLeft -= 1
            linkedAccount = plan.account
            throw StellarError.notConfirmed(hash: String(repeating: "b", count: 64))
        }
        linkedAccount = plan.account
        return String(repeating: "b", count: 64)
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool { linkedAccount == account }
}
