import Foundation
import Testing
@testable import ChimpDAO

/// Plusieurs comptes sur un téléphone (I6 « Switch account », session « Réglages », point 3).
struct AccountSwitchTests {
    private let leo = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let shop = "CCDO6JSHOPACCOUNTXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXDDYB"
    private let k1 = MockChipReader.secp256k1Key.hex
    private let r1 = MockChipReader.p256Key.hex

    private func card(_ key: String, name: String) -> SavedCard {
        SavedCard(publicKey: key, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET", name: name, color: "banana")
    }

    /// Léo affiché, Shop ouvert à côté.
    private var twoAccounts: LocalWallet {
        LocalWallet(
            firstName: "Léo", tourSeen: true,
            account: SavedAccount(address: leo, cards: [card(k1, name: "Banana")]),
            otherAccounts: [SavedAccount(address: shop, cards: [card(r1, name: "Till")], firstName: "Shop")]
        )
    }

    private func session(_ wallet: LocalWallet) -> (AppSession, InMemoryLocalWalletStore) {
        let store = InMemoryLocalWalletStore(wallet)
        return (AppSession(store: store, network: .testnet), store)
    }

    private var pending: PendingSend {
        PendingSend(
            trace: PaymentTrace(token: "t", from: leo, destination: shop, units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: shop, recipientName: nil, drawerTitle: "Main account", asset: "usdc", amount: 1, signedAt: .distantPast
        )
    }

    // MARK: Fichier local

    @Test("Comptes ouverts : le compte affiché (avec son prénom) d'abord, puis les autres ; un compte fermé n'y est pas")
    func openAccounts() {
        var wallet = twoAccounts
        wallet.disconnectedAccounts = [SavedAccount(address: "CCLOSED", cards: [])]
        #expect(wallet.openAccounts.map(\.address) == [leo, shop])
        #expect(wallet.openAccounts.map(\.firstName) == ["Léo", "Shop"])
        #expect(wallet.firstName(for: shop) == "Shop")
        #expect(wallet.knownAccount(shop)?.cards.first?.name == "Till")
        #expect(wallet.knownAccount("CCLOSED") != nil && wallet.otherAccount("CCLOSED") == nil)
        #expect(LocalWallet().openAccounts.isEmpty)
    }

    @Test("Un fichier écrit avant les autres comptes reste lisible")
    func oldFileStillReadable() throws {
        let json = #"{"version":1,"tourSeen":true,"cardHints":[],"account":{"address":"\#(leo)","cards":[]}}"#
        let wallet = try FileLocalWalletStore.decoder.decode(LocalWallet.self, from: Data(json.utf8))
        #expect(wallet.otherAccounts == nil && wallet.openAccounts.map(\.address) == [leo])
    }

    // MARK: Changer de compte

    @Test("Changer de compte : sans carte, le prénom suit, le compte quitté reste ouvert en tête des autres")
    func switchAccount() throws {
        let (session, store) = session(twoAccounts)
        try session.switchAccount(to: shop)
        #expect(store.wallet.account?.address == shop && store.wallet.firstName == "Shop")
        #expect(store.wallet.account?.firstName == nil)
        #expect(store.wallet.otherAccounts?.map(\.address) == [leo])
        #expect(store.wallet.otherAccounts?.first?.firstName == "Léo")
        #expect(store.wallet.otherAccounts?.first?.cards.first?.name == "Banana")
        try session.switchAccount(to: leo)
        #expect(store.wallet.account?.address == leo && store.wallet.firstName == "Léo")
    }

    @Test("Changer de compte : refusé si un paiement attend son issue, ou si le compte n'est pas ouvert ici")
    func switchRefusals() throws {
        var wallet = twoAccounts
        wallet.pendingSend = pending
        let (session, store) = session(wallet)
        #expect(throws: AppSession.SettingsError.pendingPayment) { try session.switchAccount(to: self.shop) }
        #expect(store.wallet.account?.address == leo)

        let (other, _) = self.session(twoAccounts)
        #expect(throws: AppSession.SettingsError.unknownAccount) { try other.switchAccount(to: "CUNKNOWN") }
    }

    @Test("Reconnexion (« + Add an account ») : le compte affiché rejoint les autres comptes ouverts")
    func signInKeepsCurrentAccount() throws {
        let (session, store) = session(LocalWallet(
            firstName: "Léo", tourSeen: true, account: SavedAccount(address: leo, cards: [card(k1, name: "Banana")])
        ))
        try session.signIn(account: shop, card: card(r1, name: "Till"), firstName: "Shop")
        #expect(store.wallet.account?.address == shop && store.wallet.firstName == "Shop")
        #expect(store.wallet.otherAccounts?.map(\.address) == [leo])
        #expect(store.wallet.otherAccounts?.first?.firstName == "Léo")
    }

    @Test("Reconnexion vers un autre compte refusée tant qu'un paiement du compte affiché attend son issue")
    func signInRefusedWhilePending() {
        var wallet = LocalWallet(firstName: "Léo", tourSeen: true, account: SavedAccount(address: leo, cards: []))
        wallet.pendingSend = pending
        let (session, store) = session(wallet)
        #expect(throws: AppSession.SettingsError.pendingPayment) {
            try session.signIn(account: self.shop, card: self.card(self.r1, name: "Till"))
        }
        #expect(store.wallet.account?.address == leo)
    }

    // MARK: Disconnect

    @Test("Disconnect avec plusieurs comptes : le compte affiché se ferme, le suivant s'affiche")
    func disconnectOpensNextAccount() throws {
        let (session, store) = session(twoAccounts)
        try session.disconnect()
        #expect(store.wallet.account?.address == shop && store.wallet.firstName == "Shop")
        #expect(store.wallet.otherAccounts == nil)
        #expect(store.wallet.disconnectedAccounts?.map(\.address) == [leo])
        #expect(store.wallet.disconnectedAccount(leo)?.firstName == "Léo")
        #expect(!session.showsOnboarding)

        try session.disconnect()
        #expect(store.wallet.account == nil && store.wallet.firstName == nil)
        #expect(store.wallet.disconnectedAccounts?.map(\.address) == [shop, leo])
        #expect(session.showsOnboarding)
    }

    @Test("« Erase everything » efface aussi les autres comptes ouverts")
    func eraseRemovesOtherAccounts() throws {
        let (session, store) = session(twoAccounts)
        try session.eraseEverything()
        #expect(store.wallet == LocalWallet())
    }

    // MARK: « + Add an account » (A2 à la racine)

    private func addAccountModel(
        wallet: LocalWallet, reader: MockChipReader.Scenario = .infineon, scenario: MockOnboardingService.Scenario = .member
    ) -> (OnboardingModel, InMemoryLocalWalletStore) {
        let (session, store) = session(wallet)
        let model = OnboardingModel(
            session: session, reader: MockChipReader(scenario: reader, delay: .zero),
            service: MockOnboardingService(scenario: scenario, delay: .zero), signer: MockChipSigner(delay: .zero),
            mode: .addAccount, makeSetup: { _ in throw CancellationError() }
        )
        return (model, store)
    }

    private let member = MockOnboardingService.memberAccount

    @Test("Carte d'un compte inconnu : reconnexion habituelle (PIN d'une Infineon), A2 à la racine")
    func addUnknownAccount() async throws {
        let (model, store) = addAccountModel(
            wallet: LocalWallet(firstName: "Shop", tourSeen: true, account: SavedAccount(address: shop, cards: [])),
            reader: .infineonWithPIN
        )
        #expect(!model.isReturning)
        await model.scan()
        #expect(model.path == [.reconnectPIN])
        #expect(store.wallet.account?.address == shop, "Rien n'est ouvert avant le PIN")
        model.cancelReconnection()
        #expect(model.path.isEmpty && model.reconnection == nil)
    }

    @Test("Carte d'un compte sans PIN à vérifier : ouvert, le compte affiché reste parmi les autres")
    func addAccountWithoutPIN() async throws {
        var wallet = LocalWallet(firstName: "Shop", tourSeen: true, account: SavedAccount(address: shop, cards: []))
        wallet.disconnectedAccounts = [SavedAccount(address: member, cards: [card(k1, name: "Banana")], firstName: "Léo")]
        let (model, store) = addAccountModel(wallet: wallet)
        await model.scan()
        #expect(store.wallet.account?.address == member && store.wallet.firstName == "Léo")
        #expect(store.wallet.otherAccounts?.map(\.address) == [shop])
        #expect(store.wallet.disconnectedAccounts == nil)
    }

    @Test("Carte d'un compte déjà ouvert à côté : il s'affiche directement ; carte du compte affiché : message")
    func addKnownOrCurrentAccount() async throws {
        let wallet = LocalWallet(
            firstName: "Shop", tourSeen: true, account: SavedAccount(address: shop, cards: []),
            otherAccounts: [SavedAccount(address: member, cards: [], firstName: "Léo")]
        )
        let (model, store) = addAccountModel(wallet: wallet, reader: .infineonWithPIN)
        await model.scan()
        #expect(model.path.isEmpty && store.wallet.account?.address == member)

        let (again, _) = addAccountModel(wallet: store.wallet)
        await again.scan()
        guard case .failed(let problem) = again.readingState else { Issue.record("\(again.readingState)"); return }
        #expect(problem.kind == .alreadyOpen)
    }

    @Test("Carte neuve ou orpheline : « This card isn't in an account yet », rien ne change")
    func addCardWithoutAccount() async {
        for scenario in [MockOnboardingService.Scenario.fresh, .orphan] {
            let wallet = LocalWallet(firstName: "Shop", tourSeen: true, account: SavedAccount(address: shop, cards: []))
            let (model, store) = addAccountModel(wallet: wallet, scenario: scenario)
            await model.scan()
            guard case .failed(let problem) = model.readingState else { Issue.record("\(model.readingState)"); continue }
            #expect(problem.kind == .notInAnAccount)
            #expect(model.path.isEmpty && store.wallet == wallet)
        }
    }

    // MARK: Réglages

    private struct FixedSummaries: AccountSummaryReader {
        func summary(of account: SavedAccount) async throws -> AccountSummary {
            AccountSummary(cardCount: 2, total: "$312.40")
        }
    }

    @Test("I6 : le compte affiché d'abord (total du Wallet), les autres avec leur total lu sur la chaîne")
    func accountRows() async {
        let (session, _) = session(twoAccounts)
        let model = SettingsModel(session: session, walletCards: [], walletTotal: "$1,485.00", summaries: FixedSummaries())
        #expect(model.accountName == "Léo's account")
        #expect(model.hasSeveralAccounts)
        #expect(model.accountRows.map(\.total) == ["$1,485.00", nil])
        #expect(model.accountRows[1].cardCount == 1, "Avant la lecture : les cartes connues du téléphone")
        await model.loadAccountSummaries()
        #expect(model.accountRows.map(\.name) == ["Léo's account", "Shop's account"])
        #expect(model.accountRows.map(\.isCurrent) == [true, false])
        #expect(model.accountRows[1] == SettingsModel.AccountRow(id: shop, name: "Shop's account", cardCount: 2, total: "$312.40", isCurrent: false))
        #expect(AccountsSheet.detail(model.accountRows[1]) == "2 cards · $312.40")
        #expect(AccountsSheet.detail(SettingsModel.AccountRow(id: "x", name: "", cardCount: 1, total: nil, isCurrent: false)) == "1 card")
    }

    @Test("I6 : changer de compte depuis les réglages ; refusé avec un paiement en attente (message « Not yet »)")
    func switchFromSettings() {
        let (session, store) = session(twoAccounts)
        let model = SettingsModel(session: session, walletCards: [])
        model.switchAccount(to: shop)
        #expect(store.wallet.account?.address == shop)

        var wallet = twoAccounts
        wallet.pendingSend = pending
        let (blocked, blockedStore) = self.session(wallet)
        let blockedModel = SettingsModel(session: blocked, walletCards: [])
        blockedModel.switchAccount(to: shop)
        #expect(blockedModel.isShowingPendingNotice && blockedStore.wallet.account?.address == leo)
        blockedModel.isShowingPendingNotice = false
        blockedModel.addAccount()
        #expect(blockedModel.isShowingPendingNotice && !blockedModel.isAddingAccount)
    }

    @Test("I6 : « + Add an account » ferme la feuille et ouvre la lecture ; « Disconnect » confirme après la feuille")
    func sheetActions() {
        let (session, _) = session(twoAccounts)
        let model = SettingsModel(session: session, walletCards: [])
        model.isShowingAccounts = true
        model.addAccount()
        #expect(!model.isShowingAccounts && model.isAddingAccount)
        #expect(model.makeAddAccountModel().mode == .addAccount)

        model.isShowingAccounts = true
        model.disconnectFromAccounts()
        #expect(!model.isShowingAccounts && !model.isConfirmingDisconnect)
        model.accountsSheetDismissed()
        #expect(model.isConfirmingDisconnect)
    }

    @Test("Nom d'un compte : son prénom, sinon la fin de son adresse ; un seul compte : pas de « plusieurs »")
    func accountName() {
        #expect(AccountName.text(firstName: "Léo", address: leo) == "Léo's account")
        #expect(AccountName.text(firstName: nil, address: leo) == "Account ···VVFR")
        let (single, _) = session(LocalWallet(firstName: "Léo", account: SavedAccount(address: leo, cards: [])))
        #expect(!SettingsModel(session: single, walletCards: []).hasSeveralAccounts)
    }
}
