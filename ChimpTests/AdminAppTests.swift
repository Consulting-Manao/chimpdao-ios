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
}
#endif
