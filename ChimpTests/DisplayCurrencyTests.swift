import Foundation
import Testing
@testable import ChimpDAO

/// Devise d'affichage (I3) : portage de `netWorthIn` (`reference/terminal/src/chain/prices.ts`), vecteurs repris de
/// `prices.test.ts`, plus le formatage et le branchement dans le Wallet et les pages de tiroir.
struct DisplayCurrencyTests {
    /// Taux de `prices.test.ts` : XLM 0,20 $, XRP 2 $, USDC 1 $, EUR 0,90 $.
    private let rates: [String: Decimal] = ["XLM": Decimal(string: "0.2")!, "XRP": 2, "USDC": 1, "EUR": Decimal(string: "0.9")!]
    private let holdings = [AssetAmount(code: "XLM", amount: 9900), AssetAmount(code: "XRP", amount: 100)]
    private let enUS = Locale(identifier: "en_US")

    private func money(_ currency: DisplayCurrency, _ prices: [String: Decimal]? = nil) -> DisplayMoney {
        DisplayMoney(currency: currency, usdPrices: prices ?? rates, locale: enUS)
    }

    @Test("netWorthIn : somme exacte en dollars (« 2,180 »)")
    func sumsInUSD() {
        #expect(money(.usd).value(holdings) == 2180)
    }

    @Test("netWorthIn : conversion par le taux de la devise, coupée à 2 décimales (2180 / 0,9 = 2 422,22 € ; 10 900 XLM)")
    func convertsThroughDenominationRate() {
        #expect(money(.eur).value(holdings) == Decimal(string: "2422.22")!)
        #expect(money(.xlm).value(holdings) == 10900)
    }

    @Test("netWorthIn : un avoir sans prix refuse le total, pas de total partiel")
    func refusesPartialTotal() {
        #expect(money(.usd).value([AssetAmount(code: "BLND", amount: 5)]) == nil)
    }

    @Test("netWorthIn : une devise sans prix refuse le total")
    func refusesUnpricedDenomination() {
        // Vecteur du terminal : CHF sans taux. CHF n'est plus proposé (non coté par Reflector) : même règle avec le yen.
        #expect(money(.jpy).value([AssetAmount(code: "USDC", amount: 1)]) == nil)
        #expect(money(.jpy).rate == nil)
        #expect(money(.eur, ["USDC": 1, "EUR": 0]).rate == nil, "Un prix nul ne sert jamais de diviseur")
    }

    @Test("netWorthIn : montants fractionnaires exacts (0,1 + 0,2 XLM à 0,20 $ = 0,06 $)")
    func keepsFractionsExact() {
        let value = money(.usd).value([AssetAmount(code: "XLM", amount: Decimal(string: "0.1")!), AssetAmount(code: "XLM", amount: Decimal(string: "0.2")!)])
        #expect(value == Decimal(string: "0.06")!)
    }

    @Test("Un solde nul n'a pas besoin de prix ; sans avoirs, le total vaut zéro")
    func zeroHoldings() {
        #expect(money(.usd).value([AssetAmount(code: "BLND", amount: 0), AssetAmount(code: "USDC", amount: 5)]) == 5)
        #expect(money(.eur).value([]) == 0)
    }

    @Test("Coupé, jamais arrondi : 1,999 $ reste 1,99 $ ; le yen n'a pas de décimales (243 210,9 → 243 210)")
    func truncatesToCurrencyDigits() {
        #expect(money(.usd).value([AssetAmount(code: "USDC", amount: Decimal(string: "1.999")!)]) == Decimal(string: "1.99")!)
        let jpy = money(.jpy, ["USDC": 1, "JPY": Decimal(string: "0.01")!])
        #expect(jpy.value([AssetAmount(code: "USDC", amount: Decimal(string: "2432.109")!)]) == 243210)
    }

    @Test("XLM affiché en XLM : exactement le solde (prix réel de l'oracle), pas 6 999,99 pour 7 000")
    func sameAssetStaysExact() {
        let prices: [String: Decimal] = ["XLM": Decimal(string: "0.22199559495484")!, "USDC": 1]
        let xlm = money(.xlm, prices)
        #expect(xlm.value([AssetAmount(code: "XLM", amount: 7000)]) == 7000)
        #expect(xlm.value([AssetAmount(code: "XLM", amount: Decimal(string: "1234.5678901")!)]) == Decimal(string: "1234.56")!)
        #expect(xlm.value([AssetAmount(code: "XLM", amount: 3000), AssetAmount(code: "XLM", amount: 7000)]) == 10000)
    }

    @Test("Prix demandés à l'oracle : les actifs détenus, plus la devise (sauf le dollar)")
    func priceCodes() {
        #expect(DisplayMoney.priceCodes(held: ["XLM", "USDC"], currency: .usd) == ["XLM", "USDC"])
        #expect(DisplayMoney.priceCodes(held: ["USDC"], currency: .eur) == ["USDC", "EUR"])
        #expect(DisplayMoney.priceCodes(held: ["XLM"], currency: .xlm) == ["XLM"])
    }

    @Test("Texte : symbole court, décimales de la devise, XLM à la suite du nombre")
    func text() {
        #expect(money(.usd).text(2180) == "$2,180.00")
        #expect(money(.eur).text(Decimal(string: "2422.22")!) == "€2,422.22")
        #expect(money(.gbp).text(Decimal(string: "12.5")!) == "£12.50")
        #expect(money(.jpy).text(243210) == "¥243,210")
        #expect(money(.xlm).text(10900) == "10,900 XLM")
        #expect(money(.xlm).text(Decimal(string: "6758.92")!) == "6,758.92 XLM")
        #expect(money(.usd).text(620, style: .wholeWhenRound) == "$620")
        #expect(money(.usd).text(Decimal(string: "6.2")!, style: .signed) == "+$6.20")
        #expect(money(.usd).text(1200, style: .upToDigits) == "$1,200")
    }

