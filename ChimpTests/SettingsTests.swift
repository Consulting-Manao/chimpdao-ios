import Foundation
import Testing
import UIKit
@testable import ChimpDAO

/// Réglages de base (I2) : nom et couleur des cartes, prénom, « Disconnect this phone ». Données du téléphone seulement.
struct SettingsTests {
    private let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let k1 = MockChipReader.secp256k1Key.hex
    private let r1 = MockChipReader.p256Key.hex

    private func session(_ wallet: LocalWallet) -> (AppSession, InMemoryLocalWalletStore) {
        let store = InMemoryLocalWalletStore(wallet)
        return (AppSession(store: store, config: .testnet), store)
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

    @Test("« Sounds » (tête de Chimpy) : un toucher coupe, un autre réactive ; gardé dans les préférences ; les deux têtes sont dans l'app")
    func soundsSetting() {
        let (session, _) = session(namedWallet)
        let model = SettingsModel(session: session, walletCards: [])
        #expect(model.soundsEnabled)
        model.soundsEnabled.toggle()
        #expect(!model.soundsEnabled)
        #expect(!session.preferences.soundsEnabled)
        model.soundsEnabled.toggle()
        #expect(session.preferences.soundsEnabled)
        #expect(UIImage(named: "ChimpySoundOn") != nil)
        #expect(UIImage(named: "ChimpySoundOff") != nil)
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
        #expect(store.wallet.firstName == nil, "Le prénom part avec le compte fermé")
        var closed = namedWallet.account!
        closed.firstName = "Barth"
        #expect(store.wallet.disconnectedAccounts == [closed])
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
        #expect(store.wallet.firstName == nil, "Le prénom du compte fermé ne passe pas à un autre compte")
        #expect(store.wallet.disconnectedAccounts?.first?.firstName == "Barth")
    }

    @Test("Deux comptes sur le même téléphone : chacun garde son prénom, dans les deux sens")
    func firstNamePerAccount() throws {
        let (session, store) = session(namedWallet)
        let other = "CBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        try session.disconnect()
        try session.signIn(account: other, card: SavedCard(publicKey: r1, chip: "duox", tokenID: 9, pocket: nil, name: "Pinky", color: "pink"), firstName: "Léo")
        #expect(store.wallet.firstName == "Léo")
        try session.disconnect()
        try session.signIn(account: account, card: SavedCard(publicKey: k1, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: nil, color: nil))
        #expect(store.wallet.firstName == "Barth")
        try session.disconnect()
        try session.signIn(account: other, card: SavedCard(publicKey: r1, chip: "duox", tokenID: 9, pocket: nil, name: nil, color: nil))
        #expect(store.wallet.firstName == "Léo")
        #expect(store.wallet.account?.cards.first?.name == "Pinky")
    }

    @Test("Fichier de la version précédente (prénom resté au niveau du téléphone) : il ne revient qu'au dernier compte fermé")
    func legacyFirstName() {
        let other = "CBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        let legacy = LocalWallet(firstName: "Barth", tourSeen: true, disconnectedAccounts: [
            SavedAccount(address: account, cards: []), SavedAccount(address: other, cards: []),
        ])
        #expect(legacy.firstName(for: account) == "Barth")
        #expect(legacy.firstName(for: other) == nil)
        #expect(legacy.firstName(for: "CUNKNOWN") == nil)
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

    // MARK: Session « Avant TestFlight », étape 2

    @Test("Erase everything on this phone : compte, comptes fermés, indices, visite et historique effacés ; retour à A1")
    func eraseEverything() throws {
        var wallet = namedWallet
        wallet.disconnectedAccounts = [SavedAccount(address: "CBBBB", cards: [], firstName: "Léo")]
        let activity = InMemoryActivityStore()
        try activity.update(account) { $0.records = [ActivityRecord(id: "stellar:a", event: .transfer, hash: "a", from: account, to: "G", assetCode: "XLM", amount: 1, at: .now, isLocal: true)] }
        let store = InMemoryLocalWalletStore(wallet)
        let session = AppSession(store: store, config: .testnet, activity: activity)
        let model = SettingsModel(session: session, walletCards: [])
        model.eraseEverything()
        #expect(model.saveError == nil)
        #expect(store.wallet == LocalWallet())
        #expect(session.wallet == LocalWallet())
        #expect(activity.log == ActivityLog())
        #expect(session.showsOnboarding)
        #expect(!session.wallet.tourSeen, "La visite sera reproposée")
    }

