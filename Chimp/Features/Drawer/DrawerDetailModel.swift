import Foundation
import Observation

/// Un tiroir du compte : Main, ou le wallet d'une carte (clé publique en hexadécimal).
enum DrawerSelection: Hashable {
    case main
    case card(String)

    /// Identifiant du tiroir dans Envoyer, Move et Recevoir (« main », ou la clé de la carte).
    var drawerID: String {
        switch self {
        case .main: "main"
        case .card(let key): key
        }
    }
}

/// Détail d'un tiroir, prêt à afficher (textes déjà formatés).
struct DrawerDetailContent: Equatable {
    struct Asset: Equatable, Identifiable {
        let code: String
        let glyph: ChimpAssetGlyph
        /// « US Dollar », « Stellar ».
        let title: String
        /// « 620 USDC », « 800 XLM ».
        let amount: String
        /// « $620.00 » ; `nil` si l'actif n'a pas de prix.
        let value: String?

        var id: String { code }
    }

    struct Signer: Equatable, Identifiable {
        let id: String
        let name: String
        let color: ChimpCardColor
    }

    /// Total du tiroir : en dollars, ou par actif si un prix manque (comme B1).
    let total: String
    /// Libellé « Ready to spend · $820 ».
    let ready: String
    /// Actifs non nuls, dans l'ordre du Wallet (XLM, USDC).
    let assets: [Asset]
    /// Cartes qui peuvent signer pour ce tiroir : toutes celles du compte pour Main, la carte seule pour son wallet.
    let signers: [Signer]
    /// Adresse du tiroir (C…), `nil` si elle n'est pas connue.
    let address: String?
    /// Rien dans ce tiroir : Send et Move n'ont pas de sens.
    let isEmpty: Bool
}

/// ViewModel du détail d'un tiroir (B2 Main account, B3 wallet d'une carte). Aucune lecture propre : il met en forme la
/// dernière lecture du Wallet (`WalletViewModel.snapshot`), et « tirer pour rafraîchir » relit le Wallet. Les noms et
/// couleurs viennent du téléphone, pour qu'un « Rename & colour » se voie tout de suite.
@Observable
final class DrawerDetailModel {
    let selection: DrawerSelection
    let wallet: WalletViewModel
    private let session: AppSession
    private let clipboard: AddressClipboard
    private let copiedDuration: Duration
    private var copiedResetTask: Task<Void, Never>?

    /// Adresse tout juste copiée : la pilule affiche « Copied! ».
    private(set) var isCopied = false

    init(
        selection: DrawerSelection,
        wallet: WalletViewModel,
        session: AppSession,
        clipboard: AddressClipboard = SystemAddressClipboard(),
        copiedDuration: Duration = ChimpMotion.Copied.display
    ) {
        self.selection = selection
        self.wallet = wallet
        self.session = session
        self.clipboard = clipboard
        self.copiedDuration = copiedDuration
    }

    // MARK: Contenu

    var isMain: Bool { selection == .main }

    /// La carte de ce wallet, telle que le Wallet l'a lue (`nil` pour Main, ou si le compte ne la liste plus).
    var card: CardBalance? {
        guard case .card(let key) = selection else { return nil }
        return wallet.snapshot?.cards.first { $0.id == key }
    }

    /// Nom de la carte : celui du téléphone (modifiable dans « Rename & colour »), sinon celui lu par le Wallet.
    var cardName: String {
        guard case .card(let key) = selection else { return "" }
        return savedCard(key)?.name ?? card?.name ?? String(localized: "Card")
    }

    var cardColor: ChimpCardColor {
        guard case .card(let key) = selection else { return .jungle }
        return savedCard(key)?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? card?.color ?? .jungle
    }

    /// Nombre de cartes du compte à la dernière lecture.
    var cardCount: Int { wallet.snapshot?.cards.count ?? 0 }

    /// Le compte ne liste plus cette carte (retirée ailleurs) : l'écran le dit au lieu d'afficher des soldes.
    var isMissing: Bool {
        guard case .card = selection, wallet.snapshot != nil else { return false }
        return card == nil
    }

    var content: DrawerDetailContent? {
        guard let snapshot = wallet.snapshot else { return nil }
        let names = session.wallet.account?.cards ?? []
        func signer(_ card: CardBalance) -> DrawerDetailContent.Signer {
            let saved = names.first { $0.publicKey == card.id }
            return DrawerDetailContent.Signer(
                id: card.id, name: saved?.name ?? card.name,
                color: saved?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? card.color
            )
        }
        switch selection {
        case .main:
            return Self.content(
                assets: snapshot.main.assets, snapshot: snapshot,
                signers: snapshot.cards.map(signer), address: session.wallet.account?.address
            )
        case .card:
            guard let card else { return nil }
            return Self.content(assets: card.assets, snapshot: snapshot, signers: [signer(card)], address: card.pocket)
        }
    }

