import Foundation
import stellarsdk

/// Ce dont l'ajout d'une carte a besoin sur la chaîne. `ChainAddCardService` (testnet, `CardMembershipClient` de
/// `Core/`) dans l'app ; `MockAddCardService` pour le simulateur, le catalogue et les tests.
protocol AddCardService {
    /// Nouvelle carte lue : peut-elle entrer dans ce compte ? (`assertAddable`)
    func checkNewCard(_ card: ChipKeyInfo, account: String) async throws -> CardMembershipClient.AddableCard
    /// A8 (rejoindre depuis l'onboarding) : de quel compte cette carte est-elle membre ? `nil` : d'aucun.
    /// `hint` : compte mémorisé sur le téléphone pour elle. Réseau incertain : erreur (jamais « d'aucun »).
    func account(ofMember card: ChipKeyInfo, hint: String?) async throws -> String?
    /// Entrée `set_owner` à faire signer par la nouvelle carte.
    func declareLink(pocket: String, account: String) async throws -> DeclaredAuthorization
    func latestLedger() async throws -> UInt32
    /// Envoie `set_owner` ; renvoie le hash.
    func submitLink(_ declared: DeclaredAuthorization, pocket: String, account: String, curve: ChipCurve, signed: ChipSignedDigest) async throws -> String
    func pocketOwner(_ pocket: String) async throws -> String
    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool
    /// `add_card` à faire signer par une carte du compte.
    func prepareAddCard(account: String, newCard: ChipPublicKey, curve: ChipCurve) async throws -> CardMembershipClient.PreparedAddCard
    func needsRefresh(_ prepared: CardMembershipClient.PreparedAddCard) async throws -> Bool
    /// Envoie `add_card` ; renvoie le hash.
    func submitAddCard(_ prepared: CardMembershipClient.PreparedAddCard, signed: CardSignatures) async throws -> String
}

/// Branché sur `Core/` : lectures et simulations sur testnet, envois **uniquement** via le serveur de frais.
struct ChainAddCardService: AddCardService {
    let config: ChimpNetworkConfig
    let feeSigner: FeeSigner

    init(config: ChimpNetworkConfig = .testnet, feeSigner: FeeSigner? = nil) {
        self.config = config
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private var membership: CardMembershipClient { CardMembershipClient(client: SorobanClient(config: config), config: config) }

    func checkNewCard(_ card: ChipKeyInfo, account: String) async throws -> CardMembershipClient.AddableCard {
        try await membership.checkAddable(card.publicKey, to: account)
    }

    /// Résolution §3.4 (`resolveAccountForCard`) : seule une carte que `has_card` confirme donne son compte.
    func account(ofMember card: ChipKeyInfo, hint: String?) async throws -> String? {
        switch try await ChainCardResolver(config: config).resolve(card.publicKey, hint: hint) {
        case .signIn(let account, _): return account
        case .unknown(let detail): throw StellarError.rpc(detail)
        case .newCard, .enrolled, .orphan: return nil
        }
    }

    func declareLink(pocket: String, account: String) async throws -> DeclaredAuthorization {
        try await membership.declareLink(pocket: pocket, account: account)
    }

    func latestLedger() async throws -> UInt32 {
        try await SorobanClient(config: config).latestLedger()
    }

    func submitLink(_ declared: DeclaredAuthorization, pocket: String, account: String, curve: ChipCurve, signed: ChipSignedDigest) async throws -> String {
        try await membership.submitLink(declared, pocket: pocket, account: account, curve: curve, signed: signed, feeSigner: feeSigner)
    }

    func pocketOwner(_ pocket: String) async throws -> String {
        try await membership.pocketOwner(pocket)
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool {
        try await membership.hasCard(account: account, publicKey: publicKey)
    }

    func prepareAddCard(account: String, newCard: ChipPublicKey, curve: ChipCurve) async throws -> CardMembershipClient.PreparedAddCard {
        try await membership.prepareAddCard(account: account, newCard: newCard, curve: curve)
    }

    func needsRefresh(_ prepared: CardMembershipClient.PreparedAddCard) async throws -> Bool {
        try await membership.needsRefresh(prepared)
    }

    func submitAddCard(_ prepared: CardMembershipClient.PreparedAddCard, signed: CardSignatures) async throws -> String {
        try await membership.submitAddCard(prepared, signed: signed, feeSigner: feeSigner)
    }
}

/// Fausse chaîne : chaque réponse est réglable, rien ne part. La Pocket et le compte « bougent » comme sur la chaîne
/// (`set_owner` puis `add_card`), pour que la reprise se teste.
final class MockAddCardService: AddCardService, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Carte neuve, tout passe.
        case success
        /// La carte est déjà dans ce compte.
        case alreadyInAccount
        /// La carte est dans un autre compte.
        case otherAccount
        /// Carte jamais enregistrée par ChimpDAO.
        case notEnrolled
        /// Le réseau tombe pendant `add_card` (une fois) : « Try again » reprend.
        case networkWhileAdding
        /// Le serveur de frais est occupé pendant le lien (une fois).
        case feeHelperBusy

        var id: String { rawValue }
    }

