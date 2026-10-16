import Foundation
import Testing
@testable import ChimpDAO

/// Revue de sécurité F3, partie 1 : l'expiration d'une autorisation est plafonnée par l'horloge du téléphone.
struct LedgerClockTests {
    /// Repère testnet relevé le 2026-10-16 : ledger 5 223 554 fermé à 09:02:37 UTC (retrait XOXNO de Barth).
    private let anchor = LedgerAnchor(ledger: 5_223_554, time: Date(timeIntervalSince1970: 1_792_141_357))

    private func clock(at seconds: TimeInterval, store: LedgerAnchorStore = MemoryLedgerAnchorStore()) -> LedgerClock {
        let clock = LedgerClock(anchor: anchor, store: store)
        clock.now = { Date(timeIntervalSince1970: 1_792_141_357 + seconds) }
        return clock
    }

    @Test("F3 : un ledger annoncé bien au-delà de ce que l'horloge permet est refusé (autorisation valable des mois)")
    func farFutureLedgerRefused() {
        // Une heure après le repère, le testnet est vers 5 224 200. Le RPC annonce un million de ledgers de plus (~2 mois).
        #expect(throws: LedgerClockError.self) { try clock(at: 3_600).checked(6_224_200) }
    }

    @Test("Un ledger normal est accepté et devient le repère du téléphone ; le plus serré des repères s'applique")
    func normalLedgerAccepted() throws {
        let store = MemoryLedgerAnchorStore()
        let clock = clock(at: 3_600, store: store)
        #expect(try clock.checked(5_224_200) == 5_224_200)
        #expect(store.load()?.ledger == 5_224_200)
        // Repère du téléphone 1 h après celui de Config : plafond = 5 224 200 + 0 + 17 280.
        #expect(clock.maximumLedger() == 5_224_200 + LedgerClock.marginLedgers)
        #expect(throws: LedgerClockError.self) { try clock.checked(5_224_200 + LedgerClock.marginLedgers + 1) }
        // Un ledger plus ancien ne recule pas le repère.
        #expect(try clock.checked(5_224_000) == 5_224_000)
        #expect(store.load()?.ledger == 5_224_200)
    }

    @Test("Le plafond suit le temps : 4 s par ledger au plus, plus une marge d'un jour")
    func boundFollowsTime() {
        let day: TimeInterval = 86_400
        #expect(LedgerClock.bound(from: anchor, now: anchor.time.addingTimeInterval(day)) == 5_223_554 + 21_600 + 17_280)
        // Horloge du téléphone en retard sur le repère : jamais en dessous du repère + la marge.
        #expect(LedgerClock.bound(from: anchor, now: anchor.time.addingTimeInterval(-day)) == 5_223_554 + 17_280)
    }

    @Test("Sans aucun repère : accepté (et gardé comme repère)")
    func noAnchor() throws {
        let store = MemoryLedgerAnchorStore()
        let clock = LedgerClock(anchor: nil, store: store)
        #expect(try clock.checked(64_140_891) == 64_140_891)
        #expect(store.load()?.ledger == 64_140_891)
    }

    @Test("Le repère testnet de Config est celui relevé sur la chaîne")
    func testnetAnchor() {
        #expect(ChimpNetworkConfig.testnet.ledgerAnchor == anchor)
    }
}