    @Test("Erase everything : refusé pendant un paiement en attente, rien n'est effacé")
    func eraseRefusedWhilePending() throws {
        var wallet = namedWallet
        let trace = PaymentTrace(token: "T", from: account, destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121)
        wallet.pendingSend = PendingSend(trace: trace, recipient: "G", recipientName: nil, drawerTitle: "Main account", asset: "XLM", amount: 1, signedAt: .now)
        let activity = InMemoryActivityStore()
        try activity.update(account) { $0.records = [ActivityRecord(id: "stellar:a", event: .transfer, hash: "a", from: account, to: "G", assetCode: "XLM", amount: 1, at: .now, isLocal: true)] }
        let store = InMemoryLocalWalletStore(wallet)
        let session = AppSession(store: store, config: .testnet, activity: activity)
        let model = SettingsModel(session: session, walletCards: [])
        model.eraseEverything()
        #expect(model.saveError != nil)
        #expect(store.wallet == wallet)
        #expect(activity.log.accounts[account]?.records.count == 1)
        #expect(!session.showsOnboarding)
    }

    @Test("Fichiers du téléphone : l'effacement retire aussi les copies mises de côté (.unreadable)")
    func fileErase() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let walletStore = try FileLocalWalletStore(network: .testnet, directory: directory)
        let activityStore = try FileActivityStore(network: .testnet, directory: directory)
        try walletStore.save(namedWallet)
        try activityStore.save(ActivityLog())
        for url in [walletStore.fileURL, activityStore.fileURL] {
            try Data("x".utf8).write(to: url.appendingPathExtension("unreadable"))
        }
        try walletStore.erase()
        try activityStore.erase()
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "ChimpDAO").path)
        #expect(left.isEmpty)
        try walletStore.erase()
    }

    @Test("Aide : un e-mail à chimpdao@consulting-manao.com, la version dans l'objet")
    func helpEmail() throws {
        let url = try #require(SettingsModel.helpURL)
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:chimpdao@consulting-manao.com?subject=ChimpDAO%20help"))
        #expect(url.absoluteString.contains(SettingsModel.versionText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!))
    }

    @Test("Pages web : adresses HTTPS de privacy.html et support.html, une fois remplies")
    func publicPages() {
        for (url, page) in [(PublicPages.privacy, "privacy.html"), (PublicPages.support, "support.html")] {
            guard let url else { continue }
            #expect(url.scheme == "https", "\(page) : HTTPS obligatoire")
            #expect(url.lastPathComponent == page)
        }
    }

    @Test("Version : « 1.1.0 (1) », lue dans le paquet de l'app")
    func version() {
        #expect(SettingsModel.versionText.range(of: #"^\d+\.\d+(\.\d+)? \(\d+\)$"#, options: .regularExpression) != nil)
    }

    @Test("Licences : le texte de chaque composant tiers est dans l'app")
    func licenses() {
        for item in ThirdPartyLicense.all {
            #expect(item.text()?.isEmpty == false, "\(item.file).txt manque")
        }
        #expect(ThirdPartyLicense.all.first { $0.name == "stellar-ios-mac-sdk" }?.text()?.contains("Apache License") == true)
    }
}

/// « Network » (I2) : affichage seulement, le réseau vient de la configuration de build (session « Réglages », point 5).
struct NetworkRowTests {
    @Test("Debug et Testing : Testnet choisi, Mainnet grisé « Coming soon »")
    func developerBuild() {
        let row = SettingsModel.networkRow(current: .testnet, isDeveloperBuild: true)
        #expect(row.options == [.testnet, .mainnet])
        #expect(row.current == .testnet)
        #expect(row.comingSoon == [.mainnet])
    }

    @Test("Release : seulement le réseau réellement utilisé, sans autre option ni « Coming soon »")
    func releaseBuild() {
        let testnet = SettingsModel.networkRow(current: .testnet, isDeveloperBuild: false)
        #expect(testnet.options == [.testnet] && testnet.comingSoon.isEmpty)
        let mainnet = SettingsModel.networkRow(current: .mainnet, isDeveloperBuild: false)
        #expect(mainnet.options == [.mainnet] && mainnet.comingSoon.isEmpty)
    }

    @Test("La ligne des réglages suit le réseau de la session ; Debug et Testing montrent l'autre réseau, verrouillé")
    func rowFollowsSession() {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let model = SettingsModel(session: session, walletCards: [])
        #if DESIGN_CATALOG
        #expect(SettingsModel.isDeveloperBuild)
        #else
        #expect(!SettingsModel.isDeveloperBuild, "Release (schéma « Chimp Release Tests ») : pas de build de développement")
        #endif
        #expect(model.networkRow == SettingsModel.networkRow(current: .testnet, isDeveloperBuild: SettingsModel.isDeveloperBuild))
        #expect(StellarNetwork.testnet.shortName == "Testnet" && StellarNetwork.mainnet.shortName == "Mainnet")
    }
}
