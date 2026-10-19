import Foundation
import SwiftUI
import Testing
@testable import ChimpDAO

/// Grow, étape 5 : les textes de G3 à G6 (raccourcis de montant, ligne de Chimpy de la vérification, fin du parcours).
/// Service factice : Main a 400 XLM, Banana 120 XLM ; une position dans Main.
struct GrowFlowTextsTests {
    private let us = Locale(identifier: "en_US")

    private func draft(_ action: VaultAction = .deposit, drawerID: String? = nil, amount: Decimal = 50) async throws -> VaultDraft {
        let service = MockVaultService(delay: .zero)
        let model = VaultFlowModel(service: service, action: action, initialDrawerID: drawerID, quoteDebounce: .zero)
        await model.loadIfNeeded()
        model.setAmount(amount)
        await model.refreshQuote()
        model.continueToReview()
        return try #require(model.draft)
    }

    @Test("Raccourcis : 10 · 50 · 100 qui tiennent dans le solde ; retrait : 10 · 50, sous ce qui peut sortir maintenant")
    func quickPicks() {
        #expect(VaultAmountView.quickPicks(deposit: true, available: 400, now: nil) == [10, 50, 100])
        #expect(VaultAmountView.quickPicks(deposit: true, available: 60, now: nil) == [10, 50])
        #expect(VaultAmountView.quickPicks(deposit: false, available: Decimal(string: "50.12")!, now: nil) == [10, 50])
        #expect(VaultAmountView.quickPicks(deposit: false, available: 50, now: 30) == [10], "Max met déjà ce qui peut sortir maintenant")
        #expect(VaultAmountView.quickPicks(deposit: false, available: 5, now: nil).isEmpty)
    }

    @Test("Chimpy dit qui peut signer : n'importe quelle carte depuis Main, la carte seule depuis son wallet")
    func chimpyLine() async throws {
        #expect(VaultReviewView.chimpyLine(try await draft()) == "Tap any of your cards, then your PIN. And we plant!")
        let banana = try await draft(drawerID: "0688", amount: 10)
        #expect(VaultReviewView.chimpyLine(banana).hasPrefix("Only your Banana card can sign"))
        #expect(VaultReviewView.chimpyLine(try await draft(.withdraw, amount: 10)).hasSuffix("And it comes home!"))
    }

    @Test("Fin : « 50 XLM is growing in DeFindex », « 30 XLM is back in Main », sans montant lu : « Your XLM »")
    func lead() async throws {
        let deposit = VaultSummary(try await draft())
        #expect(VaultSentView.lead(deposit, received: nil, locale: us) == "50 XLM is growing in DeFindex. I'll show you what it really does.")
        let withdraw = VaultSummary(try await draft(.withdraw, amount: 30))
        #expect(VaultSentView.lead(withdraw, received: 30, locale: us) == "30 XLM is back in Main, ready to use.")
        #expect(VaultSentView.lead(withdraw, received: nil, locale: us) == "Your XLM is back in Main, ready to use.")
    }

    @Test("Le retrait montre le minimum signé (« At least ») ; le prêt, « Expected back » (revue F5)")
    func minimum() {
        #expect(VaultReviewView.minimumLabel(lending: false) == "At least")
        #expect(VaultReviewView.minimumLabel(lending: true) == "Expected back")
    }
}
