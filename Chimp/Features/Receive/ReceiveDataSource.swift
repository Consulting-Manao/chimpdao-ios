import Foundation

/// Un tiroir dans lequel on peut recevoir : Main (le compte partagé) ou le wallet d'une carte (sa Pocket).
struct ReceiveDrawer: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Chimp account : n'importe quelle carte du compte peut dépenser.
        case main
        /// Pocket d'une carte : seule cette carte peut dépenser. Nom et couleur sont des données locales.
        case card(name: String, color: ChimpCardColor)
    }

    /// « main », ou l'identifiant de la carte (sa clé publique ; le numéro dans les données factices).
    let id: String
    let kind: Kind
    /// Adresse Stellar complète du contrat (`C…`, 56 caractères) : c'est elle qu'on copie, partage et met dans le QR.
    let address: String
}

/// Ce que l'écran Recevoir a besoin de savoir : le réseau et les tiroirs, Main en premier.
struct ReceiveOptions: Equatable {
    var network: StellarNetwork
    var drawers: [ReceiveDrawer]
}

/// Source des adresses de réception : `LocalReceiveDataSource` dans l'app, `MockReceiveDataSource` dans le catalogue.
protocol ReceiveDataSource {
    func fetchReceiveOptions() async throws -> ReceiveOptions
}

/// Les vraies adresses, depuis le stockage local : le Main account, puis la Pocket de chaque carte connue sur ce
/// téléphone (adresses vérifiées sur la chaîne à l'onboarding). Rien à lire sur le réseau, rien à signer.
struct LocalReceiveDataSource: ReceiveDataSource {
    let session: AppSession

    func fetchReceiveOptions() async throws -> ReceiveOptions {
        guard let account = session.wallet.account else { throw ChainWalletDataSource.ReadError.noAccount }
        let main = ReceiveDrawer(id: "main", kind: .main, address: account.address)
        let cards = account.cards.compactMap { card -> ReceiveDrawer? in
            guard let pocket = card.pocket else { return nil }
            let color = card.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle
            return ReceiveDrawer(id: card.publicKey, kind: .card(name: card.name ?? String(localized: "Card"), color: color), address: pocket)
        }
        return ReceiveOptions(network: session.network, drawers: [main] + cards)
    }
}

/// Données factices (noms de la maquette), avec des scénarios pour tester chaque état.
///
/// Les adresses sont **fausses mais au format valide** (somme de contrôle correcte), pour qu'un wallet
/// qui scanne le QR ne signale pas d'erreur de format. Elles ont été calculées hors de l'app
/// (`sha256` d'un libellé, encodé en adresse de contrat) et n'appartiennent à aucun contrat.
final class MockReceiveDataSource: ReceiveDataSource {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Maquette D1 : Main + les wallets de Jungle et Banana, testnet.
        case standard
        /// Main seul (question 11 de DESIGN_NOTES §12 : « Main seul en V1 ? »).
        case mainOnly
        /// Comme la maquette, sur mainnet : pas de badge Testnet.
        case mainnet
        /// Chargement qui ne se termine pas.
        case loadingForever
        /// Erreur réseau au chargement.
        case networkError

        var id: String { rawValue }
    }

    static let mainAddress = "CAIO2SJ6UNDZELXIPQTONOBOURBWJFNNB5DHQWRVUDVZVPZRJLAZVOX2"
    static let jungleAddress = "CANLHHGR5NAINKBE4MYL657H5XUCTPT6C2ZGNMLMK57IO6TQ4FO6UBQO"
    static let bananaAddress = "CBNLYLABIDAW2YJM6GZPJSIMABCU66BFXQCYGJPBL6VSHEEIG5JX2WHS"

    let scenario: Scenario
    /// Délai simulé du réseau.
    var delay: Duration

    init(scenario: Scenario = .standard, delay: Duration = .milliseconds(500)) {
        self.scenario = scenario
        self.delay = delay
    }

    func fetchReceiveOptions() async throws -> ReceiveOptions {
        if scenario == .loadingForever {
            try await Task.sleep(for: .seconds(3600))
        }
        try await Task.sleep(for: delay)

        let main = ReceiveDrawer(id: "main", kind: .main, address: Self.mainAddress)
        let jungle = ReceiveDrawer(id: "0421", kind: .card(name: "Jungle", color: .jungle), address: Self.jungleAddress)
        let banana = ReceiveDrawer(id: "0688", kind: .card(name: "Banana", color: .banana), address: Self.bananaAddress)

        switch scenario {
        case .networkError:
            throw URLError(.notConnectedToInternet)
        case .mainOnly:
            return ReceiveOptions(network: .testnet, drawers: [main])
        case .mainnet:
            return ReceiveOptions(network: .mainnet, drawers: [main, jungle, banana])
        case .standard, .loadingForever:
            return ReceiveOptions(network: .testnet, drawers: [main, jungle, banana])
        }
    }
}
