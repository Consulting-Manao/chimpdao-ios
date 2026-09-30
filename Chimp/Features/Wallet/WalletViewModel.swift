import Foundation
import Observation

/// Action proposée par une tuile du Wallet.
enum WalletAction: String, CaseIterable, Identifiable {
    case send, receive, move, swap

    var id: String { rawValue }
}

/// Contenu du Wallet prêt à afficher (textes déjà formatés).
struct WalletContent: Equatable {
    struct Card: Equatable, Identifiable {
        let id: String
        let number: String
        let name: String
        let color: ChimpCardColor
        let amount: String
    }

    var total: String
    /// Variation hebdomadaire signée (« +$6.20 »), `nil` si la donnée n'existe pas.
    var weeklyChange: String?
    var mainAmount: String
    /// Part disponible de Main, affichée seulement si une partie est en épargne.
    var mainReady: String?
    var mainGrowing: String?
    var cards: [Card]
    var isZeroBalance: Bool
    /// Un actif détenu n'a pas de prix : montants affichés par actif (« 1,000 XLM · 25 USDC »), pas en dollars.
    var isShowingAssetAmounts: Bool
    var updatedAt: Date

    /// Valeurs de remplacement pour le squelette de chargement (jamais montrées lisibles).
    static let placeholder = WalletContent(
        total: "$0,000.00",
        weeklyChange: nil,
        mainAmount: "$0,000.00",
        mainReady: nil,
        mainGrowing: nil,
        cards: [
            Card(id: "placeholder-1", number: "0000", name: "Card", color: .jungle, amount: "$00.00"),
            Card(id: "placeholder-2", number: "0000", name: "Card", color: .banana, amount: "$00.00"),
        ],
        isZeroBalance: false,
        isShowingAssetAmounts: false,
        updatedAt: .distantPast
    )
}

/// ViewModel du Wallet (B1) : charge les soldes, gère les états et formate les montants.
/// Ne fait aucun calcul crypto et ne connaît que le protocole `WalletDataSource`.
@Observable
final class WalletViewModel {
    enum Phase: Equatable {
        /// Premier chargement, rien à montrer encore.
        case loading
        /// Soldes affichés (éventuellement anciens si le dernier rafraîchissement a échoué).
        case loaded
        /// Premier chargement en échec, rien à montrer.
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var content: WalletContent?
    /// Vrai si le dernier rafraîchissement a échoué alors que des soldes plus anciens sont affichés.
    private(set) var isShowingStaleData = false
    /// Cartes du compte lues au dernier chargement réussi (clé, numéro, puce, wallet) : les réglages s'en servent.
    private(set) var cards: [CardBalance] = []
    /// Dernière lecture réussie, telle quelle : le détail d'un tiroir (B2, B3) en tire ses soldes par actif.
    private(set) var snapshot: WalletSnapshot?

    /// Actions des tuiles. Swap (E3) est masqué tant qu'il n'existe pas : aucune tuile sans destination.
    let availableActions: [WalletAction] = [.send, .receive, .move]

    private let dataSource: WalletDataSource
    private var hasLoaded = false

    /// Prénom du téléphone, indépendant du réseau (« Hey Barth » même si le premier chargement échoue).
    var firstName: String? { dataSource.firstName }

    init(dataSource: WalletDataSource) {
        self.dataSource = dataSource
    }

    /// Premier affichage : ne recharge pas si les soldes sont déjà là (retour sur l'onglet).
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    /// Relit les soldes (tirer pour rafraîchir, bouton « Try again » ou « Retry »).
    func refresh() async {
        if content == nil { phase = .loading }
        do {
            let snapshot = try await dataSource.fetchWallet()
            content = Self.format(snapshot)
            cards = snapshot.cards
            self.snapshot = snapshot
            isShowingStaleData = false
            phase = .loaded
        } catch is CancellationError {
            // Rafraîchissement interrompu (écran quitté) : on garde l'état actuel.
        } catch {
            if content != nil {
                isShowingStaleData = true
                phase = .loaded
            } else {
                phase = .failed
            }
        }
    }

    /// Une tuile est-elle utilisable ? Avec un solde nul, seul Receive a un sens.
    func isEnabled(_ action: WalletAction) -> Bool {
        guard let content, phase == .loaded else { return false }
        return action == .receive || !content.isZeroBalance
    }

    // MARK: Formatage

    /// Montants dans la devise d'affichage (`DisplayMoney`, portage exact de `netWorthIn`, coupé aux décimales de la
    /// devise). Si un actif détenu ou la devise n'a pas de prix, aucun total partiel : les tiroirs concernés et le total
    /// affichent leurs montants par actif, comme le terminal.
    static func format(_ snapshot: WalletSnapshot) -> WalletContent {
        let money = snapshot.money
        /// Dans la devise si possible, sinon par actif.
        func amount(_ assets: [AssetAmount], plus growing: Decimal? = nil) -> String {
            guard let value = money.value(assets) else { return assetText(assets) }
            guard let growing else { return money.text(value) }
            guard let saved = money.value(usd: growing) else { return assetText(assets) }
            return money.text(value + saved)
        }

        let main = snapshot.main
        let growing = main.growing ?? 0
        let hasSavings = growing > 0
        let total = money.value(snapshot.allAssets)
        let growingValue = hasSavings ? money.value(usd: growing) : 0
        let isZero = snapshot.allAssets.allSatisfy { $0.amount == 0 } && growing == 0
        let totalText: String
        if let total, let growingValue {
            totalText = money.text(total + growingValue)
        } else {
            totalText = assetText(snapshot.allAssets)
        }
        return WalletContent(
            total: totalText,
            weeklyChange: total == nil ? nil : snapshot.weeklyChange.flatMap(money.value(usd:)).map { money.text($0, style: .signed) },
            mainAmount: amount(main.assets, plus: hasSavings ? growing : nil),
            mainReady: hasSavings ? (money.value(main.assets).map { money.text($0, style: .upToDigits) } ?? assetText(main.assets)) : nil,
            mainGrowing: hasSavings ? growingValue.map { money.text($0, style: .upToDigits) } : nil,
            cards: snapshot.cards.map { card in
                WalletContent.Card(id: card.id, number: card.number, name: card.name, color: card.color, amount: amount(card.assets))
            },
            isZeroBalance: isZero,
            isShowingAssetAmounts: total == nil || growingValue == nil,
            updatedAt: snapshot.fetchedAt
        )
    }

    /// « 1,000 XLM · 25 USDC » : actifs non nuls, additionnés par code, dans l'ordre d'apparition ; « 0 » si tout est nul.
    static func assetText(_ assets: [AssetAmount]) -> String {
        var codes: [String] = []
        var sums: [String: Decimal] = [:]
        for asset in assets {
            if sums[asset.code] == nil { codes.append(asset.code) }
            sums[asset.code, default: 0] += asset.amount
        }
        let parts = codes.compactMap { code -> String? in
            guard let sum = sums[code], sum != 0 else { return nil }
            return "\(sum.formatted(.number.precision(.fractionLength(0...2)))) \(code)"
        }
        return parts.isEmpty ? 0.formatted() : parts.joined(separator: " · ")
    }
}
