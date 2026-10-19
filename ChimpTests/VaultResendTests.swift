import Foundation
import Testing
@testable import ChimpDAO

/// Revue de sécurité F3, partie 2 (décision de Pamphile du 2026-10-19), pour le vault DeFindex et le prêt XOXNO :
/// signature retenue par le serveur de frais, puis « Try again ». La même autorisation est renvoyée (aucune nouvelle
/// signature) : un seul nonce, donc une seule exécution possible.
struct VaultResendTests {
    private func waitUntil(seconds: Double = 2, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isWaiting(_ model: VaultFlowModel) -> Bool {
        if case .finished(.waiting) = model.stage { return true }
        return false
    }

    private func isSent(_ model: VaultFlowModel) -> Bool {
        if case .finished(.sent) = model.stage { return true }
        return false
    }

    /// Montant, devis, vérification, PIN puis tap, jusqu'à l'attente (« Not moved »).
    private func signedAndWithheld(_ model: VaultFlowModel, amount: Decimal) async {
        await model.loadIfNeeded()
        model.setAmount(amount)
        await model.refreshQuote()
        model.continueToReview()
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { isWaiting(model) }
    }

    /// L'hôte n'accepte un nonce qu'une fois par adresse.
    private func executions(_ authorizations: [SignedVault], trace: (SignedVault) throws -> PaymentTrace) throws -> Int {
        var used = Set<String>()
        return try authorizations.filter { signed in
            let trace = try trace(signed)
            return used.insert("\(trace.from):\(trace.nonce)").inserted
        }.count
    }

    @Test("F3 : dépôt DeFindex retenu puis « Try again » : la même autorisation, une seule exécution possible")
    func defindex() async throws {
        let service = MockVaultService(resultScenario: .withheld, delay: .zero)
        service.send.authorizationWait = .seconds(30)
        let model = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await signedAndWithheld(model, amount: 10)
        #expect(isWaiting(model))
        #expect(!model.canTryAgain, "Pas de nouvelle signature tant que la première peut servir")
        #expect(model.canResend)

        model.resend()
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(service.signCount == 1, "Aucune nouvelle signature")
        #expect(service.prepareCount == 1, "Aucune nouvelle préparation")
        #expect(service.submitted.count == 2)
        let withheld = try #require(service.submitted.first)
        #expect(service.submitted[1] == withheld, "Exactement la même autorisation signée")
        // Le renvoi s'exécute ; l'autorisation retenue, soumise ensuite par l'attaquant, ne peut plus s'exécuter.
        #expect(try executions([service.submitted[1], withheld], trace: service.trace(for:)) == 1)
        #expect(service.pendingSend == nil)
    }

    @Test("F3 : retrait XOXNO retenu puis « Try again » : la même autorisation, une seule exécution possible")
    func xoxno() async throws {
        let service = MockLendingService(resultScenario: .withheld, delay: .zero)
        service.send.authorizationWait = .seconds(30)
        let model = VaultFlowModel(service: service, action: .withdraw, quoteDebounce: .zero)
        await signedAndWithheld(model, amount: 5)
        #expect(isWaiting(model))
        #expect(model.isLending)
        #expect(!model.canTryAgain)
        #expect(model.canResend)

        model.resend()
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(service.send.signCount == 1, "Aucune nouvelle signature")
        #expect(service.prepareCount == 1)
        #expect(service.submitted.count == 2)
        let withheld = try #require(service.submitted.first)
        #expect(service.submitted[1] == withheld)
        #expect(try executions([service.submitted[1], withheld], trace: service.trace(for:)) == 1)
    }

    @Test("F3 : après un redémarrage de l'app, on attend l'expiration : ni renvoi ni nouvelle signature")
    func afterRestart() async {
        let service = MockVaultService(resultScenario: .withheld, delay: .zero)
        service.send.authorizationWait = .seconds(30)
        let first = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await signedAndWithheld(first, amount: 10)
        #expect(service.pendingSend != nil)
        let reopened = VaultFlowModel(service: service, action: .deposit, quoteDebounce: .zero)
        await reopened.loadIfNeeded()
        await waitUntil { isWaiting(reopened) }
        #expect(isWaiting(reopened))
        #expect(!reopened.canResend)
        #expect(!reopened.canTryAgain)
        #expect(service.signCount == 1)
    }
}
