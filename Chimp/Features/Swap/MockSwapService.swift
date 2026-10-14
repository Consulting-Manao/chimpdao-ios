import Foundation

/// Swap factice (catalogue, simulateur, tests) : les tiroirs de `MockSendService`, un prix fixe, et des scénarios pour
/// chaque état (route introuvable, protocole indisponible, prix qui bouge, gros impact, issues après le tap).
final class MockSwapService: SwapService {
    enum QuoteScenario: String, CaseIterable, Identifiable {
        /// Devis normal (1 XLM = 0,2492 USDC, comme la maquette E3 : 400 XLM → 99,68 USDC).
        case normal
        /// Aucune route.
        case noRoute
        /// Le protocole ne répond pas.
        case protocolUnavailable
        /// Impact de prix de 8,12 % : avertissement fort.
        case bigImpact
        /// Le devis est bon, mais le prix a bougé quand on prépare la signature (« Price moved »).
        case priceMovesBeforeSigning
        /// Aquarius donne le meilleur prix (comparé à Soroswap).
        case aquariusBest
        /// Soroswap ne répond pas : le prix vient d'Aquarius seul, et l'écran le dit.
        case soroswapDown

        var id: String { rawValue }
    }

    /// Tiroirs, cartes, issues et taps : ceux d'Envoyer (mêmes noms, mêmes soldes).
    let send: MockSendService
    var quoteScenario: QuoteScenario
    /// Délai simulé du réseau.
    var delay: Duration

    /// « Price moves before signing » : le prix a baissé une fois (la préparation suivante passe, au nouveau prix).
    private var priceHasMoved = false

    private(set) var quoteCount = 0
    private(set) var prepareCount = 0
    private(set) var signCount = 0
    private(set) var submitCount = 0
    private(set) var checkCount = 0
    /// Erreur de la prochaine signature (tests), consommée une fois.
    var nextSignError: Error?
    var pendingSend: PendingSend?

    /// Prix fixes, en millionièmes : 1 XLM → 0,2492 USDC ; 1 USDC → 4,0128 XLM.
    static let rates: [SendAsset: Int128] = [.xlm: 249_200, .usdc: 4_012_800]

    init(
        quoteScenario: QuoteScenario = .normal,
        dataScenario: MockSendService.DataScenario = .standard,
        cardSetup: MockSendService.CardSetup = .allWithPin,
        resultScenario: MockSendService.ResultScenario = .sent,
        delay: Duration = .milliseconds(600)
    ) {
        send = MockSendService(dataScenario: dataScenario, cardSetup: cardSetup, resultScenario: resultScenario, delay: delay, nfcDelay: delay)
        self.quoteScenario = quoteScenario
        self.delay = delay
    }

    func fetchContext() async throws -> SwapContext {
        let context = try await send.fetchContext()
        return SwapContext(network: context.network, drawers: context.drawers)
    }

    func quote(given: SendAsset, received: SendAsset, amount: Decimal) async throws -> SwapQuoteSummary {
        quoteCount += 1
        try await Task.sleep(for: delay)
        switch quoteScenario {
        case .noRoute: throw SwapError.noRoute
        case .protocolUnavailable: throw SwapServiceError.protocolUnavailable(["Soroswap", "Aquarius"])
        case .normal, .bigImpact, .priceMovesBeforeSigning, .aquariusBest, .soroswapDown: break
        }
        let units = try SwapUnits.units(of: amount, asset: given)
        var out = units * (Self.rates[given] ?? 0) / 1_000_000
        if priceHasMoved { out = out * 994 / 1000 }
        let fromAquarius = quoteScenario == .aquariusBest || quoteScenario == .soroswapDown
        return SwapQuoteSummary(
            protocolID: "mock", protocolName: fromAquarius ? "Aquarius" : "Soroswap", given: given, received: received, amountIn: amount,
            expectedOutUnits: out, route: [given, received], routeContracts: [given.rawValue, received.rawValue],
            priceImpactBasisPoints: quoteScenario == .bigImpact ? 812 : 30,
            comparedProtocols: quoteScenario == .soroswapDown ? ["Aquarius"] : ["Soroswap", "Aquarius"],
            unavailableProtocols: quoteScenario == .soroswapDown ? ["Soroswap"] : []
        )
    }

    func prepare(_ draft: SwapDraft) async throws -> PreparedSwap {
        prepareCount += 1
        try await Task.sleep(for: delay)
        if draft.amount > draft.drawer.balance(of: draft.given) {
            throw PaymentClient.PaymentError.insufficientBalance(held: draft.drawer.balance(of: draft.given))
        }
        if quoteScenario == .priceMovesBeforeSigning, !priceHasMoved {
            priceHasMoved = true
            throw SwapError.slippageExceeded
        }
        return PreparedSwap(draft: draft, firstHopVenue: "mock-pair", contract: "mock-router")
    }

    func refreshedIfNeeded(_ prepared: PreparedSwap) async throws -> PreparedSwap { prepared }

    func readCard(for prepared: PreparedSwap) async throws -> SwapCardRead {
        let read = try await send.readCard(for: sendEquivalent(prepared))
        return SwapCardRead(check: read.check, signed: read.signed.map { SignedSwap(prepared: prepared, cardName: $0.cardName) })
    }

    func sign(_ prepared: PreparedSwap, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSwap {
        signCount += 1
        if let error = nextSignError {
            nextSignError = nil
            throw error
        }
        let signed = try await send.sign(sendEquivalent(prepared), pin: pin, onlyCard: onlyCard)
        return SignedSwap(prepared: prepared, cardName: signed.cardName)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? { send.knownCard(key) }

    func submit(_ signed: SignedSwap, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SwapReceipt {
        submitCount += 1
        let draft = signed.prepared.draft
        do {
            let receipt = try await send.submit(SignedSend(prepared: sendEquivalent(signed.prepared), cardName: signed.cardName), onProgress: onProgress)
            return SwapReceipt(
                summary: SwapSummary(draft), transactionHash: receipt.transactionHash, sentAt: receipt.sentAt,
                explorerURL: receipt.explorerURL, receivedAmount: draft.quote.expectedOut
            )
        }
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        checkCount += 1
        return try await send.check(trace)
    }

    func setPendingSend(_ pending: PendingSend?) throws {
        pendingSend = pending
    }

    func explorerURL(transactionHash: String) -> URL? { send.explorerURL(transactionHash: transactionHash) }

    /// Le même tiroir et le même montant, sous la forme qu'attend le service factice d'Envoyer (taps, issues).
    private func sendEquivalent(_ prepared: PreparedSwap) -> PreparedSend {
        let draft = prepared.draft
        let recipient = StellarRecipient(address: MockSendService.tomAddress, kind: .account, memoID: nil)
        return PreparedSend(draft: SendDraft(
            recipient: recipient, recipientName: draft.quote.protocolName, drawer: draft.drawer,
            asset: draft.given, amount: draft.amount, network: draft.network
        ))
    }
}
