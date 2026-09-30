import Foundation
import Testing
@testable import ChimpDAO

/// Réglages de base (I2) : nom et couleur des cartes, prénom, « Disconnect this phone ». Données du téléphone seulement.
struct SettingsTests {
    private let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let k1 = MockChipReader.secp256k1Key.hex
    private let r1 = MockChipReader.p256Key.hex

    private func session(_ wallet: LocalWallet) -> (AppSession, InMemoryLocalWalletStore) {
        let store = InMemoryLocalWalletStore(wallet)
        return (AppSession(store: store, network: .testnet), store)
    }

    private var namedWallet: LocalWallet {
        LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: account, cards: [
                SavedCard(publicKey: k1, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: "Banana", color: "banana"),
            ]),
            cardHints: [CardHint(key: k1, account: account, at: Date(timeIntervalSince1970: 1))]
        )
    }

    /// Carte lue par le Wallet que ce téléphone ne connaît pas (ajoutée ailleurs), P-256.
    private var duoxFromWallet: CardBalance {
        CardBalance(id: r1, number: "0913", name: "Card", color: .jungle, assets: [], pocket: "CPOCKET913", tokenID: 913, chip: .duox)
    }

    @Test("La puce d'une carte du compte vient de sa courbe (secp256k1 = Infineon, P-256 = DUOX)")
    func chipFromCurve() {
        #expect(AccountCard(publicKey: MockChipReader.secp256k1Key, curve: .secp256k1).chip == .infineon2Go)
        #expect(AccountCard(publicKey: MockChipReader.p256Key, curve: .p256).chip == .duox)
    }

    @Test("Liste : les cartes du compte dans l'ordre lu par le Wallet, noms et couleurs du téléphone, « Card » sinon")
    func cardList() {
        let (session, _) = session(namedWallet)
        let banana = CardBalance(id: k1, number: "0007", name: "Banana", color: .banana, assets: [], pocket: "CPOCKET7", tokenID: 7, chip: .infineon2Go)
        let model = SettingsModel(session: session, walletCards: [duoxFromWallet, banana])
        #expect(model.cards.map(\.id) == [r1, k1])
        #expect(model.cards[0].displayName == "Card")
        #expect(model.cards[1].displayName == "Banana" && model.cards[1].color == .banana)
    }

    @Test("Wallet pas encore chargé : les cartes enregistrées sur le téléphone")
    func cardListWithoutWallet() {
        let (session, _) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        #expect(model.cards.map(\.id) == [k1])
        #expect(model.cards[0].number == "0007")
    }

    @Test("Renommer une carte connue : nom et couleur changés, le reste gardé")
    func renameKnownCard() throws {
        let (session, store) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        model.edit(model.cards[0])
        #expect(!model.canSaveCard, "Rien n'a changé")
        model.editedName = "  Jungle "
        model.editedColor = .leaf
        #expect(model.saveCard())
        let saved = try #require(store.wallet.account?.cards.first)
        #expect(saved.name == "Jungle" && saved.color == "leaf")
        #expect(saved.tokenID == 7 && saved.pocket == "CPOCKET7" && saved.chip == "infineon2Go")
        #expect(model.editingCard == nil)
    }

    @Test("Renommer une carte que le téléphone ne connaissait pas : elle est enregistrée avec sa puce, son NFT et son wallet")
    func renameUnknownCard() throws {
        let (session, store) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [duoxFromWallet])
        model.edit(try #require(model.cards.first { $0.id == r1 }))
        model.editedName = "Leaf"
        model.editedColor = .leaf
        #expect(model.saveCard())
        let saved = try #require(store.wallet.account?.cards.first { $0.publicKey == r1 })
        #expect(saved == SavedCard(publicKey: r1, chip: "duox", tokenID: 913, pocket: "CPOCKET913", name: "Leaf", color: "leaf"))
        #expect(store.wallet.account?.cards.count == 2)
    }

    @Test("Nom vide ou trop long : refusé")
    func invalidNames() {
        let (session, _) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        model.edit(model.cards[0])
        model.editedName = "   "
        #expect(!model.canSaveCard)
        model.editedName = String(repeating: "a", count: 21)
        #expect(!model.canSaveCard)
        #expect(!model.saveCard())
    }

    @Test("Prénom : modifié sur le téléphone")
    func firstName() {
        let (session, store) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        model.editFirstName()
        #expect(model.editedFirstName == "Barth")
        #expect(!model.canSaveFirstName)
        model.editedFirstName = "Léo"
        model.saveFirstName()
        #expect(store.wallet.firstName == "Léo")
        #expect(!model.isEditingFirstName)
    }

    @Test("Disconnect this phone : le compte se ferme (l'app revient à A1), mais le prénom et les noms des cartes sont gardés")
    func disconnect() {
        let (session, store) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        #expect(!model.hasPendingPayment)
        model.disconnect()
        #expect(store.wallet.account == nil)
        #expect(store.wallet.firstName == "Barth")
        #expect(store.wallet.disconnectedAccounts == [namedWallet.account!])
        #expect(store.wallet.cardHints == namedWallet.cardHints)
        #expect(store.wallet.tourSeen)
        #expect(session.showsOnboarding)
    }

    @Test("Reconnexion au compte fermé : toutes ses cartes retrouvent leur nom et leur couleur, le compte fermé est retiré")
    func reconnectRestoresNames() throws {
        var wallet = namedWallet
        wallet.account?.cards.append(SavedCard(publicKey: r1, chip: "duox", tokenID: 913, pocket: "CPOCKET913", name: "Leaf", color: "leaf"))
        let (session, store) = session(wallet)
        try session.disconnect()
        try session.signIn(account: account, card: SavedCard(publicKey: k1, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: nil, color: nil))
        #expect(store.wallet.account == wallet.account)
        #expect(store.wallet.disconnectedAccounts == nil)
        #expect(store.wallet.firstName == "Barth")
    }

    @Test("Reconnexion à un autre compte : ses noms ne viennent pas du compte fermé, qui reste gardé")
    func otherAccountKeepsDisconnected() throws {
        let (session, store) = session(namedWallet)
        try session.disconnect()
        let other = "CBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        try session.signIn(account: other, card: SavedCard(publicKey: r1, chip: "duox", tokenID: 9, pocket: nil, name: "Pinky", color: "pink"))
        #expect(store.wallet.account?.cards.map(\.name) == ["Pinky"])
        #expect(store.wallet.disconnectedAccounts == [namedWallet.account!])
    }

    @Test("Paiement en attente : la déconnexion est refusée, rien n'est effacé")
    func disconnectRefusedWhilePending() {
        var wallet = namedWallet
        let trace = PaymentTrace(token: "T", from: account, destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121)
        wallet.pendingSend = PendingSend(trace: trace, recipient: "G", recipientName: nil, drawerTitle: "Main account", asset: "XLM", amount: 1, signedAt: .now)
        let (session, store) = session(wallet)
        let model = SettingsModel(session: session, walletCards: [])
        #expect(model.hasPendingPayment)
        model.disconnect()
        #expect(store.wallet == wallet)
        #expect(model.saveError != nil)
        #expect(!session.showsOnboarding)
    }
}
