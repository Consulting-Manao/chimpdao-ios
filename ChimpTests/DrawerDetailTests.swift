import Foundation
import Testing
@testable import ChimpDAO

/// B1 · page d'un tiroir (Main ou le wallet d'une carte) : soldes par actif, cartes qui signent, adresse, actions
/// pré-remplies depuis ce tiroir, panneau du total (prêt / qui pousse), historique filtré sans toucher au filtre de
/// l'onglet Activity.
@MainActor
struct DrawerDetailTests {
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let k1 = MockChipReader.secp256k1Key.hex
    private let r1 = MockChipReader.p256Key.hex

    private struct FixedWallet: WalletDataSource {
        let snapshot: WalletSnapshot
        var firstName: String? { "Barth" }
        func fetchWallet() async throws -> WalletSnapshot { snapshot }
    }

    private func snapshot(prices: [String: Decimal] = ["XLM": Decimal(string: "0.25")!, "USDC": 1], cardAssets: [AssetAmount]? = nil) -> WalletSnapshot {
        WalletSnapshot(
            currency: .usd,
            main: DrawerBalance(assets: [AssetAmount(code: "XLM", amount: 800), AssetAmount(code: "USDC", amount: 620)]),
            cards: [
                CardBalance(id: k1, number: "0007", name: "Card", color: .jungle,
                            assets: cardAssets ?? [AssetAmount(code: "XLM", amount: 250), AssetAmount(code: "USDC", amount: 0)],
                            pocket: "CPOCKET7", tokenID: 7, chip: .infineon2Go),
                CardBalance(id: r1, number: "0913", name: "Card", color: .jungle, assets: [], pocket: "CPOCKET913", tokenID: 913, chip: .duox),
            ],
            weeklyChange: nil,
            usdPrices: prices,
            fetchedAt: .now
        )
    }

