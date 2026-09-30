import Foundation
import Testing
@testable import ChimpDAO

/// B2 · Main account et B3 · wallet d'une carte : soldes par actif, cartes qui signent, adresse, actions pré-remplies
/// depuis ce tiroir, historique filtré sans toucher au filtre de l'onglet Activity.
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
            currencyCode: "USD",
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
        )), network: .testnet)
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
        #expect(content.assets.map(\.band) == ["XLM · READY", "USDC · READY"])
        #expect(content.assets.first?.amount == SendAsset.xlm.formattedWithCode(800))
        #expect(content.assets.first?.value == Decimal(200).formatted(.currency(code: "USD").presentation(.narrow).precision(.fractionLength(0))), "Tuile : « $200 » (maquette B2e)")
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
        let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US")).presentation(.narrow)
        #expect(DrawerDetailModel.tileMoney(620, currency: usd) == "$620")
        #expect(DrawerDetailModel.tileMoney(Decimal(string: "62.5")!, currency: usd) == "$62.50")
        #expect(DrawerDetailModel.tileMoney(Decimal(string: "0.07")!, currency: usd) == "$0.07")
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

    @Test("LATELY (B2r) : les deux derniers mouvements de Main, signés pour Main, « today » / « yesterday »")
    func lately() {
        let t = ActivityViewModelTests.self
        let records = [
            t.transfer("old", t.maya, t.main, "USDC", "1", t.at(3, 9)),
            t.transfer("got", t.maya, t.main, "USDC", "12.5", t.at(1, 16)),
            t.transfer("move", t.main, t.jungle, "USDC", "50", t.at(0, 11)),
            t.transfer("other", t.jungle, t.maya, "USDC", "25", t.at(0, 14)),
        ]
        let rows = DrawerDetailModel.lately(
            records: records, drawer: t.main, drawers: t.drawers, cardName: { _ in nil }, calendar: t.calendar, now: t.now
        )
        #expect(rows.map(\.id) == ["stellar:move", "stellar:got"], "Main seulement, les plus récents, deux au plus")
        #expect(rows[0].title == "Moved to Jungle's wallet")
        #expect(rows[0].amount == ActivityViewModel.amountText(50, code: "USDC", sign: .negative))
        #expect(!rows[0].isIncoming)
        #expect(rows[0].meta.hasSuffix("· today"))
        #expect(rows[1].amount == ActivityViewModel.amountText(Decimal(string: "12.5")!, code: "USDC", sign: .positive))
        #expect(rows[1].isIncoming)
        #expect(rows[1].meta.hasSuffix("· yesterday"))
    }
}
