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
        let name: String
        let color: ChimpCardColor
        let amount: String
    }

    var firstName: String?
    var total: String
    /// Variation hebdomadaire signée (« +$6.20 »), `nil` si la donnée n'existe pas.
    var weeklyChange: String?
    var mainAmount: String
    /// Part disponible de Main, affichée seulement si une partie est en épargne.
    var mainReady: String?
    var mainGrowing: String?
    var cards: [Card]
    var isZeroBalance: Bool
    var updatedAt: Date

    /// Valeurs de remplacement pour le squelette de chargement (jamais montrées lisibles).
    static let placeholder = WalletContent(
        firstName: "Léo",
        total: "$0,000.00",
        weeklyChange: nil,
        mainAmount: "$0,000.00",
        mainReady: nil,
        mainGrowing: nil,
        cards: [
            Card(id: "placeholder-1", name: "Card", color: .jungle, amount: "$00.00"),
            Card(id: "placeholder-2", name: "Card", color: .banana, amount: "$00.00"),
        ],
        isZeroBalance: false,
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

    /// Actions des tuiles. Pour l'instant les quatre de la maquette ; Swap dépend du périmètre V1.
    let availableActions: [WalletAction] = WalletAction.allCases

    private let dataSource: WalletDataSource
    private var hasLoaded = false

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

    // MARK: Actions (écrans des lots suivants du jalon 4)
    // Les tuiles (Send, Receive, Move, Swap) sont routées par `MainTabView`.

    func openMain() {
        // TODO(jalon 4) : ouvrir Main (B2).
    }

    func openCard(id: String) {
        // TODO(jalon 4) : ouvrir le wallet de la carte (B3).
    }

    func addCard() {
        // TODO(jalon 4) : ajouter une carte (G1).
    }

    // MARK: Formatage

    private static func format(_ snapshot: WalletSnapshot) -> WalletContent {
        // Symbole court (« $ » et non « US$ » hors des États-Unis) ; séparateurs selon la région du téléphone.
        let currency = Decimal.FormatStyle.Currency(code: snapshot.currencyCode).presentation(.narrow)
        let wholeCurrency = currency.precision(.fractionLength(0...2))
        let main = snapshot.main
        let hasSavings = (main.growing ?? 0) > 0
        return WalletContent(
            firstName: snapshot.firstName,
            total: snapshot.total.formatted(currency),
            weeklyChange: snapshot.weeklyChange?.formatted(currency.sign(strategy: .always())),
            mainAmount: main.total.formatted(currency),
            mainReady: hasSavings ? main.ready.formatted(wholeCurrency) : nil,
            mainGrowing: hasSavings ? main.growing?.formatted(wholeCurrency) : nil,
            cards: snapshot.cards.map { card in
                WalletContent.Card(id: card.id, name: card.name, color: card.color, amount: card.balance.formatted(currency))
            },
            isZeroBalance: snapshot.total == 0,
            updatedAt: snapshot.fetchedAt
        )
    }
}
