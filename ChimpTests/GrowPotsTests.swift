import Foundation
import Testing
@testable import ChimpDAO

/// Grow, étape 2 : les pots (un par protocole et par tiroir), le total en dollars, l'historique de la courbe.
struct GrowPotsTests {
    private func contexts() async throws -> (VaultContext, VaultContext, SavingsContext) {
        let vault = try await MockVaultService(delay: .zero).fetchContext()
        let lending = try await MockLendingService(delay: .zero).fetchContext()
        let savings = try await MockSavingsService(delay: .zero).fetchSavings()
        return (vault, lending, savings)
    }

    @Test("Un pot par protocole et par tiroir, dans l'ordre DeFindex, XOXNO, Etherfuse")
    func build() async throws {
        let (vault, lending, savings) = try await contexts()
        let pots = GrowPots.build(vault: vault, lending: lending, savings: savings)
        #expect(pots.map(\.mark) == [.defindex, .xoxno, .etherfuse])
        #expect(Set(pots.map(\.drawerID)) == ["main"])
        let defindex = try #require(pots.first)
        #expect(defindex.value == Decimal(string: "50.12"))
        #expect(defindex.growth == Decimal(string: "0.12"))
        let xoxno = pots[1]
        #expect(xoxno.growth == MockLendingService.positionValue - 20)
        let cetes = pots[2]
        #expect(cetes.growth == nil)
        #expect(cetes.priceChange != nil)
    }

    @Test("Total en dollars : XLM au prix de l'oracle, USDC à 1 $, CETES au prix d'Etherfuse ; un prix manquant → pas de total")
    func total() async throws {
        let (vault, lending, savings) = try await contexts()
        let pots = GrowPots.build(vault: vault, lending: lending, savings: savings)
        let total = try #require(GrowPots.totalUSD(pots, xlmUSD: Decimal(string: "0.25")!))
        let cetes = pots[2]
        let expected = Decimal(string: "0.12")! * Decimal(string: "0.25")! + (MockLendingService.positionValue - 20) + cetes.value! * (cetes.priceUSD! - cetes.basisPriceUSD!)
        #expect(total == expected)
        #expect(GrowPots.totalUSD(pots, xlmUSD: nil) == nil, "Jamais de total partiel")
    }

    @Test("XOXNO à renouveler : valeur inconnue (jamais zéro), hors du total ; avec dette : montré sans action")
    func lendingStates() async throws {
        let renew = try await MockLendingService(scenario: .needsRenewal, delay: .zero).fetchContext()
        let pot = try #require(GrowPots.build(vault: nil, lending: renew, savings: nil).first)
        #expect(pot.state == .needsRenewal && pot.value == nil && !pot.canMove)
        #expect(GrowPots.totalUSD([pot], xlmUSD: 1) == 0)
        let debt = try await MockLendingService(scenario: .hasDebt, delay: .zero).fetchContext()
        #expect(GrowPots.build(vault: nil, lending: debt, savings: nil).first?.state == .hasDebt)
    }

    @Test("Courbe : départ à zéro au jour du dépôt, puis les relevés ; « THIS WEEK » seulement avec un relevé d'il y a 7 jours")
    func history() {
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        let day: TimeInterval = 86_400
        let pot = GrowPot(
            mark: .defindex, drawerID: "main", drawerAddress: "C", asset: .xlm, state: .growing, value: Decimal(string: "50.12"),
            putIn: 50, since: now.addingTimeInterval(-26 * day), basisPriceUSD: nil, priceUSD: nil, withdrawableNow: nil
        )
        let readings = [
            PotReading(day: now.addingTimeInterval(-10 * day), value: Decimal(string: "0.05")!),
            PotReading(day: now.addingTimeInterval(-8 * day), value: Decimal(string: "0.08")!),
            PotReading(day: now.addingTimeInterval(-1 * day), value: Decimal(string: "0.11")!),
        ]
        let series = PotHistory.series(of: pot, readings: readings)
        #expect(series.count == 4)
        #expect(zip(series, [0, 0.05, 0.08, 0.11]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(PotHistory.thisWeek(of: pot, readings: readings, now: now) == Decimal(string: "0.04"))
        #expect(PotHistory.thisWeek(of: pot, readings: [], now: now) == nil, "Sans relevé d'il y a 7 jours : masqué")
        #expect(PotHistory.days(since: pot.since, now: now) == 26)
        // Planté cette semaine : toute la croissance.
        let young = GrowPot(mark: .xoxno, drawerID: "main", drawerAddress: "C", asset: .usdc, state: .growing, value: 20, putIn: 19, since: now.addingTimeInterval(-2 * day), basisPriceUSD: nil, priceUSD: nil, withdrawableNow: nil)
        #expect(PotHistory.thisWeek(of: young, readings: [], now: now) == 1)
    }

    @Test("Un relevé par jour : le second du même jour remplace le premier")
    func onePerDay() {
        let store = MemoryPotHistoryStore()
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        store.record(PotReading(day: now, value: 1), potID: "p")
        store.record(PotReading(day: now.addingTimeInterval(60), value: 2), potID: "p")
        #expect(store.readings("p").map(\.value) == [2])
    }

    @Test("Les courbes : ligne plate pour une seule valeur, points entre 10 % et 85 % de la hauteur")
    func curvePoints() {
        #expect(ChimpGrowCurve.points([3]).map(\.y) == [0.475, 0.475])
        let points = ChimpGrowCurve.points([0, 1, 2])
        #expect(points.first?.y == 0.85 && points.last?.y == 0.10000000000000009 || abs((points.last?.y ?? 0) - 0.1) < 0.0001)
    }
}
