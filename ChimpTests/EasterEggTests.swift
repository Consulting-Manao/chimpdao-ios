import Foundation
import Testing
@testable import ChimpDAO

/// Easter eggs J1 à J3 (règles validées le 2026-09-30).
struct EasterEggTests {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("J1 : 7 taps en moins de 3 s ; 6 taps, ou 7 trop lents, ne suffisent pas")
    func bananaTaps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let quick = (0..<7).map { start.addingTimeInterval(Double($0) * 0.4) }
        #expect(EasterEggRules.isBananaMode(quick))
        #expect(!EasterEggRules.isBananaMode(Array(quick.prefix(6))))
        let slow = (0..<7).map { start.addingTimeInterval(Double($0) * 0.6) }
        #expect(!EasterEggRules.isBananaMode(slow))
        #expect(EasterEggRules.isBananaMode([start.addingTimeInterval(-60)] + quick), "Seuls les 7 derniers comptent")
    }

    @Test("J2 : seulement entre 3 h 00 et 3 h 59")
    func nightOwlHour() {
        #expect(EasterEggRules.isNightOwlHour(date(12, 3, 0), calendar: paris))
        #expect(EasterEggRules.isNightOwlHour(date(12, 3, 59), calendar: paris))
        #expect(!EasterEggRules.isNightOwlHour(date(12, 2, 59), calendar: paris))
        #expect(!EasterEggRules.isNightOwlHour(date(12, 4, 0), calendar: paris))
        #expect(!EasterEggRules.isNightOwlHour(date(12, 15, 30), calendar: paris))
    }

    @Test("J2 : une fois par nuit ; la nuit suivante, de nouveau")
    func nightOwlOncePerNight() {
        let preferences = AppPreferences(store: InMemoryPreferencesStore())
        let model = WalletViewModel(dataSource: MockWalletDataSource(), preferences: preferences)
        model.openedAt(date(12, 15), calendar: paris)
        #expect(model.celebration == nil)
        model.openedAt(date(12, 3, 10), calendar: paris)
        #expect(model.celebration == .nightOwl)
        model.dismissCelebration()
        model.openedAt(date(12, 3, 40), calendar: paris)
        #expect(model.celebration == nil, "Déjà vu cette nuit")
        model.openedAt(date(13, 3, 5), calendar: paris)
        #expect(model.celebration == .nightOwl)
        let catalog = WalletViewModel(dataSource: MockWalletDataSource())
        catalog.openedAt(date(12, 3), calendar: paris)
        #expect(catalog.celebration == nil, "Sans préférences (catalogue) : rien")
    }

    @Test("J3 : passer de moins de 1 000 $ à 1 000 $ ou plus ; jamais sans lecture d'avant, ni en redescendant")
    func crossing() {
        #expect(EasterEggRules.crossesThousand(from: 999.99, to: 1_000))
        #expect(EasterEggRules.crossesThousand(from: 10, to: 5_000))
        #expect(!EasterEggRules.crossesThousand(from: nil, to: 5_000), "Première lecture : rien n'a été franchi")
        #expect(!EasterEggRules.crossesThousand(from: 1_200, to: 1_500))
        #expect(!EasterEggRules.crossesThousand(from: 1_200, to: 800))
        #expect(!EasterEggRules.crossesThousand(from: 800, to: nil))
    }

    @Test("J3 : le total se compte en dollars, quelle que soit la devise affichée ; pas de total sans tous les prix")
    func usdTotal() {
        func snapshot(xlm: Decimal, prices: [String: Decimal], currency: DisplayCurrency = .eur) -> WalletSnapshot {
            WalletSnapshot(
                currency: currency, main: DrawerBalance(assets: [AssetAmount(code: "XLM", amount: xlm), AssetAmount(code: "USDC", amount: 100)]),
                cards: [], weeklyChange: nil, usdPrices: prices, fetchedAt: .now
            )
        }
        #expect(EasterEggRules.usdTotal(snapshot(xlm: 3_000, prices: ["XLM": Decimal(string: "0.3")!, "USDC": 1, "EUR": Decimal(string: "1.1")!])) == 1_000)
        #expect(EasterEggRules.usdTotal(snapshot(xlm: 3_000, prices: ["USDC": 1])) == nil)
    }

    /// Un compte dont les lectures se suivent.
    private final class Readings: WalletDataSource {
        var totals: [Decimal]
        var accountAddress: String? = "CMAIN"
        var firstName: String? { "Barth" }
        init(_ totals: [Decimal]) { self.totals = totals }
        func fetchWallet() async throws -> WalletSnapshot {
            let usdc = totals.removeFirst()
            return WalletSnapshot(
                currency: .usd, main: DrawerBalance(assets: [AssetAmount(code: "USDC", amount: usdc)]), cards: [],
                weeklyChange: nil, usdPrices: ["USDC": 1], fetchedAt: .now
            )
        }
    }

    @Test("J3 dans le Wallet : une seule fête par compte, gardée d'un lancement à l'autre")
    func thousandaireOncePerAccount() async {
        let store = InMemoryPreferencesStore()
        let preferences = AppPreferences(store: store)
        let source = Readings([800, 1_200, 700, 1_500])
        let model = WalletViewModel(dataSource: source, preferences: preferences)
        await model.refresh()
        #expect(model.celebration == nil)
        await model.refresh()
        #expect(model.celebration == .thousandaire)
        model.dismissCelebration()
        await model.refresh()
        await model.refresh()
        #expect(model.celebration == nil, "Déjà fêté pour ce compte")
        #expect(AppPreferences(store: store).thousandaireAccounts == ["CMAIN"])

        let other = Readings([800, 1_200])
        other.accountAddress = "COTHER"
        let second = WalletViewModel(dataSource: other, preferences: preferences)
        await second.refresh()
        await second.refresh()
        #expect(second.celebration == .thousandaire, "Un autre compte a sa propre fête")
    }
}
