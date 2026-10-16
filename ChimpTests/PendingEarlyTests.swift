import Foundation
import Testing
@testable import ChimpDAO

/// Revue de sécurité F7 (2026-10-16) : l'opération en attente est gardée sur le téléphone **dès le retour de la carte**,
/// avant l'envoi. Sinon, si iOS tue l'app pendant l'envoi, rien ne bloquerait une nouvelle signature (double envoi possible).
/// Les services factices envoient lentement ; on regarde ce qui est gardé **pendant** l'envoi.
struct PendingEarlyTests {
    private func waitUntil(seconds: Double = 8, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Envoyer : gardée pendant l'envoi, effacée une fois envoyé")
    func send() async {
        let service = MockSendService(cardSetup: .allWithPin, delay: .milliseconds(150), nfcDelay: .zero)
        let model = SendFlowModel(service: service)
        await model.loadIfNeeded()
        model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
        model.select(drawerID: "main")
        model.setAmount(10)
        model.continueToReview()
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { if case .sending = model.signingStage { true } else { false } }
        #expect(service.pendingSend != nil, "Gardée avant l'envoi")
        await waitUntil { if case .finished = model.signingStage { true } else { false } }
        #expect(service.pendingSend == nil)
    }

    @Test("Swap : gardée pendant l'envoi, effacée une fois envoyé")
    func swap() async {
        let service = MockSwapService(delay: .milliseconds(150))
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        model.setAmount(400)
        await model.refreshQuote()
        model.continueToReview()
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { if case .sending = model.stage { true } else { false } }
        #expect(service.pendingSend != nil, "Gardée avant l'envoi")
        await waitUntil { if case .finished = model.stage { true } else { false } }
        #expect(service.pendingSend == nil)
    }

    @Test("Vault (et prêt) : gardée pendant l'envoi, effacée une fois envoyé")
    func vault() async {
        let service = MockVaultService(delay: .milliseconds(150))
        let model = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await model.loadIfNeeded()
        model.setAmount(50)
        await model.refreshQuote()
        model.continueToReview()
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { if case .sending = model.stage { true } else { false } }
        #expect(service.pendingSend != nil, "Gardée avant l'envoi")
        await waitUntil { if case .finished = model.stage { true } else { false } }
        #expect(service.pendingSend == nil)
    }
}
