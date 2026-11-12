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
        /// « 620 USDC », « 800 XLM ».
        let amount: String
        /// « $620.00 » (ligne de la liste N1b, B1) ; `nil` si l'actif n'a pas de prix.
        let value: String?

        var id: String { code }
    }

    struct Signer: Equatable, Identifiable {
        let id: String
        let name: String
        let color: ChimpCardColor
        /// « 0421 ».
        var number: String = "····"
    }

    /// Total du tiroir : en dollars, ou par actif si un prix manque (comme B1).
    let total: String
    /// Actifs non nuls, dans l'ordre du Wallet (XLM, USDC).
    let assets: [Asset]
    /// Stablebonds détenus (CETES) : dans « Growing » (B1), comme le vault (décision de Barth du 2026-10-15 : construits
    /// comme « GROWING »).
    var savings: [Asset] = []
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
                color: saved?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? card.color, number: card.number
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

    /// Carte dont on peut changer le PIN : une Infineon (une DUOX n'a pas de PIN). `nil` sinon.
    var pinCard: PINCard? {
        guard case .card(let key) = selection, let card, card.chip != .duox,
              let publicKey = try? ChipPublicKey(Data(hex: key) ?? Data()) else { return nil }
        return PINCard(key: publicKey, name: cardName, color: cardColor, number: card.number)
    }

    /// Clés de toutes les cartes du compte (dernière lecture), pour la chaîne factice du simulateur.
    var memberKeys: [ChipPublicKey] {
        (wallet.snapshot?.cards ?? []).compactMap { try? ChipPublicKey(Data(hex: $0.id) ?? Data()) }
    }

    private func savedCard(_ key: String) -> SavedCard? {
        session.wallet.account?.cards.first { $0.publicKey == key }
    }

    /// Ce qui est prêt à dépenser dans ce tiroir (tout sauf les stablebonds), tel que lu par le Wallet.
    var readyAssets: [AssetAmount] { drawerAssets.filter { !Self.isSavings($0.code) } }

    /// Les stablebonds de ce tiroir (CETES), tels que lus par le Wallet.
    var savingsAssets: [AssetAmount] { drawerAssets.filter { Self.isSavings($0.code) && $0.amount != 0 } }

    private var drawerAssets: [AssetAmount] {
        guard let snapshot = wallet.snapshot else { return [] }
        return switch selection {
        case .main: snapshot.main.assets
        case .card: card?.assets ?? []
        }
    }

    /// Devise et prix de la dernière lecture du Wallet.
    var money: DisplayMoney? { wallet.snapshot?.money }

    // MARK: Formatage (fonction pure, testée)

    /// Un actif qui ne s'envoie pas (CETES) : de l'épargne, rangée dans « Growing ».
    static func isSavings(_ code: String) -> Bool {
        SendAsset.allCases.first { $0.code == code }.map { !$0.isSendable } ?? false
    }

    /// Une part de « Growing » : sa valeur dans la devise d'affichage (`nil` sans prix) et, à défaut, son texte par actif.
    struct GrowingPart: Equatable {
        let value: Decimal?
        /// « 2,000.48 XLM », « 1,820 CETES ».
        let fallback: String
    }

    /// Le panneau du total de B1 : total (prêt + qui pousse), les deux parts et la barre.
    struct Split: Equatable {
        /// « $1,320.00 ».
        let total: String
        /// Parts du panneau, sans centimes quand c'est rond (« $820 », « $62.50 »).
        let ready: String
        /// `nil` : rien ne pousse.
        let growing: String?
        /// Titres des listes N1b, avec centimes (« $820.00 ») ; par actif sans prix.
        let readyTotal: String
        let growingTotal: String?
        /// Parts de la barre ; toutes deux à 0 pour un tiroir vide.
        let readyWeight: Double
        let growingWeight: Double
    }

    /// Le total compte ce qui pousse (maquette B1 : $820 prêts + $500 qui poussent = $1,320). Sans prix pour une part,
    /// pas de total partiel : les montants par actif, comme le Wallet, et une barre à parts égales.
    static func split(ready assets: [AssetAmount], growing parts: [GrowingPart], money: DisplayMoney) -> Split {
        let readyValue = money.value(assets)
        let hasGrowing = !parts.isEmpty
        let growingValue: Decimal? = parts.contains { $0.value == nil } ? nil : parts.reduce(0) { $0 + ($1.value ?? 0) }
        let readyAssetText = WalletViewModel.assetText(assets)
        let growingFallback = parts.map(\.fallback).joined(separator: " · ")
        let hasReady = assets.contains { $0.amount != 0 }

        if let readyValue, let growingValue {
            let readyWeight = NSDecimalNumber(decimal: readyValue).doubleValue
            let growingWeight = hasGrowing ? NSDecimalNumber(decimal: growingValue).doubleValue : 0
            return Split(
                total: money.text(readyValue + growingValue),
                ready: money.text(readyValue, style: .wholeWhenRound),
                growing: hasGrowing ? money.text(growingValue, style: .wholeWhenRound) : nil,
                readyTotal: money.text(readyValue),
                growingTotal: hasGrowing ? money.text(growingValue) : nil,
                readyWeight: max(0, readyWeight),
                growingWeight: max(0, growingWeight)
            )
        }
        let readyText = readyValue.map { money.text($0, style: .wholeWhenRound) } ?? readyAssetText
        let growingText = hasGrowing ? (growingValue.map { money.text($0, style: .wholeWhenRound) } ?? growingFallback) : nil
        return Split(
            total: [readyAssetText, hasGrowing ? growingFallback : nil].compactMap { $0 }.joined(separator: " · "),
            ready: readyText,
            growing: growingText,
            readyTotal: readyValue.map { money.text($0) } ?? readyAssetText,
            growingTotal: hasGrowing ? (growingValue.map { money.text($0) } ?? growingFallback) : nil,
            readyWeight: hasReady ? 1 : 0,
            growingWeight: hasGrowing ? 1 : 0
        )
    }

    static func content(
        assets: [AssetAmount], snapshot: WalletSnapshot, signers: [DrawerDetailContent.Signer], address: String?
    ) -> DrawerDetailContent {
        let money = snapshot.money
        let total = money.value(assets)

        var codes: [String] = []
        var sums: [String: Decimal] = [:]
        for asset in assets {
            if sums[asset.code] == nil { codes.append(asset.code) }
            sums[asset.code, default: 0] += asset.amount
        }
        func line(_ code: String) -> DrawerDetailContent.Asset? {
            guard let amount = sums[code], amount != 0 else { return nil }
            let known = SendAsset.allCases.first { $0.code == code }
            let value = money.value([AssetAmount(code: code, amount: amount)]).map { money.text($0) }
            return DrawerDetailContent.Asset(
                code: code,
                amount: known?.displayedWithCode(amount) ?? "\(SendAsset.displayed(amount, code: code)) \(code)",
                value: value
            )
        }
        // Un actif qui ne s'envoie pas (CETES) n'est pas « prêt à dépenser » : il va dans « Growing ».
        let isSavings = Self.isSavings
        let lines = codes.filter { !isSavings($0) }.compactMap(line)
        let savings = codes.filter(isSavings).compactMap(line)
        return DrawerDetailContent(
            total: total.map { money.text($0) } ?? WalletViewModel.assetText(assets),
            assets: lines,
            savings: savings,
            signers: signers,
            address: address,
            isEmpty: lines.isEmpty && savings.isEmpty
        )
    }
}
