import Foundation

/// Un tiroir d'où l'argent peut partir : Main (le compte partagé) ou le wallet d'une carte (sa Pocket).
struct SendDrawer: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Chimp account : n'importe quelle carte du compte peut signer (ARCHITECTURE §3.7, ordre 2).
        case main
        /// Pocket d'une carte : seule cette carte peut signer (ordre 1). Nom et couleur sont des données locales.
        case card(name: String, color: ChimpCardColor)
    }

    /// « main », ou le numéro de la carte (`token_id` de son NFT, d'après DESIGN_NOTES §1.1).
    let id: String
    let kind: Kind
    /// Adresse du contrat (`C…`) : sert à refuser un envoi vers soi-même (il faut passer par Move).
    let address: String
    /// Solde disponible par actif (hors épargne Grow), dans l'unité de l'actif.
    var balances: [SendAsset: Decimal]

    func balance(of asset: SendAsset) -> Decimal {
        balances[asset] ?? 0
    }

    /// Nom affiché (glossaire, DESIGN_NOTES §1.2) : « Main account », « Jungle's wallet ».
    var title: String {
        switch kind {
        case .main: String(localized: "Main account")
        case .card(let name, _): String(localized: "\(name)'s wallet")
        }
    }

    var icon: ChimpDrawerIcon {
        switch kind {
        case .main: .main
        case .card(_, let color): .card(color)
        }
    }
}

/// Destinataire déjà payé depuis ce téléphone (C1 « Recent »). Donnée locale, jamais on-chain.
struct SendContact: Equatable, Identifiable {
    let id: String
    let name: String
    let color: ChimpCardColor
    /// Adresse complète payée la dernière fois (G, M ou C).
    let address: String
}

/// Ce que le parcours Envoyer a besoin de connaître avant de commencer.
struct SendContext: Equatable {
    /// Main d'abord, puis les wallets des cartes.
    var drawers: [SendDrawer]
    var recents: [SendContact]
    /// Prix en dollars des actifs à prix variable (XLM), pour l'équivalent « ≈ $ ». Source à confirmer
    /// (DESIGN_NOTES §12, question 8) : absent = pas d'équivalent affiché.
    var usdPrices: [SendAsset: Decimal]
}

/// Service d'envoi. Au jalon 5, une implémentation branchée sur `Core/` (soldes SAC, contacts locaux,
/// construction, signature par la carte, frais par le Worker, soumission) remplacera `MockSendService`,
/// sans toucher aux vues ni au ViewModel.
///
/// Étape A : lecture du contexte. Les étapes B et C ajoutent la préparation, la signature et l'envoi.
protocol SendService {
    func fetchContext() async throws -> SendContext
}

/// Données factices (noms de la maquette), avec des scénarios pour tester chaque état.
///
/// Les adresses sont **fausses mais au format valide** (somme de contrôle correcte), calculées hors de l'app
/// (`sha256` d'un libellé, encodé en adresse Stellar) : elles n'appartiennent à personne.
/// Les adresses des tiroirs sont celles de `MockReceiveDataSource`.
final class MockSendService: SendService {
    enum DataScenario: String, CaseIterable, Identifiable {
        /// Maquette : Main + Jungle + Banana, trois destinataires récents.
        case standard
        /// Tous les soldes à zéro.
        case emptyBalances
        /// Main seul, sans carte à choisir.
        case mainOnly
        /// Aucun destinataire récent.
        case noRecents
        /// Chargement qui ne se termine pas.
        case loadingForever
        /// Erreur réseau au chargement des soldes.
        case networkError

        var id: String { rawValue }
    }

    static let mayaAddress = "GCQF355RQFN77CHM5DHEGK75FWVF26PUES6J6EMQ4U7BAD3E7ORDGXPO"
    static let tomAddress = "GBTWPJNLC3BYIDPCXYYO5F4G5C245OMGXFHQPLHAATQXHL37DY7ZFNMB"
    /// Compte d'un exchange fictif, et la même adresse avec le memo ID 1234567890 plié dedans (SEP-23).
    static let exchangeAddress = "GB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL452DN"
    static let exchangeMuxedAddress = "MB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL44AAAAAAETFQC2J5EQ"

    let dataScenario: DataScenario
    /// Délai simulé du réseau.
    var delay: Duration

    init(dataScenario: DataScenario = .standard, delay: Duration = .milliseconds(600)) {
        self.dataScenario = dataScenario
        self.delay = delay
    }

    func fetchContext() async throws -> SendContext {
        if dataScenario == .loadingForever {
            try await Task.sleep(for: .seconds(3600))
        }
        try await Task.sleep(for: delay)
        if dataScenario == .networkError {
            throw URLError(.notConnectedToInternet)
        }
        return context
    }

    /// Mêmes totaux en dollars que le Wallet factice (XLM à 0,25 $) : Main 820 $, Jungle 62,50 $, Banana 102,50 $.
    private var context: SendContext {
        var main = SendDrawer(
            id: "main", kind: .main, address: MockReceiveDataSource.mainAddress,
            balances: [.usdc: 720, .xlm: 400]
        )
        var jungle = SendDrawer(
            id: "0421", kind: .card(name: "Jungle", color: .jungle), address: MockReceiveDataSource.jungleAddress,
            balances: [.usdc: Decimal(string: "62.5")!]
        )
        var banana = SendDrawer(
            id: "0688", kind: .card(name: "Banana", color: .banana), address: MockReceiveDataSource.bananaAddress,
            balances: [.usdc: Decimal(string: "72.5")!, .xlm: 120]
        )
        var recents = [
            SendContact(id: "maya", name: "Maya", color: .pink, address: Self.mayaAddress),
            SendContact(id: "tom", name: "Tom", color: .jungle, address: Self.tomAddress),
            SendContact(id: "exchange", name: "Coconut Exchange", color: .leaf, address: Self.exchangeMuxedAddress),
        ]
        switch dataScenario {
        case .emptyBalances:
            main.balances = [:]
            jungle.balances = [:]
            banana.balances = [:]
        case .noRecents:
            recents = []
        default:
            break
        }
        let drawers = dataScenario == .mainOnly ? [main] : [main, jungle, banana]
        return SendContext(drawers: drawers, recents: recents, usdPrices: [.xlm: Decimal(string: "0.25")!])
    }
}