    // MARK: Actions

    func copyAddress() {
        guard let address = content?.address else { return }
        clipboard.copy(address)
        isCopied = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [copiedDuration] in
            try? await Task.sleep(for: copiedDuration)
            guard !Task.isCancelled else { return }
            isCopied = false
        }
    }

    func refresh() async {
        await wallet.refresh()
    }

    /// De quoi ouvrir « Rename & colour » (écran des réglages) pour cette carte.
    func makeRenameModel() -> SettingsModel? {
        guard case .card(let key) = selection else { return nil }
        let settings = SettingsModel(session: session, walletCards: wallet.cards)
        guard let card = settings.cards.first(where: { $0.id == key }) else { return nil }
        settings.edit(card)
        return settings
    }

    /// De quoi retirer cette carte (G6) ou la déclarer perdue (G7) : ses montants et ceux de Main, déjà formatés.
    var removalTarget: RemovalTarget? {
        guard case .card(let key) = selection, let snapshot = wallet.snapshot, let card,
              let publicKey = try? ChipPublicKey(Data(hex: key) ?? Data()) else { return nil }
        let wallet = Self.content(assets: card.assets, snapshot: snapshot, signers: [], address: card.pocket)
        let main = Self.content(assets: snapshot.main.assets, snapshot: snapshot, signers: [], address: nil)
        return RemovalTarget(
            key: publicKey, chip: card.chip ?? .infineon2Go, name: cardName, color: cardColor, number: card.number,
            walletAmount: wallet.total, walletIsEmpty: wallet.isEmpty, mainAmount: main.total
        )
    }

    /// Clés de toutes les cartes du compte (dernière lecture), pour la chaîne factice du simulateur.
    var memberKeys: [ChipPublicKey] {
        (wallet.snapshot?.cards ?? []).compactMap { try? ChipPublicKey(Data(hex: $0.id) ?? Data()) }
    }

    private func savedCard(_ key: String) -> SavedCard? {
        session.wallet.account?.cards.first { $0.publicKey == key }
    }

    // MARK: Formatage (fonction pure, testée)

    static func content(
        assets: [AssetAmount], snapshot: WalletSnapshot, signers: [DrawerDetailContent.Signer], address: String?
    ) -> DrawerDetailContent {
        let currency = Decimal.FormatStyle.Currency(code: snapshot.currencyCode).presentation(.narrow)
        let wholeCurrency = currency.precision(.fractionLength(0...2))
        let usd = NetWorth.usd(assets.map { ($0.code, $0.amount) }, prices: snapshot.usdPrices)

        var codes: [String] = []
        var sums: [String: Decimal] = [:]
        for asset in assets {
            if sums[asset.code] == nil { codes.append(asset.code) }
            sums[asset.code, default: 0] += asset.amount
        }
        let lines: [DrawerDetailContent.Asset] = codes.compactMap { code in
            guard let amount = sums[code], amount != 0 else { return nil }
            let known = SendAsset.allCases.first { $0.code == code }
            let value = snapshot.usdPrices[code.uppercased()].map { NetWorth.truncatedToCents(amount * $0).formatted(currency) }
            return DrawerDetailContent.Asset(
                code: code,
                glyph: known?.glyph ?? .xlm,
                title: known.map(Self.assetName) ?? code,
                amount: known?.formattedWithCode(amount) ?? "\(amount) \(code)",
                value: value
            )
        }
        let readyAmount = usd?.formatted(wholeCurrency) ?? WalletViewModel.assetText(assets)
        return DrawerDetailContent(
            total: usd?.formatted(currency) ?? WalletViewModel.assetText(assets),
            ready: String(localized: "Ready to spend · \(readyAmount)"),
            assets: lines,
            signers: signers,
            address: address,
            isEmpty: lines.isEmpty
        )
    }

    /// Nom d'un actif dans le détail d'un tiroir (maquette B2 : « US Dollar », « Stellar »).
    static func assetName(_ asset: SendAsset) -> String {
        switch asset {
        case .usdc: String(localized: "US Dollar")
        case .xlm: String(localized: "Stellar")
        }
    }
}
