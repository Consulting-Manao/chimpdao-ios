import Foundation

/// Vault factice (catalogue, simulateur, tests) : les tiroirs de `MockSendService`, une position dans Main (maquette F1 :
/// 50 XLM mis le 22 sept., 50.12 XLM aujourd'hui), un prix de part fixe, et des scénarios pour chaque état.
final class MockVaultService: VaultService {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Une position dans Main.
        case normal
        /// Aucune position (Grow vide).
        case noPosition
        /// Le vault ne répond pas (F3b).
        case vaultUnavailable
        /// Le vault rend moins que le minimum entre la vérification et la signature (retrait) : rien n'est signé.
        case priceMovesBeforeSigning
        /// Une valeur lue n'est pas vraisemblable : refusée, rien n'est affiché comme un montant.
        case implausible
        /// Presque tout est prêté sur Blend : le vault ne peut rendre que 30 XLM tout de suite (retrait refusé au-delà).
        case lentOut

        var id: String { rawValue }
    }

    /// Tiroirs, cartes, issues et taps : ceux d'Envoyer.
    let send: MockSendService
    var scenario: Scenario
    var delay: Duration

    private var priceHasMoved = false
    private(set) var quoteCount = 0
    private(set) var prepareCount = 0
    /// Chaque autorisation signée envoyée, dans l'ordre (tests de la revue F3).
    private(set) var submitted: [SignedVault] = []
    private(set) var signCount = 0
    private(set) var submitCount = 0
    var nextSignError: Error?
    var pendingSend: PendingSend?

    static let vaultAddress = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    /// 1 part = 1,0024 XLM (maquette : 50 XLM ≈ 48.73 parts ne tombe pas juste ; prix simple pour le catalogue).
    static let xlmPerShare = Decimal(string: "1.0024")!
    static let depositDate = Date(timeIntervalSince1970: 1_790_067_720) // 22 sept. 2026, 09:02 UTC

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

    static let vault = VaultInfo(
        id: vaultAddress, name: "DeFindex XLM", protocols: ["DeFindex", "Blend"], asset: .xlm,
        invested: 0, totalManaged: Decimal(string: "49557.2426222")!
    )

    /// `lentOut` : tout est prêté sauf 30 XLM.
    static let availableWhenLentOut: Decimal = 30

    private var vault: VaultInfo {
        guard scenario == .lentOut else { return Self.vault }
        return VaultInfo(
            id: Self.vault.id, name: Self.vault.name, protocols: Self.vault.protocols, asset: Self.vault.asset,
            invested: Self.vault.totalManaged - Self.availableWhenLentOut, totalManaged: Self.vault.totalManaged
        )
    }

    func fetchContext() async throws -> VaultContext {
        try await Task.sleep(for: delay)
        if scenario == .vaultUnavailable { throw VaultServiceError.vaultUnavailable }
        if scenario == .implausible { throw YieldError.implausibleValue }
        let context = try await send.fetchContext()
        var holdings: [VaultHolding] = []
        if scenario != .noPosition, let main = context.drawers.first(where: { $0.kind == .main }) {
            let shares = Decimal(string: "50")! / Self.xlmPerShare
            holdings.append(VaultHolding(
                drawerID: main.id, drawerAddress: main.address, shares: shares, value: Decimal(string: "50.12")!,
                basis: VaultBasis(putIn: 50, since: Self.depositDate), readAt: .now
            ))
        }
        return VaultContext(network: context.network, drawers: context.drawers, vault: vault, holdings: holdings)
    }

    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        quoteCount += 1
        try await Task.sleep(for: delay)
        if scenario == .vaultUnavailable { throw VaultServiceError.vaultUnavailable }
        let shares = try SwapUnits.units(of: (amount / Self.xlmPerShare).truncated(to: 7), asset: .xlm)
        return VaultQuote(action: .deposit, amount: amount, shares: TokenAmount(shares), expectedOut: nil, minimumOut: nil, all: false)
    }

    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        quoteCount += 1
        try await Task.sleep(for: delay)
        if scenario == .vaultUnavailable { throw VaultServiceError.vaultUnavailable }
        let value = all ? Decimal(string: "50.12")! : amount
        // Après « le vault a bougé » : il rend un peu moins (0,2 %).
        let paid = priceHasMoved ? (value * Decimal(string: "0.998")!).truncated(to: 7) : value
        let expected = try SwapUnits.units(of: paid, asset: .xlm)
        let shares = try SwapUnits.units(of: (value / Self.xlmPerShare).truncated(to: 7), asset: .xlm)
        return VaultQuote(
            action: .withdraw, amount: value, shares: TokenAmount(shares), expectedOut: TokenAmount(expected),
            minimumOut: TokenAmount(Slippage.minimum(of: expected, basisPoints: DeFindexAdapter.withdrawSlippageBasisPoints)), all: all
        )
    }

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        prepareCount += 1
        try await Task.sleep(for: delay)
        if draft.action == .deposit, draft.amount > draft.drawer.balance(of: draft.vault.asset) {
            throw PaymentClient.PaymentError.insufficientBalance(held: draft.drawer.balance(of: draft.vault.asset))
        }
        if scenario == .priceMovesBeforeSigning, draft.action == .withdraw, !priceHasMoved {
            priceHasMoved = true
            throw VaultServiceError.priceMoved
        }
        if scenario == .lentOut, draft.action == .withdraw, (draft.quote.expected ?? draft.amount) > Self.availableWhenLentOut {
            throw YieldError.notEnoughLiquidity
        }
        return PreparedVault(draft: draft)
    }

    func refreshedIfNeeded(_ prepared: PreparedVault) async throws -> PreparedVault { prepared }

    func readCard(for prepared: PreparedVault) async throws -> VaultCardRead {
        let read = try await send.readCard(for: sendEquivalent(prepared))
        return VaultCardRead(check: read.check, signed: read.signed.map { SignedVault(prepared: prepared, cardName: $0.cardName) })
    }

    func sign(_ prepared: PreparedVault, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedVault {
        signCount += 1
        if let error = nextSignError {
            nextSignError = nil
            throw error
        }
        let signed = try await send.sign(sendEquivalent(prepared), pin: pin, onlyCard: onlyCard)
        return SignedVault(prepared: prepared, cardName: signed.cardName)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? { send.knownCard(key) }

    func trace(for signed: SignedVault) throws -> PaymentTrace {
        try send.trace(for: SignedSend(prepared: sendEquivalent(signed.prepared), cardName: signed.cardName))
    }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        submitted.append(signed)
        submitCount += 1
        let draft = signed.prepared.draft
        let receipt = try await send.submit(SignedSend(prepared: sendEquivalent(signed.prepared), cardName: signed.cardName), onProgress: onProgress)
        return VaultReceipt(
            summary: VaultSummary(draft), transactionHash: receipt.transactionHash, sentAt: receipt.sentAt, explorerURL: receipt.explorerURL,
            shares: draft.quote.sharesAmount,
            received: draft.action == .withdraw ? (draft.quote.expected ?? draft.amount) + Decimal(string: "0.01")! : nil
        )
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        try await send.check(trace)
    }

    func setPendingSend(_ pending: PendingSend?) throws {
        pendingSend = pending
    }

    func explorerURL(transactionHash: String) -> URL? { send.explorerURL(transactionHash: transactionHash) }

    /// Le même tiroir et le même montant, sous la forme qu'attend le service factice d'Envoyer (taps, issues).
    private func sendEquivalent(_ prepared: PreparedVault) -> PreparedSend {
        let draft = prepared.draft
        let recipient = StellarRecipient(address: MockSendService.tomAddress, kind: .account, memoID: nil)
        return PreparedSend(draft: SendDraft(
            recipient: recipient, recipientName: draft.vault.name, drawer: draft.drawer,
            asset: draft.vault.asset, amount: draft.amount, network: draft.network
        ))
    }
}
