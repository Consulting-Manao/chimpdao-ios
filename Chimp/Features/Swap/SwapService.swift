import Foundation

/// Ce que le parcours Swap a besoin de connaître avant de commencer : les tiroirs et leurs soldes (comme Envoyer).
struct SwapContext: Equatable {
    var network: StellarNetwork
    /// Main d'abord, puis les wallets des cartes.
    var drawers: [SendDrawer]
}

/// Conversions entre les montants affichés (`Decimal`, unité de l'actif) et les unités on-chain (7 décimales, `i128`).
enum SwapUnits {
    /// Montant tapé → unités. Refuse un montant nul, négatif ou trop précis (jamais tronqué : règle 8).
    static func units(of amount: Decimal, asset: SendAsset) throws -> Int128 {
        Int128(try SACClient.units(of: amount, keypadDecimals: asset.maxFractionDigits))
    }

    /// Unités → montant exact (7 décimales).
    static func amount(fromUnits units: Int128) -> Decimal {
        SACClient.amount(fromUnits: Decimal(string: String(units)) ?? 0)
    }
}

/// Un devis tel que l'écran Swap l'affiche : **des quantités seulement**, jamais de dollars tirés d'un pool (décision du
/// 2026-10-14). Affichage seulement : la préparation redemande un devis juste avant de signer.
struct SwapQuoteSummary: Equatable {
    let protocolID: String
    /// « Soroswap ».
    let protocolName: String
    let given: SendAsset
    let received: SendAsset
    /// Montant donné, exact.
    let amountIn: Decimal
    /// Quantité attendue, en unités on-chain (exacte) : la base du minimum signé.
    let expectedOutUnits: Int128
    /// Route, actifs dans l'ordre (« XLM → USDC »), et contrats de ces actifs.
    let route: [SendAsset]
    let routeContracts: [String]
    /// Écart au prix des réserves, frais du pool compris.
    let priceImpactBasisPoints: Int?

    var expectedOut: Decimal { SwapUnits.amount(fromUnits: expectedOutUnits) }

    /// Au-delà de 5 % d'impact : avertissement fort (principe 5).
    var needsPriceImpactWarning: Bool {
        priceImpactBasisPoints.map(Slippage.needsPriceImpactWarning) ?? false
    }
}

/// Ce qui sera signé, figé au passage à la vérification. Affiché tel quel, sans rien recalculer.
struct SwapDraft: Equatable {
    let drawer: SendDrawer
    let quote: SwapQuoteSummary
    /// Tolérance choisie (0,5 % par défaut, 3 % au plus).
    let slippageBasisPoints: Int
    let network: StellarNetwork

    var given: SendAsset { quote.given }
    var received: SendAsset { quote.received }
    var amount: Decimal { quote.amountIn }

    /// Minimum reçu signé, en unités : le devis vu moins la tolérance (`withSlippage`). Jamais redérivé ensuite.
    var minimumOutUnits: Int128 {
        Slippage.minimum(of: quote.expectedOutUnits, basisPoints: slippageBasisPoints)
    }

    var minimumOut: Decimal { SwapUnits.amount(fromUnits: minimumOutUnits) }
}

/// Swap préparé **avant** la session NFC (règle 9) : devis redemandé, bornes vérifiées, autorisation à signer.
struct PreparedSwap: Equatable {
    let draft: SwapDraft
    /// Ce que la carte signera (vrai service) ; `nil` dans le service factice.
    let integration: PreparedIntegrationCall?
    /// Le contrat qui reçoit ce qui part (paire Soroswap) : destination de la trace de « Check again ».
    let firstHopVenue: String
    /// Le contrat appelé (router), affiché dans les détails.
    let contract: String

    init(draft: SwapDraft, integration: PreparedIntegrationCall? = nil, firstHopVenue: String = "", contract: String = "") {
        self.draft = draft
        self.integration = integration
        self.firstHopVenue = firstHopVenue
        self.contract = contract
    }

    static func == (lhs: PreparedSwap, rhs: PreparedSwap) -> Bool {
        lhs.draft == rhs.draft && lhs.integration?.digest == rhs.integration?.digest
    }
}

/// Swap signé par la carte, prêt à partir.
struct SignedSwap: Equatable {
    let prepared: PreparedSwap
    /// Nom local de la carte qui a signé.
    let cardName: String
    /// Carte et signature (vrai service) ; `nil` dans le service factice.
    let card: CardSignatures?

    init(prepared: PreparedSwap, cardName: String, card: CardSignatures? = nil) {
        self.prepared = prepared
        self.cardName = cardName
        self.card = card
    }
}

