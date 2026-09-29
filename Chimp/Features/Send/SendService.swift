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
    /// Un PIN peut être demandé pour signer depuis ce tiroir. Wallet d'une carte : cette carte a un PIN actif
    /// (Infineon ; une DUOX n'en a jamais). Main : au moins une carte du compte en a un ; le PIN ne sert
    /// que si la carte tapée en a un. Connu localement depuis la dernière lecture des cartes.
    var usesPin: Bool

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
    var network: StellarNetwork
    /// Main d'abord, puis les wallets des cartes.
    var drawers: [SendDrawer]
    var recents: [SendContact]
    /// Prix en dollars des actifs à prix variable (XLM), pour l'équivalent « ≈ $ ». Source à confirmer
    /// (DESIGN_NOTES §12, question 8) : absent = pas d'équivalent affiché.
    var usdPrices: [SendAsset: Decimal]
}

/// Ce qui sera signé, figé au passage à la vérification (C4). Affiché tel quel, sans rien recalculer.
struct SendDraft: Equatable {
    let recipient: StellarRecipient
    /// Nom du destinataire s'il vient des récents.
    let recipientName: String?
    let drawer: SendDrawer
    let asset: SendAsset
    /// Montant exact, indépendant de la langue du téléphone.
    let amount: Decimal
    let network: StellarNetwork
}

/// Envoi préparé **avant** la session NFC (règle 9). Au jalon 5 : dernier ledger, puis auth entry déclarée
/// (ordre 1, wallet d'une carte) ou transaction simulée (ordre 2, Main). Ici, seulement le brouillon.
struct PreparedSend: Equatable {
    let draft: SendDraft
}

/// Ce qu'apprend une première lecture de la carte, sans signer (ordre « tap puis PIN ») : quelle carte,
/// et si elle a un PIN. Au jalon 5 : SELECT (octet « PIN actif ») + GET KEY INFO, comparée à la clé attendue.
struct CardCheck: Equatable {
    /// Nom et couleur locaux de la carte tapée.
    let cardName: String
    let cardColor: ChimpCardColor
    let usesPin: Bool
}

/// Envoi signé par la carte, prêt à partir (frais par le Worker, soumission : étape C).
struct SignedSend: Equatable {
    let prepared: PreparedSend
}

/// Service d'envoi. Au jalon 5, une implémentation branchée sur `Core/` (soldes SAC, contacts locaux,
/// construction, signature par la carte, frais par le Worker, soumission) remplacera `MockSendService`,
/// sans toucher aux vues ni au ViewModel.
protocol SendService {
    /// Soldes, tiroirs et destinataires récents.
    func fetchContext() async throws -> SendContext
    /// Appels réseau à faire avant la session NFC (limite Apple de 60 s, règle 9).
    func prepare(_ draft: SendDraft) async throws -> PreparedSend
    /// Session NFC de lecture seule (ordre « tap puis PIN ») : quelle carte, avec ou sans PIN.
    func readCard(for prepared: PreparedSend) async throws -> CardCheck
    /// Session NFC de signature : vérifier la carte, puis VERIFY PIN si `pin` est fourni, puis SIGN.
    /// Le PIN n'est jamais gardé par le service.
    func sign(_ prepared: PreparedSend, pin: String?) async throws -> SignedSend
}

/// Données et signature factices (noms de la maquette), avec des scénarios pour tester chaque état.
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

    /// Puces des cartes du compte factice.
    enum CardSetup: String, CaseIterable, Identifiable {
        /// Deux Infineon avec PIN.
        case allWithPin
        /// Deux DUOX : jamais de PIN.
        case noPin
        /// Jungle = Infineon avec PIN, Banana = DUOX sans PIN. Depuis Main, c'est Jungle qui est tapée.
        case mixed

        var id: String { rawValue }
    }

    static let mayaAddress = "GCQF355RQFN77CHM5DHEGK75FWVF26PUES6J6EMQ4U7BAD3E7ORDGXPO"
    static let tomAddress = "GBTWPJNLC3BYIDPCXYYO5F4G5C245OMGXFHQPLHAATQXHL37DY7ZFNMB"
    /// Compte d'un exchange fictif, et la même adresse avec le memo ID 1234567890 plié dedans (SEP-23).
    static let exchangeAddress = "GB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL452DN"
    static let exchangeMuxedAddress = "MB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL44AAAAAAETFQC2J5EQ"

    let dataScenario: DataScenario
    let cardSetup: CardSetup
    /// Délai simulé du réseau.
    var delay: Duration
    /// Délai simulé d'une session NFC (le temps de poser la carte et de la lire).
    var nfcDelay: Duration

    /// Nombre d'appels, pour vérifier dans les tests qu'un envoi n'est jamais préparé ou signé deux fois.
    private(set) var prepareCount = 0
    private(set) var readCount = 0
    private(set) var signCount = 0
    /// PIN reçu par la dernière signature (tests uniquement : le vrai service ne le garde jamais).
    private(set) var lastPin: String?

    init(
        dataScenario: DataScenario = .standard,
        cardSetup: CardSetup = .allWithPin,
        delay: Duration = .milliseconds(600),
        nfcDelay: Duration = .milliseconds(1500)
    ) {
        self.dataScenario = dataScenario
        self.cardSetup = cardSetup
        self.delay = delay
        self.nfcDelay = nfcDelay
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

    func prepare(_ draft: SendDraft) async throws -> PreparedSend {
        prepareCount += 1
        try await Task.sleep(for: delay)
        return PreparedSend(draft: draft)
    }

    func readCard(for prepared: PreparedSend) async throws -> CardCheck {
        readCount += 1
        try await Task.sleep(for: nfcDelay)
        return tappedCard(for: prepared.draft.drawer)
    }

    func sign(_ prepared: PreparedSend, pin: String?) async throws -> SignedSend {
        signCount += 1
        lastPin = pin
        try await Task.sleep(for: nfcDelay)
        return SignedSend(prepared: prepared)
    }

    /// Carte posée sur le téléphone : celle du tiroir, ou Jungle pour un envoi depuis Main.
    private func tappedCard(for drawer: SendDrawer) -> CardCheck {
        switch drawer.kind {
        case let .card(name, color):
            CardCheck(cardName: name, cardColor: color, usesPin: drawer.usesPin)
        case .main:
            CardCheck(cardName: "Jungle", cardColor: .jungle, usesPin: cardSetup != .noPin)
        }
    }

    /// Mêmes totaux en dollars que le Wallet factice (XLM à 0,25 $) : Main 820 $, Jungle 62,50 $, Banana 102,50 $.
    private var context: SendContext {
        let jungleUsesPin = cardSetup != .noPin
        let bananaUsesPin = cardSetup == .allWithPin
        var main = SendDrawer(
            id: "main", kind: .main, address: MockReceiveDataSource.mainAddress,
            balances: [.usdc: 720, .xlm: 400], usesPin: jungleUsesPin || bananaUsesPin
        )
        var jungle = SendDrawer(
            id: "0421", kind: .card(name: "Jungle", color: .jungle), address: MockReceiveDataSource.jungleAddress,
            balances: [.usdc: Decimal(string: "62.5")!], usesPin: jungleUsesPin
        )
        var banana = SendDrawer(
            id: "0688", kind: .card(name: "Banana", color: .banana), address: MockReceiveDataSource.bananaAddress,
            balances: [.usdc: Decimal(string: "72.5")!, .xlm: 120], usesPin: bananaUsesPin
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
        return SendContext(network: .testnet, drawers: drawers, recents: recents, usdPrices: [.xlm: Decimal(string: "0.25")!])
    }
}
