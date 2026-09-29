import Foundation

/// Montant d'un actif, en unités de l'actif (« 25 » USDC), jamais en unités on-chain.
struct AssetAmount: Equatable {
    var code: String
    var amount: Decimal
}

/// Soldes du Wallet : montants par actif de chaque tiroir, et prix en dollars lus au même moment.
///
/// Donnée encore sans source décidée (DESIGN_NOTES §12, question 8) : `weeklyChange`, facultatif et masqué s'il manque.
/// Le prénom n'en fait pas partie : il vient du téléphone (`WalletDataSource.firstName`), même si la lecture échoue.
struct WalletSnapshot: Equatable {
    /// Devise d'affichage (code ISO 4217, ex. « USD »).
    var currencyCode: String
    /// Main : le compte partagé par toutes les cartes.
    var main: DrawerBalance
    /// Wallets des cartes (Pockets).
    var cards: [CardBalance]
    /// Variation sur 7 jours (source à confirmer : oracles de prix, historique).
    var weeklyChange: Decimal?
    /// Prix en dollars par code d'actif (USDC = 1). Un actif détenu **sans prix** : pas de total en dollars, l'écran
    /// affiche les montants par actif (comme le terminal, décision du 2026-09-29).
    var usdPrices: [String: Decimal]
    /// Heure de la lecture des soldes.
    var fetchedAt: Date

    /// Tous les avoirs, tiroirs confondus.
    var allAssets: [AssetAmount] { main.assets + cards.flatMap(\.assets) }
}

/// Solde d'un tiroir : ses actifs, plus une part en épargne (Grow, facultative, en dollars).
struct DrawerBalance: Equatable {
    var assets: [AssetAmount]
    /// Pas encore lue sur la chaîne (Grow n'est pas construit) : seulement dans les données factices.
    var growing: Decimal?
}

/// Wallet d'une carte.
struct CardBalance: Equatable, Identifiable {
    /// Clé publique de la carte (hexadécimal) : identité stable.
    var id: String
    /// Numéro de la carte (`token_id` de son NFT) sur 4 chiffres, « ···· » s'il est inconnu.
    var number: String
    /// Nom et couleur choisis par l'utilisateur (données locales).
    var name: String
    var color: ChimpCardColor
    var assets: [AssetAmount]
    /// Adresse C du wallet de la carte (sa Pocket), `nil` si elle n'en a pas (ou dans les données factices).
    var pocket: String? = nil
}

/// Source des soldes du Wallet : `ChainWalletDataSource` (testnet) dans l'app, `MockWalletDataSource` dans le catalogue.
protocol WalletDataSource {
    /// Prénom saisi à l'onboarding (A4), lu sur le téléphone : l'en-tête l'affiche même si les soldes n'arrivent pas.
    var firstName: String? { get }
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
        /// Prix du XLM illisible : montants par actif, pas de total en dollars.
        case pricesUnavailable

        var id: String { rawValue }
    }

    let scenario: Scenario
    /// Délai simulé du réseau.
    var delay: Duration
    private var callCount = 0

    var firstName: String? { scenario == .minimal ? nil : "Léo" }

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
        // Montants de la maquette B1 : Main $820 disponibles (dont $600 en XLM à $0.20) + $500 en épargne, Jungle $62.50,
        // Banana $102.50 (dont $2.50 en XLM).
        let jungle = CardBalance(id: "jungle", number: "0421", name: "Jungle", color: .jungle, assets: [usdc("62.50")])
        let banana = CardBalance(id: "banana", number: "0688", name: "Banana", color: .banana, assets: [xlm("12.50"), usdc("100")])
        var snapshot = WalletSnapshot(
            currencyCode: "USD",
            main: DrawerBalance(assets: [xlm("3000"), usdc("220")], growing: 500),
            cards: [jungle, banana],
            weeklyChange: Decimal(string: "6.20")!,
            usdPrices: ["XLM": Decimal(string: "0.2")!, "USDC": 1],
            fetchedAt: .now
        )
        switch scenario {
        case .withoutSavings:
            snapshot.main.growing = nil
            snapshot.main.assets = [xlm("3000"), usdc("720")]
        case .minimal:
            snapshot.weeklyChange = nil
        case .zeroBalance:
            snapshot.main = DrawerBalance(assets: [xlm("0"), usdc("0")])
            snapshot.cards = snapshot.cards.map { card in
                var card = card
                card.assets = [xlm("0"), usdc("0")]
                return card
            }
            snapshot.weeklyChange = nil
        case .noCards:
            snapshot.cards = []
        case .pricesUnavailable:
            snapshot.usdPrices = ["USDC": 1]
            snapshot.weeklyChange = nil
        default:
            break
        }
        return snapshot
    }

    private func xlm(_ value: String) -> AssetAmount { AssetAmount(code: "XLM", amount: Decimal(string: value)!) }
    private func usdc(_ value: String) -> AssetAmount { AssetAmount(code: "USDC", amount: Decimal(string: value)!) }
}
