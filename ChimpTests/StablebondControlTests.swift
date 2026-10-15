import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 4 : gel et clawback du CETES, lus sur la chaîne. Si les CETES d'un tiroir sont gelés, l'app
/// le dit au lieu de proposer un swap voué à l'échec.
struct StablebondControlTests {
    @Test("Drapeaux de l'émetteur : AUTH_REVOCABLE (2) = peut geler, AUTH_CLAWBACK_ENABLED (8) = peut reprendre")
    func issuerPowers() {
        // Émetteur Etherfuse sandbox GC3CW7…UPS4 (Horizon, 2026-10-15) : auth_revocable et auth_clawback_enabled.
        #expect(IssuerPowers(flags: 0x2 | 0x8) == IssuerPowers(canFreeze: true, canClawBack: true))
        // Émetteur de l'USDC de Circle sur testnet : auth_revocable seul.
        #expect(IssuerPowers(flags: 0x2) == IssuerPowers(canFreeze: true, canClawBack: false))
        #expect(IssuerPowers(flags: 0) == IssuerPowers(canFreeze: false, canClawBack: false))
        #expect(IssuerPowers(flags: 0x1 | 0x4) == IssuerPowers(canFreeze: false, canClawBack: false))
    }

    private func model() async -> (SwapFlowModel, MockSwapService) {
        let service = MockSwapService(quoteScenario: .cetesFrozen, delay: .zero)
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        return (model, service)
    }

    @Test("CETES gelés dans Main : dit tout de suite, aucun devis demandé, aucune vérification possible, dans les deux sens")
    func frozenInMain() async {
        let (model, service) = await model()
        model.choose(.usdc, for: .given)
        model.choose(.cetes, for: .received)
        model.setAmount(1)
        await model.refreshQuote()
        #expect(model.frozenAsset == .cetes)
        #expect(service.quoteCount == 0, "Un swap voué à l'échec n'est même pas chiffré")
        #expect(!model.canReview)
        model.flipAssets()
        #expect(model.frozenAsset == .cetes, "Rendre des CETES gelés est refusé aussi")
    }

    @Test("Ailleurs, rien n'est bloqué : XLM ↔ USDC dans Main, CETES dans un autre tiroir")
    func notFrozenElsewhere() async throws {
        let (model, service) = await model()
        model.setAmount(10)
        await model.refreshQuote()
        #expect(model.frozenAsset == nil)
        #expect(model.currentQuote != nil)
        let banana = try #require(model.drawers.first { $0.kind != .main && $0.balance(of: .usdc) > 0 })
        model.choose(.usdc, for: .given)
        model.choose(.cetes, for: .received)
        model.select(drawerID: banana.id)
        await model.refreshQuote()
        #expect(model.frozenAsset == nil)
        #expect(model.currentQuote?.received == .cetes)
        #expect(service.quoteCount >= 2)
    }

    @Test("Gelé entre le devis et la signature : relu avant de signer, rien n'est signé, message dédié")
    func frozenAtSigning() {
        #expect(SwapFlowModel.preparationIssue(for: SwapServiceError.frozen("CETES")) == .frozen(.cetes))
        #expect(SendAsset.cetes.issuerName == "Etherfuse")
        #expect(SendAsset.usdc.issuerName == nil)
    }

    @Test("Gel entre la signature et l'envoi : l'envoi n'est pas bloqué, l'échec dit « Etherfuse froze your CETES »")
    func frozenAtSend() async throws {
        func run(_ scenario: MockSwapService.QuoteScenario, received: SendAsset) async -> SwapFlowModel {
            let service = MockSwapService(quoteScenario: scenario, resultScenario: .rejectedThenNothingSent, delay: .zero)
            service.send.authorizationWait = .seconds(1)
            let model = SwapFlowModel(service: service, quoteDebounce: .zero)
            await model.loadIfNeeded()
            model.choose(.usdc, for: .given)
            model.choose(received, for: .received)
            model.setAmount(10)
            await model.refreshQuote()
            model.continueToReview()
            model.confirmReview()
            for _ in 0..<200 where model.stage != .enteringPin { try? await Task.sleep(for: .milliseconds(10)) }
            model.pinEntered("1234")
            model.scanCard()
            for _ in 0..<300 {
                if case .finished = model.stage { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return model
        }
        let frozen = await run(.cetesFrozenAtSend, received: .cetes)
        guard case .finished = frozen.stage else { Issue.record("le swap n'est pas allé au bout : \(frozen.stage)"); return }
        #expect(frozen.frozenAtSend == .cetes)
        let plain = await run(.normal, received: .xlm)
        #expect(plain.frozenAtSend == nil, "Sans stablebond, rien n'est relu")
    }
}
