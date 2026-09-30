import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Étape 5A : le vrai Wallet. Prix (`prices.ts`), cartes du compte (`cards()`), lecture des soldes, affichage, Recevoir.
/// Vecteurs XDR calculés avec `@stellar/stellar-sdk` 17.0.1 (comme aux étapes précédentes).
struct WalletTests {
    private static let cardKey = try! ChipPublicKey(Data(hex:
        "049c8b29c76710018ed080005d7219800fb5fdc6d60c241a720a019545780def86c60bd495b97fc35aa3b144cf5f3bdda514cf9579eac3b426ee02e17797255beb"
    )!)
    private static let otherKey = MockChipReader.secp256k1Key
    private static let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private static let pocket = "CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q"

    private func decode(_ base64: String) throws -> SCValXDR {
        try SCValXDR(from: XDRDecoder(data: Data(base64Encoded: base64)!))
    }

    private func base64(_ value: SCValXDR) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }

    // MARK: Prix (netWorthIn, prices.test.ts)

    @Test("Total en dollars exact : 9 900 XLM à 0,20 $ + 100 XRP à 2 $ = 2 180 $")
    func netWorthSums() {
        let prices: [String: Decimal] = ["XLM": Decimal(string: "0.2")!, "XRP": 2, "USDC": 1]
        #expect(NetWorth.usd([("XLM", 9900), ("XRP", 100)], prices: prices) == 2180)
    }

    @Test("Pas de poussière de flottant : 0,1 + 0,2 XLM à 0,20 $ = 0,06 $")
    func netWorthExact() {
        let prices: [String: Decimal] = ["XLM": Decimal(string: "0.2")!]
        #expect(NetWorth.usd([("XLM", Decimal(string: "0.1")!), ("XLM", Decimal(string: "0.2")!)], prices: prices) == Decimal(string: "0.06")!)
    }

    @Test("Un avoir sans prix : pas de total partiel")
    func netWorthRefusesPartial() {
        #expect(NetWorth.usd([("BLND", 5)], prices: ["USDC": 1]) == nil)
        #expect(NetWorth.usd([("USDC", 1), ("XLM", 3)], prices: ["USDC": 1]) == nil)
    }

    @Test("Un solde nul n'a pas besoin de prix ; le total est tronqué au centime, jamais arrondi")
    func netWorthTruncates() {
        #expect(NetWorth.usd([("XLM", 0), ("USDC", 5)], prices: ["USDC": 1]) == 5)
        // 3 XLM à 0,23101338614133 $ = 0,69304… $ → 0,69 $ ; 0,999 USDC → 0,99 $.
        #expect(NetWorth.usd([("XLM", 3)], prices: ["XLM": Decimal(string: "0.23101338614133")!]) == Decimal(string: "0.69")!)
        #expect(NetWorth.usd([("USDC", Decimal(string: "0.999")!)], prices: ["USDC": 1]) == Decimal(string: "0.99")!)
    }

    @Test("Oracle : argument `Asset::Other(XLM)` identique au SDK JS")
    func oracleArgument() throws {
        #expect(try base64(ReflectorPriceOracle.assetArgument("XLM")) == "AAAAEAAAAAEAAAACAAAADwAAAAVPdGhlcgAAAAAAAA8AAAADWExNAA==")
    }

    @Test("Oracle : `PriceData` décodé à 14 décimales ; `None` ou prix nul → pas de prix")
    func oraclePriceDecoding() throws {
        let priceData = try decode("AAAAEQAAAAEAAAACAAAADwAAAAVwcmljZQAAAAAAAAoAAAAAAAAAAAAAFQKzFPl1AAAADwAAAAl0aW1lc3RhbXAAAAAAAAAFAAAAAGqxO4A=")
        #expect(ReflectorPriceOracle.price(from: priceData, decimals: 14) == Decimal(string: "0.23101338614133")!)
        #expect(ReflectorPriceOracle.price(from: .void, decimals: 14) == nil)
        let zero = SCValXDR.map([SCMapEntryXDR(key: .symbol("price"), val: .i128(Int128PartsXDR(hi: 0, lo: 0)))])
        #expect(ReflectorPriceOracle.price(from: zero, decimals: 14) == nil)
    }

    @Test("Oracle : stablecoins à 1 $ sans aucune lecture réseau")
    @MainActor func oracleStables() async {
        // Adresse RPC invalide : un appel réseau échouerait, la réponse prouve qu'il n'y en a pas eu.
        let config = PriceOracleConfig(
            rpc: URL(string: "https://invalid.invalid")!, passphrase: "", cexFeed: "", fxFeed: "",
            simulationSource: PriceOracleConfig.reflector.simulationSource, decimals: 14,
            cacheDuration: .seconds(300), stableUSD: ["USDC"]
        )
        #expect(await ReflectorPriceOracle(config: config).usdPrices(for: ["usdc"]) == ["USDC": 1])
    }

    // MARK: cards() (readAccountCards)

    @Test("`cards()` : Vec<CardSigner> du SDK JS décodé (clé et courbe)")
    func decodeCards() throws {
        let raw = try decode("AAAAEAAAAAEAAAABAAAAEQAAAAEAAAACAAAADwAAAAVjdXJ2ZQAAAAAAABAAAAABAAAAAQAAAA8AAAAJU2VjcDI1NmsxAAAAAAAADwAAAANrZXkAAAAADQAAAEEEnIspx2cQAY7QgABdchmAD7X9xtYMJBpyCgGVRXgN74bGC9SVuX/DWqOxRM9fO92lFM+VeerDtCbuAuF3lyVb6wAAAA==")
        let cards = try ChimpAccountClient.decodeCards(raw)
        #expect(cards.count == 1)
        #expect(cards.first?.publicKey == Self.cardKey)
        #expect(cards.first?.curve == .secp256k1)
        // Aller-retour avec l'encodage du constructeur (déjà vérifié contre le terminal), pour P-256 aussi.
        let r1 = ChipAuthEncoding.cardSigner(publicKey: MockChipReader.p256Key, curve: .p256)
        #expect(try ChimpAccountClient.decodeCards(.vec([r1])).first?.curve == .p256)
    }

    @Test("`cards()` : courbe inconnue ou clé mal formée → erreur, jamais une liste raccourcie")
    func decodeCardsRejects() {
        let unknown = SCValXDR.map([
            SCMapEntryXDR(key: .symbol("curve"), val: .vec([.symbol("Ed25519")])),
            SCMapEntryXDR(key: .symbol("key"), val: .bytes(Self.cardKey.bytes)),
        ])
        #expect(throws: StellarError.self) { try ChimpAccountClient.decodeCards(.vec([unknown])) }
        let short = SCValXDR.map([
            SCMapEntryXDR(key: .symbol("curve"), val: .vec([.symbol("Secp256k1")])),
            SCMapEntryXDR(key: .symbol("key"), val: .bytes(Data(repeating: 4, count: 33))),
        ])
        #expect(throws: StellarError.self) { try ChimpAccountClient.decodeCards(.vec([short])) }
        #expect(throws: StellarError.self) { try ChimpAccountClient.decodeCards(.void) }
    }

    // MARK: Lecture du Wallet (loadAccountView)

    @MainActor
    private func session(cards: [SavedCard], firstName: String? = "Léo") -> AppSession {
        var wallet = LocalWallet()
        wallet.firstName = firstName
        wallet.account = SavedAccount(address: Self.account, cards: cards)
        return AppSession(store: InMemoryLocalWalletStore(wallet), network: .testnet)
    }

    private static let savedCard = SavedCard(publicKey: cardKey.hex, chip: "infineon2Go", tokenID: 7, pocket: pocket, name: "Banana", color: "banana")

    @Test("Wallet : cartes du compte dans l'ordre du contrat, nom, couleur et numéro locaux, soldes de chaque tiroir")
    @MainActor func readsWallet() async throws {
        let chain = FakeWalletChain()
        chain.members = [Self.cardKey, Self.otherKey]
        chain.balances = [
            Self.account: [AssetAmount(code: "XLM", amount: 100), AssetAmount(code: "USDC", amount: 0)],
            Self.pocket: [AssetAmount(code: "XLM", amount: 0), AssetAmount(code: "USDC", amount: 25)],
            "COTHERPOCKET": [AssetAmount(code: "XLM", amount: 0), AssetAmount(code: "USDC", amount: 0)],
        ]
        chain.pockets = [Self.otherKey: "COTHERPOCKET"]
        chain.tokens = [Self.otherKey: 12]
        let oracle = FakeOracle(prices: ["XLM": Decimal(string: "0.25")!, "USDC": 1])
        let source = ChainWalletDataSource(session: session(cards: [Self.savedCard]), chain: chain, oracle: oracle)

        let snapshot = try await source.fetchWallet()
        #expect(source.firstName == "Léo")
        #expect(snapshot.main.assets == [AssetAmount(code: "XLM", amount: 100), AssetAmount(code: "USDC", amount: 0)])
        #expect(snapshot.cards.map(\.id) == [Self.cardKey.hex, Self.otherKey.hex])
        #expect(snapshot.cards[0].name == "Banana")
        #expect(snapshot.cards[0].color == .banana)
        #expect(snapshot.cards[0].number == "0007")
        #expect(snapshot.cards[0].assets.last == AssetAmount(code: "USDC", amount: 25))
        // Carte inconnue sur ce téléphone : Pocket demandée à la factory, numéro lu sur le NFT, nom par défaut.
        #expect(snapshot.cards[1].number == "0012")
        #expect(snapshot.cards[1].color == .jungle)
        #expect(chain.pocketLookups == [Self.otherKey])
        // Prix demandés seulement pour les actifs détenus.
        #expect(oracle.requested == [["XLM", "USDC"]])
        #expect(snapshot.usdPrices["XLM"] == Decimal(string: "0.25")!)
    }

    @Test("Wallet : numéro illisible → « ···· » ; carte sans Pocket → aucun solde")
    @MainActor func unknownNumberAndNoPocket() async throws {
        let chain = FakeWalletChain()
        chain.members = [Self.otherKey]
        chain.balances = [Self.account: [AssetAmount(code: "XLM", amount: 0), AssetAmount(code: "USDC", amount: 0)]]
        let oracle = FakeOracle(prices: [:])
        let snapshot = try await ChainWalletDataSource(session: session(cards: []), chain: chain, oracle: oracle).fetchWallet()
        #expect(snapshot.cards.first?.number == "····")
        #expect(snapshot.cards.first?.assets == [])
        // Tout est à zéro : aucun prix à demander.
        #expect(oracle.requested.isEmpty)
    }

    @Test("Wallet : un solde illisible fait échouer la lecture (jamais « zéro »), pour garder les soldes précédents")
    @MainActor func balanceFailureThrows() async {
        let chain = FakeWalletChain()
        chain.members = [Self.cardKey]
        chain.balances = [Self.account: [AssetAmount(code: "XLM", amount: 1)]]
        // Pas de solde pour la Pocket : le faux lève une erreur.
        let source = ChainWalletDataSource(session: session(cards: [Self.savedCard]), chain: chain, oracle: FakeOracle(prices: [:]))
        await #expect(throws: (any Error).self) { try await source.fetchWallet() }
    }

    @Test("Wallet : les cartes du compte deviennent des indices « carte → compte » (sans réécrire s'ils existent)")
    @MainActor func remembersHints() async throws {
        let chain = FakeWalletChain()
        chain.members = [Self.cardKey]
        chain.balances = [
            Self.account: [AssetAmount(code: "XLM", amount: 0)],
            Self.pocket: [AssetAmount(code: "XLM", amount: 0)],
        ]
        let store = InMemoryLocalWalletStore({
            var wallet = LocalWallet()
            wallet.account = SavedAccount(address: Self.account, cards: [Self.savedCard])
            return wallet
        }())
        let session = AppSession(store: store, network: .testnet)
        let source = ChainWalletDataSource(session: session, chain: chain, oracle: FakeOracle(prices: [:]))
        _ = try await source.fetchWallet()
        #expect(session.wallet.hint(for: Self.cardKey) == Self.account)
        let saves = store.saveCount
        _ = try await source.fetchWallet()
        #expect(store.saveCount == saves)
    }

    @Test("Wallet : pas de compte sur le téléphone → erreur")
    @MainActor func noAccount() async {
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let source = ChainWalletDataSource(session: session, chain: FakeWalletChain(), oracle: FakeOracle(prices: [:]))
        await #expect(throws: ChainWalletDataSource.ReadError.self) { try await source.fetchWallet() }
    }

    @Test("Prénom : lu sur le téléphone, affiché même si le premier chargement échoue")
    @MainActor func firstNameWithoutNetwork() async {
        let chain = FakeWalletChain()
        chain.members = [Self.cardKey]
        // Aucun solde : la lecture échoue.
        let model = WalletViewModel(dataSource: ChainWalletDataSource(
            session: session(cards: [Self.savedCard], firstName: "Barth"), chain: chain, oracle: FakeOracle(prices: [:])
        ))
        #expect(model.firstName == "Barth")
        await model.refresh()
        #expect(model.phase == .failed)
        #expect(model.firstName == "Barth")
    }

    // MARK: Affichage

    private func snapshot(prices: [String: Decimal]) -> WalletSnapshot {
        WalletSnapshot(
            currency: .usd,
            main: DrawerBalance(assets: [AssetAmount(code: "XLM", amount: 1000), AssetAmount(code: "USDC", amount: 20)]),
            cards: [CardBalance(id: "k", number: "0007", name: "Banana", color: .banana, assets: [AssetAmount(code: "USDC", amount: 25)])],
            weeklyChange: 1, usdPrices: prices, fetchedAt: .distantPast
        )
    }

    @Test("Affichage : tout est en dollars quand chaque actif détenu a un prix")
    @MainActor func formatsDollars() {
        let content = WalletViewModel.format(snapshot(prices: ["XLM": Decimal(string: "0.2")!, "USDC": 1]))
        let currency = Decimal.FormatStyle.Currency(code: "USD").presentation(.narrow)
        #expect(content.total == Decimal(245).formatted(currency))
        #expect(content.mainAmount == Decimal(220).formatted(currency))
        #expect(content.cards.first?.amount == Decimal(25).formatted(currency))
        #expect(content.cards.first?.number == "0007")
        #expect(!content.isShowingAssetAmounts)
        #expect(content.weeklyChange != nil)
    }

    @Test("Affichage : prix du XLM absent → montants par actif là où il y a du XLM, dollars ailleurs")
    @MainActor func formatsAssetAmounts() {
        let content = WalletViewModel.format(snapshot(prices: ["USDC": 1]))
        let number = { (value: Decimal) in value.formatted(.number.precision(.fractionLength(0...2))) }
        #expect(content.isShowingAssetAmounts)
        #expect(content.total == "\(number(1000)) XLM · \(number(45)) USDC")
        #expect(content.mainAmount == "\(number(1000)) XLM · \(number(20)) USDC")
        #expect(content.cards.first?.amount == Decimal(25).formatted(Decimal.FormatStyle.Currency(code: "USD").presentation(.narrow)))
        #expect(content.weeklyChange == nil)
    }

    @Test("Affichage : tout à zéro → solde nul, sans prix")
    @MainActor func formatsZero() {
        var empty = snapshot(prices: [:])
        empty.main.assets = [AssetAmount(code: "XLM", amount: 0)]
        empty.cards[0].assets = []
        let content = WalletViewModel.format(empty)
        #expect(content.isZeroBalance)
        #expect(!content.isShowingAssetAmounts)
    }

    // MARK: Recevoir

    @Test("Recevoir : le Main account puis la Pocket de chaque carte connue, noms et couleurs locaux")
    @MainActor func receiveAddresses() async throws {
        let withoutPocket = SavedCard(publicKey: Self.otherKey.hex, chip: "infineon2Go", tokenID: nil, pocket: nil, name: nil, color: nil)
        let options = try await LocalReceiveDataSource(session: session(cards: [Self.savedCard, withoutPocket])).fetchReceiveOptions()
        #expect(options.network == .testnet)
        #expect(options.drawers.map(\.address) == [Self.account, Self.pocket])
        #expect(options.drawers.last?.kind == .card(name: "Banana", color: .banana))
    }
}

