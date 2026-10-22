import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

#if CHIMP_ADMIN
/// Chimp Admin par tâche (2026-10-22) : clé admin, ligne d'état.
@MainActor
struct AdminAppTests {
    private func session(seed: String? = nil, balance: Result<Decimal, Error> = .success(19_920), expected: String? = nil) -> AdminSession {
        let store = InMemoryAdminKeyStore(seed: seed)
        let key = expected.map { AdminKeyModel(store: store, expectedAdmin: $0) } ?? AdminKeyModel(store: store, expectedAdmin: (try? store.publicKey()) ?? "")
        return AdminSession(key: key) { _ in try balance.get() }
    }

    @Test("Sans clé : écran « Set up Chimp Admin » ; la clé collée l'ouvre, retirée elle le ramène")
    func setup() throws {
        let admin = session()
        #expect(!admin.hasKey)
        let pair = try KeyPair.generateRandomKeyPair()
        admin.key.save("  \(pair.secretSeed!)\n")
        #expect(admin.hasKey && admin.key.publicKey == pair.accountId)
        admin.key.erase()
        #expect(!admin.hasKey)
        admin.key.save("not a key")
        #expect(!admin.hasKey && admin.key.errorMessage != nil)
    }

    @Test("Ligne d'état : « Admin key ✓ · 19,920 test XLM », solde illisible, mauvaise clé")
    func statusLine() async throws {
        let pair = try KeyPair.generateRandomKeyPair()
        let admin = session(seed: pair.secretSeed)
        #expect(admin.statusText == "Admin key ✓ · … test XLM")
        admin.refreshBalance()
        await admin.waitForBalance()
        #expect(admin.statusText == "Admin key ✓ · \(AdminSession.xlmText(19_920)) test XLM")

        let broken = session(seed: pair.secretSeed, balance: .failure(URLError(.timedOut)))
        broken.refreshBalance()
        await broken.waitForBalance()
        #expect(broken.statusText == "Admin key ✓ · balance unavailable")

        let wrong = session(seed: pair.secretSeed, expected: "GOTHERADMIN")
        #expect(wrong.statusText == "Admin key ⚠ · not the ChimpDAO admin")
        #expect(AdminSession.xlmText(Decimal(string: "12.567")!, locale: Locale(identifier: "en_US")) == "12.56")
    }

    @Test("Money : adresse G ou C de 56 caractères, montant de 1 à 1000 XLM ; envoi exact, solde relu ensuite")
    func sendTestMoney() async {
        let funder = MockTestnetFunding()
        funder.delay = .zero
        let model = AdminMoneyModel(funder: funder)
        var refreshed = 0
        model.onSent = { refreshed += 1 }
        #expect(!model.canSend && model.addressProblem == nil, "Champ vide : pas encore d'erreur")
        model.address = "hello"
        #expect(model.addressProblem != nil && !model.canSend)
        let wallet = String(repeating: "C", count: 56)
        model.address = " \(wallet.lowercased()) "
        model.amountText = "0"
        #expect(model.amountProblem != nil && !model.canSend)
        model.amountText = "1001"
        #expect(model.amountProblem != nil)
        model.amountText = "120"
        #expect(model.canSend)
        await model.send()
        #expect(funder.sent.count == 1 && funder.sent[0].address == wallet && funder.sent[0].units == 1_200_000_000)
        #expect(model.message == .sent("Sent 120 test XLM to CCCCCC…CCCC.") && refreshed == 1)

        funder.failing = [wallet]
        await model.send()
        guard case .failed = model.message else { Issue.record("expected failure"); return }
        #expect(refreshed == 1)
    }

    @Test("Money : sans testnet joignable, jamais de faux envoi")
    func noFunder() async {
        let model = AdminMoneyModel(funder: nil)
        model.address = String(repeating: "G", count: 56)
        await model.send()
        #expect(model.message == .failed("Stellar testnet isn't available in this build."))
    }
}
#endif
