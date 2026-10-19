import Foundation
import Testing
@testable import ChimpDAO

/// « Erase everything on this phone » efface vraiment tout (décision de Barth du 2026-10-19) : en plus du compte, de
/// l'historique et des réglages, l'historique de Grow et le dernier ledger vu par l'horloge.
/// `.serialized` : ces tests touchent les préférences partagées du téléphone.
@Suite(.serialized)
struct EraseEverythingTests {
    @Test("L'historique de Grow et le dernier ledger vu sont effacés ; l'horloge en mémoire est oubliée")
    func growHistoryAndLedgerClock() throws {
        let defaults = UserDefaults.standard
        DefaultsPotHistoryStore().record(PotReading(day: .now, value: 1), potID: "defindex:CTEST")
        defaults.set(Data("anchor".utf8), forKey: "ledgerClock.testnet")
        defaults.set(Data("anchor".utf8), forKey: "ledgerClock.mainnet")
        let clockBefore = LedgerClock.shared(for: .testnet)
        #expect(defaults.data(forKey: DefaultsPotHistoryStore.key) != nil)

        // Comme `AppSession.live` : l'effacement complet du téléphone.
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet, erasePhoneData: { PhoneData.eraseAll() })
        try session.eraseEverything()

        #expect(defaults.data(forKey: DefaultsPotHistoryStore.key) == nil)
        #expect(DefaultsPotHistoryStore().readings("defindex:CTEST").isEmpty)
        #expect(defaults.data(forKey: "ledgerClock.testnet") == nil)
        #expect(defaults.data(forKey: "ledgerClock.mainnet") == nil)
        #expect(LedgerClock.shared(for: .testnet) !== clockBefore, "Une horloge neuve, repartie du repère de Config/")
    }

    @Test("Une session de test n'efface pas les préférences partagées (seule `AppSession.live` le fait)")
    func testSessionLeavesDefaults() throws {
        UserDefaults.standard.set(Data("x".utf8), forKey: DefaultsPotHistoryStore.key)
        try AppSession(store: InMemoryLocalWalletStore(), config: .testnet).eraseEverything()
        #expect(UserDefaults.standard.data(forKey: DefaultsPotHistoryStore.key) != nil)
        PhoneData.eraseAll()
    }

    @Test("Le magasin de Grow n'a pas de copie en mémoire : rien ne réécrit l'ancien historique après l'effacement")
    func noStaleCache() {
        let store = DefaultsPotHistoryStore()
        store.record(PotReading(day: .now.addingTimeInterval(-86_400), value: 1), potID: "xoxno:CTEST")
        PhoneData.eraseAll()
        store.record(PotReading(day: .now, value: 2), potID: "xoxno:CTEST")
        #expect(store.readings("xoxno:CTEST").map(\.value) == [2], "Seul le relevé d'après l'effacement")
        PhoneData.eraseAll()
    }

    @Test("Toutes les préférences du domaine sont effacées (suite isolée)")
    func wholeDomain() throws {
        let suite = "chimp.erase.test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("x", forKey: "anything")
        PhoneData.eraseAll(defaults: defaults, domain: suite)
        #expect(defaults.string(forKey: "anything") == nil)
    }
}
