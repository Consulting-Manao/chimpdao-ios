import Foundation

/// Soldes du Wallet tels que l'écran en a besoin (montants en dollars, pas en unités on-chain).
///
/// Données locales ou encore sans source décidée (DESIGN_NOTES §12, questions 7 et 8) :
/// `firstName` et `weeklyChange` sont facultatifs et masqués quand ils manquent.
struct WalletSnapshot: Equatable {
    /// Prénom saisi à l'onboarding, stocké sur l'appareil (source à confirmer).
    var firstName: String?
    /// Devise d'affichage (code ISO 4217, ex. « USD »).
    var currencyCode: String
    /// Main : le compte partagé par toutes les cartes.
    var main: DrawerBalance
    /// Wallets des cartes (Pockets).
    var cards: [CardBalance]
    /// Variation sur 7 jours (source à confirmer : oracles de prix, historique).
    var weeklyChange: Decimal?
    /// Heure de la lecture des soldes.
    var fetchedAt: Date

    var total: Decimal {
        cards.reduce(main.total) { $0 + $1.balance }
    }
}

/// Solde d'un tiroir : part disponible et part en épargne (Grow, facultative).
struct DrawerBalance: Equatable {
    var ready: Decimal
    var growing: Decimal?

    var total: Decimal { ready + (growing ?? 0) }
}

/// Wallet d'une carte.
struct CardBalance: Equatable, Identifiable {
    /// Numéro de la carte (`token_id` de son NFT, d'après DESIGN_NOTES §1.1).
    var id: String
    /// Nom et couleur choisis par l'utilisateur (données locales).
    var name: String
    var color: ChimpCardColor
    var balance: Decimal
}

/// Source des soldes du Wallet. Au jalon 5, une implémentation branchée sur les services de `Core/`
/// remplacera `MockWalletDataSource`, sans toucher à la vue ni au ViewModel.
protocol WalletDataSource {
    func fetchWallet() async throws -> WalletSnapshot
}

/// Données factices (noms et montants de la maquette), avec des scénarios pour tester chaque état.
final class MockWalletDataSource: WalletDataSource {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Maquette B1 : Main $1,320 dont $500 en épargne, deux cartes, variation hebdomadaire.
        case standard
        /// Même total, sans épargne.
        case withoutSavings
        /// Sans prénom ni variation hebdomadaire.
        case minimal
        /// Tout à zéro.
        case zeroBalance
        /// Aucune carte (ne devrait pas arriver : un compte a toujours une carte).
        case noCards
        /// Chargement qui ne se termine pas (pour voir le squelette).
        case loadingForever
        /// Erreur réseau dès le premier chargement.
        case networkError
        /// Premier chargement réussi, puis chaque rafraîchissement échoue.
        case staleAfterRefresh

        var id: String { rawValue }
    }

    let scenario: Scenario
    /// Délai simulé du réseau.
    var delay: Duration
    private var callCount = 0

    init(scenario: Scenario = .standard, delay: Duration = .milliseconds(800)) {
        self.scenario = scenario
        self.delay = delay
    }

    func fetchWallet() async throws -> WalletSnapshot {
        callCount += 1
        if scenario == .loadingForever {
            try await Task.sleep(for: .seconds(3600))
        }
        try await Task.sleep(for: delay)
        switch scenario {
        case .networkError:
            throw URLError(.notConnectedToInternet)
        case .staleAfterRefresh where callCount > 1:
            throw URLError(.timedOut)
        default:
            return snapshot
        }
    }

    private var snapshot: WalletSnapshot {
        let jungle = CardBalance(id: "0421", name: "Jungle", color: .jungle, balance: Decimal(string: "62.50")!)
        let banana = CardBalance(id: "0688", name: "Banana", color: .banana, balance: Decimal(string: "102.50")!)
        var snapshot = WalletSnapshot(
            firstName: "Léo",
            currencyCode: "USD",
            main: DrawerBalance(ready: 820, growing: 500),
            cards: [jungle, banana],
            weeklyChange: Decimal(string: "6.20")!,
            fetchedAt: .now
        )
        switch scenario {
        case .withoutSavings:
            snapshot.main = DrawerBalance(ready: 1320)
        case .minimal:
            snapshot.firstName = nil
            snapshot.weeklyChange = nil
        case .zeroBalance:
            snapshot.main = DrawerBalance(ready: 0)
            snapshot.cards = snapshot.cards.map { card in
                var card = card
                card.balance = 0
                return card
            }
            snapshot.weeklyChange = nil
        case .noCards:
            snapshot.cards = []
        default:
            break
        }
        return snapshot
    }
}
