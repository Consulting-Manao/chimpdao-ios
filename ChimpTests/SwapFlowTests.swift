import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 2 : machine à états du parcours Swap, avec le service factice (mêmes tiroirs qu'Envoyer : Main a
/// 400 XLM et 720 USDC, Jungle 62,50 USDC, Banana 120 XLM et 72,50 USDC ; 1 XLM = 0,2492 USDC).
struct SwapFlowTests {
    private func model(
        _ quote: MockSwapService.QuoteScenario = .normal,
        result: MockSendService.ResultScenario = .sent,
        order: SigningOrder = .pinThenTap,
        drawerID: String? = nil
    ) async -> (SwapFlowModel, MockSwapService) {
        let service = MockSwapService(quoteScenario: quote, resultScenario: result, delay: .zero)
        // Le service factice compte l'attente en secondes entières.
        service.send.authorizationWait = .seconds(1)
        let model = SwapFlowModel(service: service, signingOrder: order, initialDrawerID: drawerID, quoteDebounce: .zero)
        await model.loadIfNeeded()
        return (model, service)
    }

    /// Montant tapé et devis reçu.
    private func quoted(_ model: SwapFlowModel, _ amount: Decimal) async {
        model.setAmount(amount)
        await model.refreshQuote()
    }

    /// Prêt sur la vérification : 400 XLM → USDC depuis Main (ou `amount` depuis le tiroir choisi).
    private func reviewReady(
        _ quote: MockSwapService.QuoteScenario = .normal,
        result: MockSendService.ResultScenario = .sent,
        drawerID: String? = nil,
        amount: Decimal = 400
    ) async -> (SwapFlowModel, MockSwapService) {
        let (model, service) = await self.model(quote, result: result, drawerID: drawerID)
        await quoted(model, amount)
        model.continueToReview()
        return (model, service)
    }

    private func waitUntil(seconds: Double = 2, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isSent(_ model: SwapFlowModel) -> Bool {
        if case .finished(.sent) = model.stage { return true }
        return false
    }

    /// PIN puis tap jusqu'au bout.
    private func signWithPin(_ model: SwapFlowModel) async {
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
    }

    // MARK: Devis en direct

    @Test("Devis : 400 XLM → 99,68 USDC (quantités seulement), minimum au slippage par défaut 0,5 % = 99,1816 USDC")
    func liveQuote() async throws {
        let (model, _) = await model()
        #expect(model.quoteState == .idle)
        await quoted(model, 400)
        let quote = try #require(model.currentQuote)
        #expect(quote.expectedOut == Decimal(string: "99.68"))
        #expect(quote.route == [.xlm, .usdc])
        #expect(quote.protocolName == "Soroswap")
        #expect(model.currentMinimum == Decimal(string: "99.1816"))
        #expect(model.canReview)
    }

    @Test("Le devis vaut pour un montant : changer le montant l'invalide jusqu'au suivant")
    func quoteFollowsAmount() async {
        let (model, service) = await model()
        await quoted(model, 10)
        model.setAmount(20)
        #expect(model.currentQuote == nil)
        #expect(!model.canReview)
        await model.refreshQuote()
        #expect(model.currentQuote?.amountIn == 20)
        #expect(service.quoteCount >= 2)
    }

    @Test("Montant effacé : plus de devis")
    func zeroAmount() async {
        let (model, _) = await model()
        await quoted(model, 10)
        model.setAmount(0)
        #expect(model.quoteState == .idle)
    }

    @Test("Route introuvable et protocole indisponible : devis en échec, vérification impossible")
    func quoteFailures() async {
        for (scenario, issue) in [(MockSwapService.QuoteScenario.noRoute, SwapFlowModel.QuoteIssue.noRoute), (.protocolUnavailable, .protocolUnavailable)] {
            let (model, _) = await model(scenario)
            await quoted(model, 10)
            #expect(model.quoteState == .failed(issue))
            #expect(!model.canReview)
        }
    }

    @Test("Solde insuffisant : signalé, vérification impossible")
    func insufficientBalance() async {
        let (model, _) = await model()
        await quoted(model, 401)
        #expect(model.amountIssue == .insufficient(drawer: "Main account", available: 400, asset: .xlm))
        #expect(!model.canReview)
    }

    @Test("Impact de prix au-delà de 5 % : avertissement")
    func priceImpactWarning() async {
        let (model, _) = await model(.bigImpact)
        await quoted(model, 10)
        #expect(model.currentQuote?.needsPriceImpactWarning == true)
        let (normal, _) = await self.model()
        await quoted(normal, 10)
        #expect(normal.currentQuote?.needsPriceImpactWarning == false)
    }

    @Test("⇅ : actifs échangés, montant ramené aux décimales de l'USDC, nouveau devis")
    func flip() async {
        let (model, _) = await model()
        await quoted(model, Decimal(string: "1.2345")!)
        model.flipAssets()
        #expect(model.given == .usdc)
        #expect(model.received == .xlm)
        #expect(model.amount.value == Decimal(string: "1.23"))
        await model.refreshQuote()
        #expect(model.currentQuote?.given == .usdc)
    }

    @Test("Slippage : 3 % accepté (minimum plus bas), 3,01 % refusé (la valeur précédente reste)")
    func slippage() async {
        let (model, _) = await model()
        await quoted(model, 400)
        #expect(model.setSlippage(300))
        #expect(model.currentMinimum == Decimal(string: "96.6896"))
        #expect(!model.setSlippage(301))
        #expect(model.slippageBasisPoints == 300)
        #expect(!model.setSlippage(-1))
    }

    @Test("La vérification fige le devis, le slippage et le tiroir : minimum signé exact")
    func draftIsFrozen() async throws {
        let (model, _) = await reviewReady()
        let draft = try #require(model.draft)
        #expect(model.isReviewPresented)
        #expect(draft.amount == 400)
        #expect(draft.minimumOut == Decimal(string: "99.1816"))
        #expect(draft.drawer.id == "main")
    }

    // MARK: Signature

    @Test("Main, PIN puis tap : une préparation, une signature, un envoi, puis le reçu (ce qui est parti, ce qui est arrivé)")
    func swapFromMain() async throws {
        let (model, service) = await reviewReady()
        await signWithPin(model)
        await waitUntil { isSent(model) }
        guard case .finished(.sent(let receipt)) = model.stage else { Issue.record("not sent: \(model.stage)"); return }
        #expect(receipt.summary.amountIn == 400)
        #expect(receipt.summary.given == .xlm)
        #expect(receipt.summary.received == .usdc)
        #expect(receipt.receivedAmount == Decimal(string: "99.68"))
        #expect(service.prepareCount == 1)
        #expect(service.send.signCount == 1)
        #expect(service.submitCount == 1)
        #expect(service.send.lastPin == "1234")
        #expect(model.pin.isEmpty)
        #expect(model.pending == nil)
    }

    @Test("Wallet d'une carte (Banana, ordre 1) : c'est sa carte qui signe")
    func swapFromCard() async {
        let (model, service) = await reviewReady(drawerID: "0688", amount: 100)
        #expect(model.draft?.drawer.id == "0688")
        await signWithPin(model)
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(model.signed?.cardName == "Banana")
        #expect(service.submitCount == 1)
    }

    @Test("Anti-double envoi : « Looks good » deux fois ne prépare qu'une fois ; signature verrouillée pendant la préparation")
    func noDoubleSend() async {
        let (model, service) = await reviewReady()
        model.confirmReview()
        #expect(model.stage == .preparing)
        #expect(model.isSigningLocked)
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        #expect(service.prepareCount == 1)
        #expect(!model.isSigningLocked, "La feuille du PIN se ferme encore (« Cancel »)")
    }

    @Test("E4p · Le prix a bougé à la préparation : rien n'est signé, nouveau devis demandé tout de suite, ancien et nouveau minimum")
    func priceMoved() async throws {
        let (model, service) = await reviewReady(.priceMovesBeforeSigning)
        model.confirmReview()
        await waitUntil { model.priceMoved?.newDraft != nil }
        let moved = try #require(model.priceMoved)
        #expect(moved.oldMinimum == Decimal(string: "99.1816"))
        #expect(moved.received == .usdc)
        #expect(moved.newDraft?.quote.amountIn == 400)
        #expect(model.stage == .idle)
        #expect(model.preparationIssue == nil)
        #expect(service.send.signCount == 0)
    }

    @Test("« See new price » : retour à la vérification complète avec les nouvelles bornes, jamais une signature directe")
    func seeNewPrice() async throws {
        let (model, service) = await reviewReady(.priceMovesBeforeSigning)
        model.confirmReview()
        await waitUntil { model.priceMoved?.newDraft != nil }
        let newDraft = try #require(model.priceMoved?.newDraft)
        service.quoteScenario = .normal
        model.acceptNewPrice()
        #expect(model.priceMoved == nil)
        #expect(model.draft == newDraft)
        #expect(model.stage == .idle, "Il faut de nouveau « Looks good »")
        #expect(model.isReviewPresented)
        #expect(service.prepareCount == 1)
        #expect(service.send.signCount == 0)
    }

    @Test("E4p · nouveau devis impossible : « Try again » le redemande")
    func newPriceFails() async throws {
        let (model, service) = await reviewReady(.priceMovesBeforeSigning)
        model.confirmReview()
        await waitUntil { model.priceMoved?.newDraft != nil }
        service.quoteScenario = .protocolUnavailable
        await model.fetchNewPrice()
        #expect(model.priceMoved?.failed == true)
        #expect(model.priceMoved?.newDraft == nil)
        model.acceptNewPrice()
        #expect(model.priceMoved != nil, "Pas de nouveau prix : rien à accepter")
        service.quoteScenario = .normal
        await model.fetchNewPrice()
        #expect(model.priceMoved?.newDraft != nil)
    }

    @Test("E3s · trois tolérances (0,5 %, 1 %, 3 %) avec le minimum de chacune ; taux et soldes après en quantités")
    func slippageSheetAndRate() async {
        let (model, _) = await model()
        await quoted(model, 400)
        #expect(SwapFlowModel.slippageOptions == [50, 100, 300])
        #expect(model.minimum(atSlippage: 100) == Decimal(string: "98.6832"))
        #expect(model.minimum(atSlippage: 300) == Decimal(string: "96.6896"))
        #expect(model.rate == Decimal(string: "0.2492"))
        #expect(model.givenBalanceLine.after == 0)
        #expect(model.receivedBalanceLine.after == Decimal(string: "819.68"))
        model.isSlippageSheetPresented = true
        model.setSlippage(100)
        #expect(model.slippageBasisPoints == 100)
        #expect(!model.isSlippageSheetPresented)
    }

    @Test("E3f « Check again » : l'envoi en attente est parti, il est effacé et le swap redevient possible")
    func checkPendingPayment() async {
        let service = MockSwapService(resultScenario: .sent, delay: .zero)
        service.pendingSend = PendingSend(
            trace: PaymentTrace(token: "xlm", from: "main", destination: "tom", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: "tom", recipientName: nil, drawerTitle: "Main account", asset: "xlm", amount: 1, signedAt: .now
        )
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.blockedByPendingPayment)
        #expect(model.loadPhase == .loaded, "L'écran E3 s'affiche quand même")
        await model.checkPendingPayment()
        #expect(!model.blockedByPendingPayment)
        #expect(service.pendingSend == nil)
        await quoted(model, 10)
        #expect(model.canReview)
    }

    @Test("« Swap again » : tiroir, actifs et montant préremplis, devis demandé au chargement")
    func swapAgainPrefill() async {
        let service = MockSwapService(delay: .zero)
        let model = SwapFlowModel(service: service, prefill: SwapPrefill(drawerID: "0688", given: .usdc, received: .xlm, amount: 10), quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.selectedDrawer?.id == "0688")
        #expect(model.given == .usdc)
        #expect(model.currentQuote?.amountIn == 10)
    }

    @Test("E4i « Change the amount » : retour à la saisie")
    func changeAmount() async {
        let (model, _) = await reviewReady(.bigImpact)
        #expect(model.draft?.quote.needsPriceImpactWarning == true)
        model.changeAmount()
        #expect(!model.isReviewPresented)
    }

    @Test("PIN faux : retour au PIN avec les essais restants, rien n'est envoyé")
    func wrongPIN() async {
        let (model, service) = await reviewReady()
        service.send.nextSignError = ChipError.wrongPIN(retriesLeft: 2)
        await signWithPin(model)
        await waitUntil { model.stage == .enteringPin }
        #expect(model.pinState == .wrong(triesLeft: 2))
        #expect(service.submitCount == 0)
    }

    @Test("Annuler pendant le PIN : retour à la vérification, rien n'est signé")
    func cancel() async {
        let (model, service) = await reviewReady()
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.cancelSigning()
        #expect(model.stage == .idle)
        #expect(service.send.signCount == 0)
    }

    // MARK: Issues incertaines

    @Test("Refusé après la signature : swap gardé en attente (avec ce qui devait arriver), attente, puis « Nothing was sent »")
    func rejectedThenNothingSent() async throws {
        let (model, service) = await reviewReady(result: .rejectedThenNothingSent)
        await signWithPin(model)
        await waitUntil { if case .finished(.waiting) = model.stage { return true }; return false }
        let pending = try #require(service.pendingSend)
        #expect(pending.swap?.receivedAsset == "usdc")
        #expect(pending.swap?.minimumReceived == Decimal(string: "99.1816"))
        #expect(pending.amount == 400)
        #expect(!model.canTryAgain, "Jamais « Try again » tant que l'autorisation peut servir")
        await waitUntil(seconds: 4) { model.stage == .finished(.nothingSent) }
        #expect(model.stage == .finished(.nothingSent))
        #expect(service.pendingSend == nil)
        #expect(model.canTryAgain)
    }

    @Test("Pas confirmé à temps : « Check again » le trouve confirmé")
    func notConfirmedThenSent() async {
        let (model, service) = await reviewReady(result: .notConfirmedThenSent)
        await signWithPin(model)
        await waitUntil { model.stage == .finished(.notConfirmed) }
        #expect(model.stage == .finished(.notConfirmed))
        #expect(service.pendingSend?.swap != nil)
        model.checkAgain()
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(service.pendingSend == nil)
    }

    @Test("Swap en attente au lancement : l'écran d'état reprend, jamais un nouveau swap")
    func resumesPendingSwap() async {
        let service = MockSwapService(resultScenario: .sent, delay: .zero)
        service.pendingSend = PendingSend(
            trace: PaymentTrace(token: "xlm", from: "main", destination: "pair", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: "router", recipientName: "Soroswap", drawerTitle: "Main account", asset: "xlm", amount: 400, signedAt: .now,
            swap: PendingSwap(receivedAsset: "usdc", expectedReceived: Decimal(string: "99.68")!, minimumReceived: Decimal(string: "99.1816")!, protocolName: "Soroswap")
        )
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.resumedPending)
        #expect(isSent(model))
        #expect(model.summary?.received == .usdc)
        #expect(service.prepareCount == 0)
    }

    @Test("Un envoi attend son issue : aucun swap ne peut être signé")
    func blockedByPendingPayment() async {
        let service = MockSwapService(delay: .zero)
        service.pendingSend = PendingSend(
            trace: PaymentTrace(token: "xlm", from: "main", destination: "tom", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: "tom", recipientName: nil, drawerTitle: "Main account", asset: "xlm", amount: 1, signedAt: .now
        )
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.blockedByPendingPayment)
        #expect(!model.canReview)
        #expect(service.checkCount == 0, "Vérifié seulement sur « Check again » (E3f)")
    }
}