    @Test("Liste de la maquette I3 sans le franc suisse (non coté par Reflector), dans l'ordre ; valeurs de la ligne « Currency »")
    func catalogue() {
        #expect(DisplayCurrency.allCases.map(\.code) == ["USD", "EUR", "GBP", "JPY", "XLM"])
        #expect(DisplayCurrency(rawValue: "chf") == nil)
        #expect(DisplayCurrency.usd.settingsValue == "USD $")
        #expect(DisplayCurrency.xlm.title == "Show everything in XLM")
        #expect(!DisplayCurrency.xlm.isFiat && DisplayCurrency.jpy.fractionDigits == 0)
    }

    // MARK: Réglage

    @Test("Réglage : dollar par défaut, enregistré, relu, remis à zéro par « Erase everything »")
    func preference() throws {
        let store = InMemoryPreferencesStore()
        let preferences = AppPreferences(store: store)
        #expect(preferences.currency == .usd)
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet, preferences: preferences)
        let model = SettingsModel(session: session, walletCards: [])
        model.isChoosingCurrency = true
        model.choose(.gbp)
        #expect(!model.isChoosingCurrency)
        #expect(store.values[.currency] == "gbp")
        #expect(AppPreferences(store: store).currency == .gbp)
        #expect(AppPreferences(store: InMemoryPreferencesStore([.currency: "btc"])).currency == .usd)
        #expect(AppPreferences(store: InMemoryPreferencesStore([.currency: "chf"])).currency == .usd, "Ancien choix CHF : dollar")
        try session.eraseEverything()
        #expect(preferences.currency == .usd && store.values.isEmpty)
    }

    // MARK: Wallet et tiroirs

    private func snapshot(_ currency: DisplayCurrency, prices: [String: Decimal]) -> WalletSnapshot {
        WalletSnapshot(
            currency: currency,
            main: DrawerBalance(assets: [AssetAmount(code: "USDC", amount: 900), AssetAmount(code: "XLM", amount: 0)]),
            cards: [CardBalance(id: "k1", number: "0007", name: "Banana", color: .banana, assets: [AssetAmount(code: "XLM", amount: 1000)])],
            weeklyChange: nil, usdPrices: prices, fetchedAt: .distantPast
        )
    }

    @Test("Wallet en euros : total et tiroirs convertis ; sans taux de l'euro, montants par actif")
    func walletInEuros() {
        let euro = WalletViewModel.format(snapshot(.eur, prices: ["USDC": 1, "XLM": Decimal(string: "0.2")!, "EUR": Decimal(string: "0.9")!]))
        let expected = DisplayMoney(currency: .eur, usdPrices: [:])
        #expect(euro.total == expected.text(Decimal(string: "1222.22")!), "1 100 $ / 0,9")
        #expect(euro.mainAmount == expected.text(1000))
        #expect(euro.cards[0].amount == expected.text(Decimal(string: "222.22")!))
        #expect(!euro.isShowingAssetAmounts)

        let noRate = WalletViewModel.format(snapshot(.eur, prices: ["USDC": 1, "XLM": Decimal(string: "0.2")!]))
        #expect(noRate.isShowingAssetAmounts)
        #expect(noRate.total == WalletViewModel.assetText(snapshot(.eur, prices: [:]).allAssets))
    }

    @Test("Page d'un tiroir en XLM : total et valeur des tuiles en XLM")
    func drawerInXLM() {
        let snapshot = snapshot(.xlm, prices: ["USDC": 1, "XLM": Decimal(string: "0.2")!])
        let content = DrawerDetailModel.content(assets: snapshot.main.assets, snapshot: snapshot, signers: [], address: nil)
        let xlm = DisplayMoney(currency: .xlm, usdPrices: [:])
        #expect(content.total == xlm.text(4500), "900 USDC / 0,20 $")
        #expect(content.assets.map(\.value) == [xlm.text(4500, style: .wholeWhenRound)])
    }

    @Test("Lecture du Wallet : le prix de la devise est demandé à l'oracle avec les actifs détenus")
    func chainAsksDenominationPrice() async throws {
        let oracle = RecordingOracle()
        let preferences = AppPreferences(store: InMemoryPreferencesStore([.currency: "gbp"]))
        let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
        let session = AppSession(
            store: InMemoryLocalWalletStore(LocalWallet(account: SavedAccount(address: account, cards: []))),
            config: .testnet, preferences: preferences
        )
        let source = ChainWalletDataSource(session: session, chain: MainOnlyChain(), oracle: oracle)
        let snapshot = try await source.fetchWallet()
        #expect(snapshot.currency == .gbp)
        #expect(oracle.asked == ["USDC", "GBP"])
    }

    private final class RecordingOracle: PriceOracle, @unchecked Sendable {
        private(set) var asked: Set<String> = []
        func usdPrices(for codes: Set<String>) async -> [String: Decimal] {
            asked = codes
            return ["USDC": 1, "GBP": Decimal(string: "1.25")!]
        }
    }

    private struct MainOnlyChain: WalletChain {
        func cards(of account: String) async throws -> [AccountCard] { [] }
        func balances(of address: String) async throws -> [AssetAmount] { [AssetAmount(code: "USDC", amount: 10)] }
        func pocket(of card: ChipPublicKey) async throws -> String? { nil }
        func tokenID(of card: ChipPublicKey) async throws -> UInt32 { 0 }
    }
}

