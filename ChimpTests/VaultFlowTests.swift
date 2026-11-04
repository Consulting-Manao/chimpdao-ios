import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 4, étape 3 : machine à états du parcours du vault (mettre, retirer), avec le service factice (mêmes
/// tiroirs qu'Envoyer : Main a 400 XLM, Banana 120 XLM ; une position dans Main : 50.12 XLM pour 50 XLM mis le 22 sept.).
struct VaultFlowTests {
    private func model(
        _ action: VaultAction = .deposit,
        scenario: MockVaultService.Scenario = .normal,
        result: MockSendService.ResultScenario = .sent,
        drawerID: String? = nil
    ) async -> (VaultFlowModel, MockVaultService) {
        let service = MockVaultService(scenario: scenario, resultScenario: result, delay: .zero)
        service.send.authorizationWait = .seconds(1)
        let model = VaultFlowModel(service: service, action: action, initialDrawerID: drawerID, quoteDebounce: .zero)
        await model.loadIfNeeded()
        return (model, service)
    }

    private func quoted(_ model: VaultFlowModel, _ amount: Decimal) async {
        model.setAmount(amount)
        await model.refreshQuote()
    }

    private func reviewReady(
        _ action: VaultAction = .deposit, scenario: MockVaultService.Scenario = .normal,
        result: MockSendService.ResultScenario = .sent, amount: Decimal = 50
    ) async -> (VaultFlowModel, MockVaultService) {
        let (model, service) = await self.model(action, scenario: scenario, result: result)
        await quoted(model, amount)
        model.continueToReview()
        return (model, service)
    }

    private func waitUntil(seconds: Double = 2, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isSent(_ model: VaultFlowModel) -> Bool {
        if case .finished(.sent) = model.stage { return true }
        return false
    }

    private func signWithPin(_ model: VaultFlowModel) async {
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
    }

    private var pendingSend: PendingSend {
        PendingSend(
            trace: PaymentTrace(token: "xlm", from: "main", destination: "tom", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: "tom", recipientName: nil, drawerTitle: "Main account", asset: "xlm", amount: 1, signedAt: .now
        )
    }

    // MARK: Chargement, montant, devis

    @Test("Chargement : le vault, ses protocoles nommés, la position de Main avec ce qui a été mis et depuis quand")
    func load() async throws {
        let (model, _) = await model()
        #expect(model.loadPhase == .loaded)
        #expect(model.context?.vault.protocolChain == "DeFindex → Blend")
        let holding = try #require(model.context?.holding(drawerID: "main"))
        #expect(holding.value == Decimal(string: "50.12"))
        #expect(holding.change == Decimal(string: "0.12"))
        #expect(holding.basis?.since == MockVaultService.depositDate)
    }

    @Test("Mettre : devis « about N shares », pas assez depuis Banana (F3a), vérification impossible")
    func depositAmount() async {
        let (model, _) = await model()
        await quoted(model, 50)
        #expect(model.currentQuote?.action == .deposit)
        #expect(model.currentQuote?.minimumOut == nil, "Un dépôt ne fixe pas de minimum de parts")
        #expect(model.canReview)

        let (banana, _) = await self.model(drawerID: "0688")
        await quoted(banana, 250)
        #expect(banana.amountIssue == .insufficient(drawer: "Banana's wallet", available: 120, asset: .xlm))
        #expect(!banana.canReview)
    }

    @Test("Vault indisponible : F3b, rien ne se charge")
    func unavailable() async {
        let (model, _) = await model(scenario: .vaultUnavailable)
        #expect(model.loadPhase == .unavailable)
        #expect(!model.canReview)
    }

    @Test("Valeur invraisemblable : rien n'est affiché comme un montant")
    func implausible() async {
        let (model, _) = await model(scenario: .implausible)
        #expect(model.loadPhase == .failed)
        #expect(model.context == nil)
        #expect(VaultFlowModel.quoteIssue(for: YieldError.implausibleValue) == .implausible)
        #expect(VaultFlowModel.preparationIssue(for: YieldError.implausibleValue) == .implausible)
    }

    // MARK: Mettre, de bout en bout

    @Test("Mettre : vérification → PIN → tap → « Planted! » ; une seule préparation, une seule signature")
    func depositEndToEnd() async throws {
        let (model, service) = await reviewReady()
        #expect(model.draft?.amount == 50)
        model.confirmReview()
        model.confirmReview()
        await waitUntil { service.prepareCount > 0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(service.prepareCount == 1, "Impossible de préparer deux fois")
        model.pinEntered("1234")
        #expect(model.stage == .scanning(.tapToSign), "Le scan démarre tout seul")
        await waitUntil { isSent(model) }
        guard case .finished(.sent(let receipt)) = model.stage else { Issue.record("pas envoyé"); return }
        #expect(receipt.summary.action == .deposit)
        #expect(receipt.summary.amount == 50)
        #expect(receipt.summary.drawerShortTitle == "Main")
        #expect(service.signCount == 1)
        #expect(service.pendingSend == nil)
    }

    @Test("Annuler pendant le PIN, préparation en cours : elle est abandonnée, rien ne se rouvre")
    func cancelDuringPreparation() async {
        let service = MockVaultService(delay: .milliseconds(200))
        let model = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await model.loadIfNeeded()
        await quoted(model, 10)
        model.continueToReview()
        model.confirmReview()
        #expect(model.stage == .enteringPin, "Le PIN s'ouvre pendant la préparation")
        #expect(!model.isSigningLocked)
        model.cancelSigning()
        #expect(model.stage == .idle)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(model.stage == .idle, "La préparation abandonnée ne rouvre rien")
        #expect(model.preparationIssue == nil)
        #expect(service.signCount == 0)
    }

    // MARK: Retirer

    @Test("Retirer : le tiroir de la position est choisi ; plus que la position refusé ; « All » = toutes les parts")
    func withdrawAmount() async throws {
        let (model, _) = await model(.withdraw)
        #expect(model.selectedDrawer?.id == "main")
        #expect(model.drawers.map(\.id) == ["main"], "Seulement les tiroirs qui détiennent une position")
        #expect(model.available == Decimal(string: "50.12"))
        await quoted(model, 60)
        #expect(model.amountIssue == .moreThanPosition(available: Decimal(string: "50.12")!, asset: .xlm))
        model.setMax()
        await model.refreshQuote()
        #expect(model.withdrawAll)
        #expect(model.amountIssue == nil)
        let quote = try #require(model.currentQuote)
        #expect(quote.all)
        #expect(quote.expected == Decimal(string: "50.12"))
        #expect(quote.minimum == SwapUnits.amount(fromUnits: Slippage.minimum(of: 501_200_000, basisPoints: 50)))
    }

    @Test("Retirer : le vault a bougé avant la signature → rien n'est signé, nouveau devis, vérification à refaire")
    func withdrawPriceMoved() async throws {
        let (model, service) = await reviewReady(.withdraw, scenario: .priceMovesBeforeSigning, amount: 20)
        await waitUntil { model.quoteState != .loading }
        let quotesBefore = service.quoteCount
        let oldMinimum = try #require(model.draft?.quote.minimum)
        model.confirmReview()
        await waitUntil { model.amountMoved?.newDraft != nil && !model.isRefreshingQuote }
        #expect(model.stage == .idle)
        #expect(service.signCount == 0)
        #expect(service.quoteCount == quotesBefore + 1, "Un nouveau devis est demandé tout de suite")
        let moved = try #require(model.amountMoved, "Écran « le montant a bougé » (comme E4p)")
        #expect(moved.old == oldMinimum, "L'ancien minimum, barré")
        let newMinimum = try #require(moved.newDraft?.quote.minimum)
        #expect(newMinimum < oldMinimum)
        #expect(model.draft?.quote.minimum == oldMinimum, "Rien ne remplace le brouillon avant « See new amount »")
        model.acceptNewAmount()
        #expect(model.amountMoved == nil)
        #expect(model.draft?.quote.minimum == newMinimum, "Vérification complète avec le nouveau minimum")
        #expect(model.stage == .idle, "Jamais une signature directe")
        await signWithPin(model)
        await waitUntil { isSent(model) }
        #expect(isSent(model), "Il a fallu « Looks good » à nouveau")
    }

    @Test("Retirer : argent prêté sur Blend → message, « Take out 30 XLM » remet le disponible ; le retrait passe ensuite")
    func withdrawLentOut() async throws {
        let (model, service) = await reviewReady(.withdraw, scenario: .lentOut, amount: 40)
        #expect(model.amountIssue == nil, "40 XLM ≤ la position : rien n'est refusé avant le contrat")
        model.confirmReview()
        await waitUntil { model.preparationIssue != nil }
        #expect(model.preparationIssue == .notEnoughLiquidity)
        #expect(service.signCount == 0)
        let draft = try #require(model.draft)
        #expect(draft.vault.availableNow == MockVaultService.availableWhenLentOut)
        model.takeOutAvailableNow()
        #expect(model.isReviewPresented == false, "Retour au montant")
        #expect(model.amount.value == MockVaultService.availableWhenLentOut)
        await model.refreshQuote()
        model.continueToReview()
        #expect(model.preparationIssue == nil)
        await signWithPin(model)
        await waitUntil { isSent(model) }
        #expect(isSent(model))
    }

    // MARK: Issues incertaines

    @Test("Issue incertaine : l'opération est gardée (retrait, minimum), « Not sure yet », puis « Check again »")
    func undetermined() async throws {
        let (model, service) = await reviewReady(.withdraw, result: .undetermined, amount: 20)
        await signWithPin(model)
        await waitUntil { model.stage == .finished(.undetermined) }
        let pending = try #require(service.pendingSend)
        #expect(pending.vault?.action == "withdraw")
        #expect(pending.vault?.minimumReceived == model.draft?.quote.minimum)
        #expect(pending.recipient == MockVaultService.vaultAddress)
    }

    @Test("Refusé : « attends jusqu'à… », puis « Nothing was moved » seulement quand c'est certain")
    func rejectedThenNothing() async {
        let (model, service) = await reviewReady(result: .rejectedThenNothingSent)
        await signWithPin(model)
        await waitUntil { if case .finished(.waiting) = model.stage { return true }; return false }
        #expect(!model.canTryAgain)
        await waitUntil(seconds: 4) { model.stage == .finished(.nothingSent) }
        #expect(model.stage == .finished(.nothingSent))
        #expect(service.pendingSend == nil)
        #expect(model.canTryAgain)
    }

    @Test("Une opération de vault en attente : le parcours la reprend et la vérifie, sans rien préparer")
    func resumesPending() async {
        let service = MockVaultService(delay: .zero)
        var waiting = pendingSend
        waiting.vault = PendingVault(action: "deposit", vaultName: "DeFindex XLM", shares: 49, minimumReceived: nil)
        service.pendingSend = waiting
        let model = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.resumedPending)
        #expect(isSent(model))
        #expect(model.summary?.action == .deposit)
        #expect(service.prepareCount == 0)
    }

    @Test("F3c : un envoi attend son issue, rien ne se signe ; « Check again » le règle")
    func blockedByPendingPayment() async {
        let service = MockVaultService(delay: .zero)
        service.pendingSend = pendingSend
        let model = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.blockedByPendingPayment)
        await quoted(model, 10)
        #expect(!model.canReview)
        await model.checkPendingPayment()
        #expect(!model.blockedByPendingPayment)
        #expect(model.canReview)
    }

    @Test("Montant 128 bits du devis : intact à travers le service (TokenAmount)")
    func quoteSurvivesAsync() async throws {
        let (model, _) = await model(.withdraw)
        model.setMax()
        await model.refreshQuote()
        let quote = try #require(model.currentQuote)
        #expect(quote.expectedOut?.units == 501_200_000)
    }
}
