import Foundation

/// Prêt XOXNO factice (catalogue, simulateur, tests) : les tiroirs de `MockSendService`, une position de 25 USDC dans Main
/// (20 USDC mis le 10 oct.), et des scénarios pour chaque état de la phase 7.
final class MockLendingService: VaultService {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Une position dans Main, tout peut sortir.
        case normal
        /// Aucune position.
        case noPosition
        /// Presque tout est prêté : 5 USDC peuvent sortir maintenant.
        case lentOut
        /// Les données de la position de Main ont expiré : à renouveler.
        case needsRenewal
        /// Une position avec dette (jamais créée par l'app) : montrée sans action.
        case hasDebt
        /// XOXNO a mis le marché en pause : ni dépôt ni retrait.
        case paused
        /// Le marché est gelé : plus de dépôt, les retraits restent possibles.
        case frozen
        /// XOXNO ne répond pas.
        case unavailable

        var id: String { rawValue }
    }

    let send: MockSendService
    var scenario: Scenario
    var delay: Duration
    var pendingSend: PendingSend?
    private(set) var prepareCount = 0

    static let pool = "CBSGF6QOQAMPFBEVSYPEQHSZRIHJ6RCGUPCRDMUX36DEKRWFAO2PZB5A"
    static let positionValue = Decimal(string: "25.0312")!
    static let depositDate = Date(timeIntervalSince1970: 1_791_626_400) // 10 oct. 2026
    static let availableWhenLentOut: Decimal = 5

    init(
        scenario: Scenario = .normal,
        cardSetup: MockSendService.CardSetup = .allWithPin,
        resultScenario: MockSendService.ResultScenario = .sent,
        delay: Duration = .milliseconds(600)
    ) {
        send = MockSendService(dataScenario: .standard, cardSetup: cardSetup, resultScenario: resultScenario, delay: delay, nfcDelay: delay)
        self.scenario = scenario
        self.delay = delay
    }

    var market: VaultInfo {
        VaultInfo(
            id: Self.pool, name: "XOXNO USDC", protocols: ["XOXNO"], asset: .usdc,
            invested: Decimal(string: "846.2")!, totalManaged: Decimal(string: "2477.89")!, kind: .lending,
            withdrawableNow: scenario == .lentOut ? Self.availableWhenLentOut : Decimal(string: "1578.69")!,
            depositsBlocked: scenario == .paused || scenario == .frozen, withdrawalsBlocked: scenario == .paused
        )
    }

    func fetchContext() async throws -> VaultContext {
        try await Task.sleep(for: delay)
        if scenario == .unavailable { throw VaultServiceError.vaultUnavailable }
        let context = try await send.fetchContext()
        var holdings: [VaultHolding] = []
        if scenario != .noPosition, let main = context.drawers.first(where: { $0.kind == .main }) {
            let condition: HoldingCondition = switch scenario {
            case .needsRenewal: .needsRenewal
            case .hasDebt: .hasDebt
            default: .movable
            }
            let value = condition == .needsRenewal ? 0 : Self.positionValue
            holdings.append(VaultHolding(
                drawerID: main.id, drawerAddress: main.address, shares: value, value: value,
                basis: VaultBasis(putIn: 20, since: Self.depositDate), readAt: .now, condition: condition
            ))
        }
        return VaultContext(network: context.network, drawers: context.drawers, vault: market, holdings: holdings)
    }

    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        try await Task.sleep(for: delay)
        let units = try SwapUnits.units(of: amount, asset: .usdc)
        return VaultQuote(action: .deposit, amount: amount, shares: TokenAmount(units), expectedOut: nil, minimumOut: nil, all: false)
    }

    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        try await Task.sleep(for: delay)
        let value = all ? Self.positionValue : amount
        guard value <= (market.withdrawableNow ?? 0) else { throw YieldError.notEnoughLiquidity }
        // 7 décimales : une position compte ses intérêts au-delà des 2 décimales du pavé.
        let units = Int128(try SACClient.units(of: value, keypadDecimals: 7))
        return VaultQuote(action: .withdraw, amount: value, shares: TokenAmount(units), expectedOut: TokenAmount(units), minimumOut: TokenAmount(units), all: all)
    }

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        prepareCount += 1
        try await Task.sleep(for: delay)
        if draft.action == .deposit, draft.amount > draft.drawer.balance(of: .usdc) {
            throw PaymentClient.PaymentError.insufficientBalance(held: draft.drawer.balance(of: .usdc))
        }
        if scenario == .paused || (scenario == .frozen && draft.action == .deposit) { throw YieldError.vaultUnavailable }
        return PreparedVault(draft: draft)
    }

    func refreshedIfNeeded(_ prepared: PreparedVault) async throws -> PreparedVault { prepared }

    func readCard(for prepared: PreparedVault) async throws -> VaultCardRead {
        let read = try await send.readCard(for: sendEquivalent(prepared))
        return VaultCardRead(check: read.check, signed: read.signed.map { SignedVault(prepared: prepared, cardName: $0.cardName) })
    }

    func sign(_ prepared: PreparedVault, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedVault {
        let signed = try await send.sign(sendEquivalent(prepared), pin: pin, onlyCard: onlyCard)
        return SignedVault(prepared: prepared, cardName: signed.cardName)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? { send.knownCard(key) }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        let draft = signed.prepared.draft
        let receipt = try await send.submit(SignedSend(prepared: sendEquivalent(signed.prepared), cardName: signed.cardName), onProgress: onProgress)
        return VaultReceipt(
            summary: VaultSummary(draft), transactionHash: receipt.transactionHash, sentAt: receipt.sentAt, explorerURL: receipt.explorerURL,
            shares: nil, received: draft.action == .withdraw ? (draft.quote.expected ?? draft.amount) : nil
        )
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck { try await send.check(trace) }

    func setPendingSend(_ pending: PendingSend?) throws { pendingSend = pending }

    func explorerURL(transactionHash: String) -> URL? { send.explorerURL(transactionHash: transactionHash) }

    private func sendEquivalent(_ prepared: PreparedVault) -> PreparedSend {
        let draft = prepared.draft
        let recipient = StellarRecipient(address: MockSendService.tomAddress, kind: .account, memoID: nil)
        return PreparedSend(draft: SendDraft(
            recipient: recipient, recipientName: draft.vault.name, drawer: draft.drawer,
            asset: draft.vault.asset, amount: draft.amount, network: draft.network
        ))
    }
}