    var scenario: Scenario
    var delay: Duration
    /// Compte dont la carte membre fait partie (A8).
    var memberAccount: String? = MockOnboardingService.memberAccount
    /// Cartes du compte (clés acceptées pour `add_card`).
    var members: [ChipPublicKey] = [MockChipReader.p256Key]
    /// Ledger courant (tests : faire expirer une signature).
    var ledger: UInt32 = 1_000
    private(set) var owner: [String: String] = [:]
    private(set) var memberships: Set<String> = []
    private(set) var linkCount = 0
    private(set) var addCount = 0
    private var failuresLeft = 1

    init(scenario: Scenario = .success, delay: Duration = .milliseconds(900)) {
        self.scenario = scenario
        self.delay = delay
    }

    /// Pocket prévue de la carte (adresse valide, calculée comme la factory ; aucun contrat derrière).
    static func pocket(for card: ChipPublicKey) -> String {
        (try? PocketFactoryClient.predictedPocket(factory: ChimpNetworkConfig.testnet.contracts.factory, publicKey: card, network: .testnet)) ?? ""
    }

    func checkNewCard(_ card: ChipKeyInfo, account: String) async throws -> CardMembershipClient.AddableCard {
        try await Task.sleep(for: delay)
        switch scenario {
        case .alreadyInAccount: throw CardMembershipClient.MembershipError.alreadyInAccount
        case .otherAccount: throw CardMembershipClient.MembershipError.belongsToAnotherAccount(MockOnboardingService.memberAccount)
        case .notEnrolled: throw CardMembershipClient.MembershipError.notEnrolled
        default: break
        }
        let pocket = Self.pocket(for: card.publicKey)
        let currentOwner = owner[pocket] ?? pocket
        let state = CardState(pocket: pocket, pocketOwner: currentOwner, nftContract: nil, tokenID: 913, nftOwner: pocket)
        return CardMembershipClient.AddableCard(
            state: state, pocket: pocket, needsLink: currentOwner != account, isMember: memberships.contains(card.publicKey.hex)
        )
    }

    func account(ofMember card: ChipKeyInfo, hint: String?) async throws -> String? {
        try await Task.sleep(for: delay)
        return memberAccount
    }

    func declareLink(pocket: String, account: String) async throws -> DeclaredAuthorization {
        try await Task.sleep(for: delay)
        return try PocketClient.declareSetOwner(
            pocket: pocket, newOwner: account, passphrase: ChimpNetworkConfig.testnet.passphrase, currentLedger: ledger, nonce: 42
        )
    }

    func latestLedger() async throws -> UInt32 { ledger }

    func submitLink(_ declared: DeclaredAuthorization, pocket: String, account: String, curve: ChipCurve, signed: ChipSignedDigest) async throws -> String {
        try await Task.sleep(for: delay)
        linkCount += 1
        if scenario == .feeHelperBusy, failuresLeft > 0 {
            failuresLeft -= 1
            throw FeeSignerError.busy
        }
        owner[pocket] = account
        return String(repeating: "c", count: 64)
    }

    func pocketOwner(_ pocket: String) async throws -> String { owner[pocket] ?? pocket }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool { memberships.contains(publicKey.hex) }

    func prepareAddCard(account: String, newCard: ChipPublicKey, curve: ChipCurve) async throws -> CardMembershipClient.PreparedAddCard {
        try await Task.sleep(for: delay)
        let declared = try DeclaredAuthorization(
            authorizer: account,
            invocation: try SorobanAuth.contractInvocation(
                contract: account, function: "add_card",
                arguments: CardMembershipClient.addCardArguments(publicKey: newCard, curve: curve)
            ),
            passphrase: ChimpNetworkConfig.testnet.passphrase, expirationLedger: ledger + SorobanAuth.expirationLedgers, nonce: 7
        )
        return CardMembershipClient.PreparedAddCard(
            account: account, newCard: newCard, newCurve: curve,
            authorization: AuthorizedCall.AccountEntry(
                entry: declared.entry, digest: declared.digest, expirationLedger: declared.expirationLedger, simulatedLedger: ledger
            ),
            acceptedKeys: members.filter { $0 != newCard }
        )
    }

    func needsRefresh(_ prepared: CardMembershipClient.PreparedAddCard) async throws -> Bool {
        SorobanAuth.needsRefresh(expirationLedger: prepared.authorization.expirationLedger, currentLedger: ledger)
    }

    func submitAddCard(_ prepared: CardMembershipClient.PreparedAddCard, signed: CardSignatures) async throws -> String {
        try await Task.sleep(for: delay)
        addCount += 1
        guard prepared.acceptedKeys.contains(signed.card.publicKey) else { throw ChipError.cardNotAccepted(tapped: signed.card.publicKey) }
        if scenario == .networkWhileAdding, failuresLeft > 0 {
            failuresLeft -= 1
            throw StellarError.rpc("The request timed out.")
        }
        memberships.insert(prepared.newCard.hex)
        return String(repeating: "d", count: 64)
    }
}
