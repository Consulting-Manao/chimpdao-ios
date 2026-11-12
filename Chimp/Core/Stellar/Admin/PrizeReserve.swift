#if CHIMP_ADMIN
import Foundation
import stellarsdk

/// « Reserve money for a card » (Chimp Admin, D5) : `prize.deposit(admin, montant, token_id)`, signé et payé par la clé
/// admin, testnet uniquement. L'argent part de l'admin vers le contrat, mis de côté pour la puce de la carte ; seule cette
/// carte pourra le retirer vers son wallet. Aucun remboursement n'existe dans le contrat : un dépôt ne se reprend pas.
protocol PrizeReserving {
    /// Ce que le contrat sait de la carte : son numéro de NFT dans la campagne du contrat, et ce qui est déjà mis de côté.
    func reservation(for card: ChipPublicKey) async throws -> PrizeReservation
    /// Dépose `amount` (unités on-chain) pour la carte, puis relit ce qui est mis de côté.
    func reserve(_ amount: TokenAmount, for card: ChipPublicKey) async throws -> PrizeReserveResult
}

struct PrizeReservation: Equatable, Sendable {
    let tokenID: UInt32
    let reserved: TokenAmount
}

struct PrizeReserveResult: Equatable, Sendable {
    let transactionHash: String
    /// Total mis de côté après le dépôt (relu sur la chaîne), `nil` si la relecture a échoué.
    let reserved: TokenAmount?
}

enum PrizeReserveError: Error, Equatable, LocalizedError {
    /// Pas de contrat `prize` dans la configuration (pas encore déployé).
    case noContract
    /// La simulation demande une autorisation à quelqu'un d'autre que l'admin : rien n'est signé.
    case unexpectedAuthorization

    var errorDescription: String? {
        switch self {
        case .noContract: "The prize contract isn't deployed on this network yet."
        case .unexpectedAuthorization: "The deposit asked for someone else's authorization, so nothing was signed."
        }
    }
}

struct ChainPrizeReserving: PrizeReserving {
    let config: ChimpNetworkConfig
    let keyStore: AdminKeyStore
    private let client: SorobanClient
    private let contract: String

    init(config: ChimpNetworkConfig, keyStore: AdminKeyStore) throws {
        try CardEnrolment.requireTestnet(config)
        guard let contract = config.contracts.prize else { throw PrizeReserveError.noContract }
        self.config = config
        self.keyStore = keyStore
        self.contract = contract
        client = SorobanClient(config: config)
    }

    private var prize: PrizeClient { PrizeClient(client: client, config: config, contract: contract) }

    func reservation(for card: ChipPublicKey) async throws -> PrizeReservation {
        let source = try await client.account(config.feePayer)
        let nfc = try await prize.nfcContract(source: source)
        let value = try await client.readValue(source: source, contract: nfc, function: "token_id", arguments: [.bytes(card.bytes)])
        guard let tokenID = value.u32 else { throw StellarError.invalidResponse("token_id returned \(value)") }
        return PrizeReservation(tokenID: tokenID, reserved: try await prize.reserved(for: card, source: source))
    }

    func reserve(_ amount: TokenAmount, for card: ChipPublicKey) async throws -> PrizeReserveResult {
        guard amount.units > 0 else { throw PrizeContract.PrizeError.invalidAmount }
        guard let admin = try keyStore.keyPair() else { throw FundingError.noAdminKey }
        let tokenID = try await reservation(for: card).tokenID
        let transaction = try client.contractCall(
            source: try await client.account(admin.accountId), contract: contract, function: "deposit",
            arguments: try PrizeContract.depositArguments(from: admin.accountId, amount: amount, tokenID: tokenID)
        )
        let simulation = try await client.simulate(transaction)
        // L'admin autorise comme source de la transaction : toute autre autorisation demandée est refusée.
        for entry in simulation.sorobanAuth ?? [] {
            if case .sourceAccount = entry.credentials { continue }
            throw PrizeReserveError.unexpectedAuthorization
        }
        try client.assemble(transaction, with: simulation)
        try transaction.sign(keyPair: admin, network: client.network)
        let hash = try await client.submitAndWait(transaction)
        let reserved = try? await prize.reserved(for: card, source: try await client.account(config.feePayer))
        return PrizeReserveResult(transactionHash: hash, reserved: reserved)
    }
}

/// Faux dépôts pour le simulateur et les tests : aucune requête réseau.
final class MockPrizeReserving: PrizeReserving, @unchecked Sendable {
    var delay: Duration = .milliseconds(500)
    var failing = false
    private(set) var reserved: [ChipPublicKey: TokenAmount] = [:]

    init(failing: Bool = false) {
        self.failing = failing
    }

    func reservation(for card: ChipPublicKey) async throws -> PrizeReservation {
        try await Task.sleep(for: delay)
        return PrizeReservation(tokenID: 7, reserved: reserved[card] ?? 0)
    }

    func reserve(_ amount: TokenAmount, for card: ChipPublicKey) async throws -> PrizeReserveResult {
        try await Task.sleep(for: delay)
        if failing { throw StellarError.simulationFailed("HostError: Error(Contract, #10)") }
        let total = TokenAmount((reserved[card]?.units ?? 0) + amount.units)
        reserved[card] = total
        return PrizeReserveResult(transactionHash: String(repeating: "0", count: 64), reserved: total)
    }
}
#endif