// MARK: Faux

@MainActor
private final class FakeWalletChain: WalletChain {
    var members: [ChipPublicKey] = []
    var balances: [String: [AssetAmount]] = [:]
    var pockets: [ChipPublicKey: String] = [:]
    var tokens: [ChipPublicKey: UInt32] = [:]
    private(set) var pocketLookups: [ChipPublicKey] = []

    func cards(of account: String) async throws -> [AccountCard] { members.map { AccountCard(publicKey: $0, curve: .secp256k1) } }

    func balances(of address: String) async throws -> [AssetAmount] {
        guard let found = balances[address] else { throw URLError(.timedOut) }
        return found
    }

    func pocket(of card: ChipPublicKey) async throws -> String? {
        pocketLookups.append(card)
        return pockets[card]
    }

    func tokenID(of card: ChipPublicKey) async throws -> UInt32 {
        guard let token = tokens[card] else { throw URLError(.timedOut) }
        return token
    }
}

@MainActor
private final class FakeOracle: PriceOracle {
    let prices: [String: Decimal]
    private(set) var requested: [Set<String>] = []

    init(prices: [String: Decimal]) {
        self.prices = prices
    }

    func usdPrices(for codes: Set<String>) async -> [String: Decimal] {
        requested.append(codes)
        return prices.filter { codes.contains($0.key) }
    }
}