/// Premier tap de l'ordre « tap puis PIN » : la carte lue, et sa signature si elle n'a pas de PIN.
struct SwapCardRead: Equatable {
    let check: CardCheck
    let signed: SignedSwap?
}

/// Ce qui a été signé, tel qu'on le réaffiche après coup (envoi, succès, issue incertaine), y compris depuis un swap en
/// attente gardé sur le téléphone.
struct SwapSummary: Equatable {
    let drawerTitle: String
    let fromAddress: String
    let given: SendAsset
    let amountIn: Decimal
    let received: SendAsset
    let expectedOut: Decimal
    let minimumOut: Decimal
    let protocolName: String
    let network: StellarNetwork

    init(_ draft: SwapDraft) {
        drawerTitle = draft.drawer.title
        fromAddress = draft.drawer.address
        given = draft.given
        amountIn = draft.amount
        received = draft.received
        expectedOut = draft.quote.expectedOut
        minimumOut = draft.minimumOut
        protocolName = draft.quote.protocolName
        network = draft.network
    }

    /// Depuis un swap en attente (`PendingSend.swap`) ; `nil` si ce n'est pas un swap.
    init?(_ pending: PendingSend, network: StellarNetwork) {
        guard let swap = pending.swap else { return nil }
        drawerTitle = pending.drawerTitle
        fromAddress = pending.trace.from
        given = SendAsset(rawValue: pending.asset) ?? .xlm
        amountIn = pending.amount
        received = SendAsset(rawValue: swap.receivedAsset) ?? .usdc
        expectedOut = swap.expectedReceived
        minimumOut = swap.minimumReceived
        protocolName = swap.protocolName
        self.network = network
    }
}

/// Swap confirmé sur la chaîne.
struct SwapReceipt: Equatable {
    let summary: SwapSummary
    let transactionHash: String
    let sentAt: Date
    let explorerURL: URL?
    /// Quantité réellement reçue (valeur rendue par le router), `nil` si elle n'a pas pu être lue.
    let receivedAmount: Decimal?
}

/// Ce qu'un écran peut dire d'un swap impossible **avant** toute signature.
enum SwapServiceError: Error, Equatable, LocalizedError {
    /// Aucun protocole n'a répondu (réseau, RPC, contrat en panne).
    case protocolUnavailable([String])
    case noAccount
    case unknownDrawer(String)

    var errorDescription: String? {
        switch self {
        case .protocolUnavailable(let names): "No answer from \(names.joined(separator: ", "))."
        case .noAccount: "No account is open on this phone."
        case .unknownDrawer(let id): "Unknown drawer \(id)."
        }
    }
}

/// Service de swap. `ChainSwapService` (testnet, `Core/`) dans l'app, `MockSwapService` dans le catalogue et les tests.
/// Mêmes étapes et mêmes garanties qu'Envoyer (`SendService`).
protocol SwapService {
    func fetchContext() async throws -> SwapContext
    /// Devis affiché (lecture seule, rien n'est signé). `SwapError.noRoute` s'il n'y a aucune route,
    /// `SwapServiceError.protocolUnavailable` si aucun protocole n'a répondu.
    func quote(given: SendAsset, received: SendAsset, amount: Decimal) async throws -> SwapQuoteSummary
    /// Avant la session NFC : solde relu, devis redemandé (`SwapError.slippageExceeded` s'il est passé sous le minimum
    /// affiché), appel construit, bornes vérifiées, autorisation préparée. Rien n'est signé.
    func prepare(_ draft: SwapDraft) async throws -> PreparedSwap
    /// Juste avant le tap qui signe : refait la préparation si l'autorisation n'a plus 20 ledgers devant elle.
    func refreshedIfNeeded(_ prepared: PreparedSwap) async throws -> PreparedSwap
    func readCard(for prepared: PreparedSwap) async throws -> SwapCardRead
    func sign(_ prepared: PreparedSwap, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSwap
    func knownCard(_ key: ChipPublicKey) -> KnownCard?
    /// Après le tap. Toute erreur est un `PaymentFailure` : l'issue se vérifie avec `check`.
    func submit(_ signed: SignedSwap, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SwapReceipt
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck
    /// Opération signée à l'issue incertaine gardée sur le téléphone (un envoi ou un swap : un seul emplacement, pour
    /// qu'aucune nouvelle signature ne parte tant qu'une issue est inconnue).
    var pendingSend: PendingSend? { get }
    func setPendingSend(_ pending: PendingSend?) throws
    func explorerURL(transactionHash: String) -> URL?
}
