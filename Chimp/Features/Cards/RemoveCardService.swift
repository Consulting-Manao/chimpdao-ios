import Foundation

/// Ce dont le retrait d'une carte (G6) et la carte perdue (G7) ont besoin sur la chaîne. `ChainRemoveCardService`
/// (testnet, `CardMembershipClient` de `Core/`) dans l'app ; `MockRemoveCardService` pour le simulateur et les tests.
protocol RemoveCardService {
    /// `cards()` du compte, relu juste avant la revue (la dernière carte ne peut pas partir).
    func members(of account: String) async throws -> [ChipPublicKey]
    /// `remove_card` simulé (ordre 2), prêt pour le tap.
    func prepareRemoveCard(account: String, card: ChipPublicKey, signer: CardMembershipClient.RemovalSigner) async throws -> CardMembershipClient.PreparedRemoveCard
    func needsRefresh(_ prepared: CardMembershipClient.PreparedRemoveCard) async throws -> Bool
    /// Envoie `remove_card` ; renvoie le hash.
    func submitRemoveCard(_ prepared: CardMembershipClient.PreparedRemoveCard, signed: CardSignatures) async throws -> String
    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool
}

/// Branché sur `Core/` : lectures et simulations sur testnet, envoi **uniquement** via le serveur de frais.
struct ChainRemoveCardService: RemoveCardService {
    let config: ChimpNetworkConfig
    let feeSigner: FeeSigner

    init(config: ChimpNetworkConfig, feeSigner: FeeSigner? = nil) {
        self.config = config
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private var client: SorobanClient { SorobanClient(config: config) }
    private var membership: CardMembershipClient { CardMembershipClient(client: client, config: config) }

    func members(of account: String) async throws -> [ChipPublicKey] {
        try await ChimpAccountClient(client: client, config: config)
            .cards(account: account, source: try await client.account(config.feePayer))
            .map(\.publicKey)
    }

    func prepareRemoveCard(account: String, card: ChipPublicKey, signer: CardMembershipClient.RemovalSigner) async throws -> CardMembershipClient.PreparedRemoveCard {
        try await membership.prepareRemoveCard(account: account, card: card, signer: signer)
    }

    func needsRefresh(_ prepared: CardMembershipClient.PreparedRemoveCard) async throws -> Bool {
        try await membership.needsRefresh(prepared)
    }

    func submitRemoveCard(_ prepared: CardMembershipClient.PreparedRemoveCard, signed: CardSignatures) async throws -> String {
        try await membership.submitRemoveCard(prepared, signed: signed, feeSigner: feeSigner)
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool {
        try await membership.hasCard(account: account, publicKey: publicKey)
    }
}

/// Fausse chaîne : le compte « perd » la carte comme sur la chaîne, rien ne part. Réglable pour chaque cas d'erreur.
final class MockRemoveCardService: RemoveCardService, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Tout passe.
        case success
        /// Stellar injoignable pendant la simulation (avant le tap).
        case networkBeforeTap
        /// Stellar injoignable à l'envoi, une fois.
        case networkWhileRemoving
        /// Le compte refuse : dernière carte (`#303`), vu seulement à l'envoi.
        case lastCardAtSubmit
        /// Envoyé, mais la relecture voit encore la carte (pas encore confirmé).
        case notConfirmedYet

        var id: String { rawValue }
    }

    let scenario: Scenario
    var delay: Duration
    private(set) var memberKeys: [ChipPublicKey]
    private(set) var submitCount = 0
    private var failuresLeft = 1
    private let ledger: UInt32 = 1000

    init(members: [ChipPublicKey], scenario: Scenario = .success, delay: Duration = .milliseconds(600)) {
        self.memberKeys = members
        self.scenario = scenario
        self.delay = delay
    }

    func members(of account: String) async throws -> [ChipPublicKey] { memberKeys }

    func prepareRemoveCard(account: String, card: ChipPublicKey, signer: CardMembershipClient.RemovalSigner) async throws -> CardMembershipClient.PreparedRemoveCard {
        try await Task.sleep(for: delay)
        if scenario == .networkBeforeTap { throw StellarError.rpc("The request timed out.") }
        let accepted = try CardMembershipClient.removalSigners(members: memberKeys, card: card, signer: signer)
        let declared = try DeclaredAuthorization(
            authorizer: account,
            invocation: try SorobanAuth.contractInvocation(
                contract: account, function: "remove_card", arguments: CardMembershipClient.removeCardArguments(publicKey: card)
            ),
            passphrase: ChimpNetworkConfig.testnet.passphrase, expirationLedger: ledger + SorobanAuth.expirationLedgers, nonce: 7
        )
        return CardMembershipClient.PreparedRemoveCard(
            account: account, removedCard: card, signer: signer,
            authorization: AuthorizedCall.AccountEntry(
                entry: declared.entry, digest: declared.digest, expirationLedger: declared.expirationLedger, simulatedLedger: ledger
            ),
            acceptedKeys: accepted
        )
    }

    func needsRefresh(_ prepared: CardMembershipClient.PreparedRemoveCard) async throws -> Bool {
        SorobanAuth.needsRefresh(expirationLedger: prepared.authorization.expirationLedger, currentLedger: ledger)
    }

    func submitRemoveCard(_ prepared: CardMembershipClient.PreparedRemoveCard, signed: CardSignatures) async throws -> String {
        try await Task.sleep(for: delay)
        submitCount += 1
        guard prepared.acceptedKeys.contains(signed.card.publicKey) else { throw ChipError.cardNotAccepted(tapped: signed.card.publicKey) }
        switch scenario {
        case .networkWhileRemoving where failuresLeft > 0:
            failuresLeft -= 1
            throw StellarError.rpc("The request timed out.")
        case .lastCardAtSubmit:
            throw CardMembershipClient.MembershipError.lastCard
        case .notConfirmedYet:
            return String(repeating: "e", count: 64)
        default:
            memberKeys.removeAll { $0 == prepared.removedCard }
            return String(repeating: "e", count: 64)
        }
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool { memberKeys.contains(publicKey) }
}
