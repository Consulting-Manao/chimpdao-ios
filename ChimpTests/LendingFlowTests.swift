import Foundation
import SwiftUI
import Testing
@testable import ChimpDAO

/// Phase 7, étape 3 : le parcours du vault sur un marché de prêt XOXNO (service factice : Main a une position de
/// 25.0312 USDC). Retrait plafonné à ce qui peut sortir maintenant, « All » seulement si tout peut sortir, blocages.
struct LendingFlowTests {
    private func model(_ action: VaultAction, scenario: MockLendingService.Scenario = .normal) async -> VaultFlowModel {
        let service = MockLendingService(scenario: scenario, delay: .zero)
        let model = VaultFlowModel(service: service, action: action, quoteDebounce: .zero)
        await model.loadIfNeeded()
        return model
    }

    @Test("Tout peut sortir : « All » retire toute la position, au montant exact")
    func withdrawAll() async throws {
        let model = await model(.withdraw)
        #expect(model.isLending)
        #expect(model.withdrawableNow == MockLendingService.positionValue)
        model.setMax()
        await model.refreshQuote()
        #expect(model.withdrawAll)
        let quote = try #require(model.currentQuote)
        #expect(quote.expected == MockLendingService.positionValue && quote.minimum == MockLendingService.positionValue)
        #expect(model.canReview)
    }

    @Test("Presque tout est prêté : le plus qui peut sortir est proposé (pas « All »), au-delà c'est dit avant tout devis")
    func lentOut() async throws {
        let model = await model(.withdraw, scenario: .lentOut)
        #expect(model.withdrawableNow == MockLendingService.availableWhenLentOut)
        model.setAmount(10)
        #expect(model.amountIssue == .moreThanAvailableNow(available: MockLendingService.availableWhenLentOut, asset: .usdc))
        #expect(!model.canReview)
        model.setMax()
        await model.refreshQuote()
        #expect(!model.withdrawAll)
        #expect(model.amount.value == MockLendingService.availableWhenLentOut)
        #expect(model.amountIssue == nil)
        #expect(model.canReview)
    }

    @Test("Pause : ni dépôt ni retrait ; gel : plus de dépôt, retraits possibles")
    func blocked() async {
        let pausedDeposit = await model(.deposit, scenario: .paused)
        pausedDeposit.setAmount(1)
        await pausedDeposit.refreshQuote()
        #expect(pausedDeposit.isBlockedByMarket && !pausedDeposit.canReview)
        let pausedWithdraw = await model(.withdraw, scenario: .paused)
        #expect(pausedWithdraw.isBlockedByMarket)
        let frozenDeposit = await model(.deposit, scenario: .frozen)
        #expect(frozenDeposit.isBlockedByMarket)
        let frozenWithdraw = await model(.withdraw, scenario: .frozen)
        #expect(!frozenWithdraw.isBlockedByMarket)
        frozenWithdraw.setAmount(1)
        await frozenWithdraw.refreshQuote()
        #expect(frozenWithdraw.canReview)
    }

    @Test("Position à renouveler ou avec dette : aucun tiroir proposé au retrait ; le dépôt reste possible")
    func notMovable() async {
        for scenario in [MockLendingService.Scenario.needsRenewal, .hasDebt] {
            let withdraw = await model(.withdraw, scenario: scenario)
            #expect(withdraw.drawers.isEmpty)
            let deposit = await model(.deposit, scenario: scenario)
            #expect(!deposit.drawers.isEmpty)
        }
    }

    @Test("Résumé d'une opération XOXNO gardée sur le téléphone : reconnue comme un prêt")
    func pendingKind() {
        var pending = PendingSend(
            trace: PaymentTrace(token: "usdc", from: "main", destination: MockLendingService.pool, units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: MockLendingService.pool, recipientName: nil, drawerTitle: "Main account", asset: "usdc", amount: 1, signedAt: .now
        )
        pending.vault = PendingVault(action: "deposit", vaultName: "XOXNO USDC", shares: nil, minimumReceived: nil)
        #expect(VaultSummary(pending, network: .testnet)?.kind == .lending)
        #expect(VaultSummary(pending, network: .testnet)?.placeName == "XOXNO")
    }
}

/// Revue de sécurité F5 (2026-10-16) : le contrat XOXNO ne garantit aucun minimum (un retrait est ramené à la position, qui
/// peut baisser si un emprunteur ne rembourse pas) : l'écran ne doit pas le présenter comme garanti.
struct LendingWordingTests {
    @Test("F5 : « Expected back », et la mention que le contrat ne garantit pas de minimum")
    func expectedBack() {
        #expect(VaultReviewView.minimumLabel(lending: true) == "Expected back")
        #expect(VaultReviewView.minimumNote(lending: true) == "The contract doesn't guarantee a minimum. If XOXNO can't pay it right now, nothing moves.")
        #expect(VaultStatusView.minimumLabel(lending: true) == "Expected back")
        // Le vault garde son minimum signé.
        #expect(VaultReviewView.minimumLabel(lending: false) == "Minimum received")
    }
}