    private func model(_ selection: DrawerSelection, snapshot: WalletSnapshot? = nil, clipboard: AddressClipboard = RecordingClipboard()) async -> DrawerDetailModel {
        let session = AppSession(store: InMemoryLocalWalletStore(LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: account, cards: [
                SavedCard(publicKey: k1, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: "Banana", color: "banana"),
            ])
        )), config: .testnet)
        let wallet = WalletViewModel(dataSource: FixedWallet(snapshot: snapshot ?? self.snapshot()))
        await wallet.refresh()
        return DrawerDetailModel(selection: selection, wallet: wallet, session: session, clipboard: clipboard, copiedDuration: .zero)
    }

    @Test("Main (B2) : total en dollars, actifs non nuls avec leur valeur, toutes les cartes du compte signent, adresse du compte")
    func mainContent() async throws {
        let model = await model(.main)
        let content = try #require(model.content)
        #expect(content.total == Decimal(820).formatted(.currency(code: "USD").presentation(.narrow)))
        #expect(content.assets.map(\.code) == ["XLM", "USDC"])
        #expect(content.assets.first?.amount == SendAsset.xlm.formattedWithCode(800))
        #expect(content.assets.first?.value == Decimal(200).formatted(.currency(code: "USD").presentation(.narrow)), "Ligne N1b : « $200.00 » (maquette B1)")
        #expect(content.signers.first?.number == "0007", "Numéro pour le plateau des cartes")
        #expect(content.signers.map(\.name) == ["Banana", "Card"], "Nom du téléphone, sinon celui du Wallet")
        #expect(content.signers.first?.color == .banana)
        #expect(content.address == account)
        #expect(!content.isEmpty)
        #expect(model.selection.drawerID == "main")
    }

    @Test("Wallet d'une carte (B3) : seulement cette carte signe, adresse de sa Pocket, actif à zéro masqué")
    func cardContent() async throws {
        let model = await model(.card(k1))
        let content = try #require(model.content)
        #expect(content.assets.map(\.code) == ["XLM"])
        #expect(content.signers.map(\.name) == ["Banana"])
        #expect(content.address == "CPOCKET7")
        #expect(model.cardName == "Banana")
        #expect(model.cardColor == .banana)
        #expect(model.card?.number == "0007")
        #expect(model.cardCount == 2)
        #expect(model.selection.drawerID == k1)
    }

    @Test("Wallet vide : état vide (Send et Move n'ont pas de sens)")
    func emptyDrawer() async throws {
        let model = await model(.card(r1))
        let content = try #require(model.content)
        #expect(content.assets.isEmpty)
        #expect(content.isEmpty)
    }

    @Test("Prix du XLM absent : total par actif, pas de valeur en dollars pour le XLM")
    func missingPrice() async throws {
        let model = await model(.main, snapshot: snapshot(prices: ["USDC": 1]))
        let content = try #require(model.content)
        #expect(content.total == WalletViewModel.assetText([AssetAmount(code: "XLM", amount: 800), AssetAmount(code: "USDC", amount: 620)]))
        #expect(content.assets.first { $0.code == "XLM" }?.value == nil)
        #expect(content.assets.first { $0.code == "USDC" }?.value != nil)
    }

    @Test("Carte que le compte ne liste plus : l'écran le dit, sans soldes")
    func missingCard() async {
        let model = await model(.card("04dead"))
        #expect(model.isMissing)
        #expect(model.content == nil)
    }

    @Test("Tuiles : sans centimes pour un montant rond, avec sinon (« $620 », « $62.50 »)")
    func tileMoney() {
        let usd = DisplayMoney(currency: .usd, usdPrices: [:], locale: Locale(identifier: "en_US"))
        #expect(usd.text(620, style: .wholeWhenRound) == "$620")
        #expect(usd.text(Decimal(string: "62.5")!, style: .wholeWhenRound) == "$62.50")
        #expect(usd.text(Decimal(string: "0.07")!, style: .wholeWhenRound) == "$0.07")
    }

    @Test("Copier l'adresse : l'adresse complète, puis « Copied! »")
    func copyAddress() async {
        let clipboard = RecordingClipboard()
        let model = await model(.card(k1), clipboard: clipboard)
        model.copyAddress()
        #expect(clipboard.copied == ["CPOCKET7"])
        #expect(model.isCopied)
    }

    @Test("« Rename & colour » depuis B3 : l'écran des réglages, sur cette carte")
    func renameFromCard() async {
        let model = await model(.card(k1))
        let settings = model.makeRenameModel()
        #expect(settings?.editingCard?.id == k1)
        #expect(settings?.editedName == "Banana")
        #expect(await self.model(.main).makeRenameModel() == nil)
    }

    @Test("Send et Move depuis un tiroir : « From » est ce tiroir ; Move va vers Main")
    func prefilledFrom() async {
        let send = SendFlowModel(service: MockSendService(delay: .zero, nfcDelay: .zero), initialDrawerID: "0421")
        await send.load()
        #expect(send.selectedDrawer?.id == "0421")

        let move = SendFlowModel(service: MockSendService(delay: .zero, nfcDelay: .zero), kind: .move, initialDrawerID: "0688")
        await move.load()
        #expect(move.selectedDrawer?.id == "0688")
        #expect(move.destinationDrawer?.id == "main")

        let unknown = SendFlowModel(service: MockSendService(delay: .zero, nfcDelay: .zero), initialDrawerID: "gone")
        await unknown.load()
        #expect(unknown.selectedDrawer?.id == "main", "Tiroir disparu : Main")
    }

    @Test("Receive depuis un tiroir : ce tiroir est choisi")
    func prefilledReceive() async {
        let model = ReceiveViewModel(dataSource: MockReceiveDataSource(delay: .zero), initialDrawerID: "0688")
        await model.load()
        #expect(model.selectedDrawer?.id == "0688")
    }

    @Test("Historique d'un tiroir : ses lignes seulement, le filtre de l'onglet Activity ne bouge pas")
    func drawerHistory() async {
        let source = FakeActivitySource()
        source.stored = AccountActivity(records: [
            ActivityViewModelTests.transfer("a", ActivityViewModelTests.jungle, ActivityViewModelTests.maya, "USDC", "25", ActivityViewModelTests.at(0, 14)),
            ActivityViewModelTests.transfer("b", ActivityViewModelTests.maya, ActivityViewModelTests.main, "USDC", "1", ActivityViewModelTests.at(0, 9)),
        ])
        let activity = ActivityViewModel(source: source, calendar: ActivityViewModelTests.calendar, now: { ActivityViewModelTests.now })
        await activity.refresh()
        let jungle = activity.tickets(for: .drawer(ActivityViewModelTests.jungle)).flatMap(\.rows).map(\.id)
        #expect(jungle == ["stellar:a"])
        #expect(activity.filter == .all)
        #expect(activity.tickets.flatMap(\.rows).count == 2)
        #expect(activity.isEmpty(for: .drawer(ActivityViewModelTests.banana)))
        #expect(!activity.isEmpty(for: .drawer(ActivityViewModelTests.jungle)))
    }

    // MARK: Panneau du total (B1)

    private func usd(_ value: Decimal, whole: Bool = false) -> String {
        DisplayMoney(currency: .usd, usdPrices: ["USD": 1]).text(value, style: whole ? .wholeWhenRound : .standard)
    }

    private let prices: DisplayMoney = DisplayMoney(currency: .usd, usdPrices: ["XLM": Decimal(string: "0.25")!, "USDC": 1])

    @Test("B1 Main : le total compte ce qui pousse ($820 prêts + $500 = $1,320), parts sans centimes quand c'est rond")
    func splitWithGrowing() {
        let split = DrawerDetailModel.split(
            ready: [AssetAmount(code: "USDC", amount: 620), AssetAmount(code: "XLM", amount: 800)],
            growing: [DrawerDetailModel.GrowingPart(value: 500, fallback: "2,000 XLM")],
            money: prices
        )
        #expect(split.total == usd(1320))
        #expect(split.ready == usd(820, whole: true))
        #expect(split.growing == usd(500, whole: true))
        #expect(split.readyTotal == usd(820))
        #expect(split.growingTotal == usd(500))
        #expect(split.readyWeight == 820)
        #expect(split.growingWeight == 500)
    }

    @Test("B1 carte : rien ne pousse → pas de part verte, barre toute jaune")
    func splitNothingGrowing() {
        let split = DrawerDetailModel.split(ready: [AssetAmount(code: "XLM", amount: 250)], growing: [], money: prices)
        #expect(split.total == usd(Decimal(string: "62.5")!))
        #expect(split.ready == usd(Decimal(string: "62.5")!, whole: true))
        #expect(split.growing == nil)
        #expect(split.growingTotal == nil)
        #expect(split.readyWeight > 0)
        #expect(split.growingWeight == 0)
    }

    @Test("B1 tiroir vide : barre vide (deux parts à zéro)")
    func splitEmpty() {
        let split = DrawerDetailModel.split(ready: [], growing: [], money: prices)
        #expect(split.total == usd(0))
        #expect(split.readyWeight == 0)
        #expect(split.growingWeight == 0)
    }

    @Test("B1 sans prix pour une part : jamais de total partiel, montants par actif, barre à parts égales")
    func splitWithoutPrice() {
        let split = DrawerDetailModel.split(
            ready: [AssetAmount(code: "XLM", amount: 800)],
            growing: [DrawerDetailModel.GrowingPart(value: nil, fallback: "1,820 CETES")],
            money: prices
        )
        #expect(split.total == "\(WalletViewModel.assetText([AssetAmount(code: "XLM", amount: 800)])) · 1,820 CETES")
        #expect(split.ready == usd(200, whole: true), "La part prête a son prix : en dollars")
        #expect(split.growing == "1,820 CETES")
        #expect(split.readyWeight == 1)
        #expect(split.growingWeight == 1)
    }

    @Test("B1 : les stablebonds (CETES) vont dans « Growing », pas dans « Ready to spend »")
    func savingsAreGrowing() async {
        let model = await model(.card(k1), snapshot: snapshot(cardAssets: [AssetAmount(code: "XLM", amount: 250), AssetAmount(code: "CETES", amount: 1820)]))
        #expect(model.readyAssets.map(\.code) == ["XLM"])
        #expect(model.savingsAssets.map(\.code) == ["CETES"])
        #expect(model.content?.savings.map(\.code) == ["CETES"])
    }

    @Test("B1 : un sticker et un bandeau par couleur de carte")
    func scenes() {
        #expect(Set(ChimpCardColor.allCases.map { "\($0.sceneSticker)" }).count == ChimpCardColor.allCases.count)
        #expect(DrawerDetailView.assetName("USDC") == String(localized: "US Dollar"))
        #expect(DrawerDetailView.assetName("XLM") == String(localized: "Stellar"))
        #expect(DrawerDetailView.assetName("CETES") == "CETES")
    }
}
