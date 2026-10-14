import Foundation

/// Un actif tel que les intégrations le manipulent : son code affiché et l'adresse de son contrat (SAC, ou jeton de parts).
struct IntegrationAsset: Equatable, Hashable, Sendable {
    let code: String
    let contract: String
}

// MARK: Échange (D2)

/// Une demande de devis : `amountIn` unités on-chain de `assetIn` contre `assetOut`.
struct SwapRequest: Equatable, Sendable {
    let assetIn: IntegrationAsset
    let assetOut: IntegrationAsset
    let amountIn: Int128
}

/// Un devis lu sur les contrats d'un protocole (simulation, rien n'est signé). **Affichage seulement** : l'exécution
/// redemande un devis juste avant de signer et signe son propre minimum (`ActionQuote` du terminal : « Display-only.
/// Execution always re-quotes and enforces its own slippage bounds »). Uniquement des quantités, jamais de dollars.
struct SwapQuote: Equatable, Sendable {
    let protocolID: String
    let request: SwapRequest
    /// Route complète, contrats des actifs (premier = donné, dernier = reçu).
    let route: [String]
    /// Quantité reçue attendue, unités on-chain.
    let amountOut: Int128
    /// Écart au prix des réserves (`Slippage.priceImpactBasisPoints`), si le protocole le connaît.
    let priceImpactBasisPoints: Int?
    /// Le contrat qui reçoit la prise du premier saut (paire Soroswap, pool Aquarius) : la forme d'autorisation en dépend.
    let firstHopVenue: String
}

/// Un protocole d'échange (Soroswap, Aquarius). Chaque adaptateur fournit le devis, l'appel, sa forme d'autorisation et
/// le décodage de ses bornes ; le Core vérifie que la simulation correspond exactement, et seule la carte signe.
protocol SwapAdapter {
    var id: String { get }
    var name: String { get }
    /// Devis pour `request`, `nil` s'il n'existe aucune route chez ce protocole. Les pannes réseau remontent.
    func quote(_ request: SwapRequest) async throws -> SwapQuote?
    /// L'appel qui exécute `quote` au nom de `authorizer` (qui reçoit aussi le résultat), au minimum signé `minimumOut`.
    func swapCall(for quote: SwapQuote, minimumOut: Int128, authorizer: String, now: UInt64) throws -> ContractCall
    /// Ce que cet appel fait signer.
    func authShape(for quote: SwapQuote) -> any AuthShape
    /// Les bornes que porte un appel de ce protocole (ce que l'écran de vérification affiche).
    func terms(of call: ContractCall) throws -> SignedTerms
}

// MARK: Rendement (D1)

/// Une entrée de menu : `StrategyAction` du terminal (`registry/protocols.ts`).
struct YieldAction: Equatable, Sendable {
    /// D'où vient le « Max » de l'étape montant.
    enum MaxSource: Equatable, Sendable {
        /// Les fonds disponibles du tiroir (par défaut).
        case balance
        /// La position elle-même.
        case position
        /// Pas de « Max ».
        case none
    }

    let id: String
    let label: String
    let maxFrom: MaxSource
}

/// Un lieu où un protocole peut tenir une position (`StrategyVenue`) : un vault DeFindex, un pool Aquarius.
struct YieldVenue: Equatable, Sendable {
    /// Adresse du contrat (vault, pool).
    let id: String
    /// Nom affiché, choisi dans `Config/` (jamais lu sur la chaîne).
    let name: String
    let asset: IntegrationAsset
    /// Protocoles sous-jacents à afficher avec le risque (principe 6 : un vault DeFindex XLM passe par Blend).
    let underlyingProtocols: [String]
}

/// Une position lue sur la chaîne (`StrategyPosition`), typée au lieu du sac de chaînes du terminal.
struct YieldPosition: Equatable, Sendable {
    let protocolID: String
    let venueID: String
    /// L'adresse qui la détient et l'autorise (Main account ou Pocket).
    let holder: String
    /// Parts détenues, unités on-chain.
    let shares: Int128
    /// Valeur actuelle en actif du lieu, unités on-chain (quantité, jamais de dollars).
    let value: Int128
}

/// Un protocole de rendement : portage de `StrategyProtocol` (`reference/terminal/src/modules/earn/registry/protocols.ts`),
/// découpé pour l'iPhone : l'adaptateur rend l'appel et sa forme **avant** le tap au lieu d'exécuter (`execute`) ; la
/// signature passe par `IntegrationCallClient`. Le déplacement d'une position (`move`) n'est pas repris (cosignataire).
protocol YieldAdapter {
    var id: String { get }
    var name: String { get }
    /// Un mot pour la tuile : « Vaults », « Liquidity ».
    var category: String { get }
    /// Menu d'une nouvelle position (une seule entrée → directement l'étape montant).
    var openActions: [YieldAction] { get }
    /// Menu d'une position existante.
    var manageActions: [YieldAction] { get }
    /// Les lieux proposés (vide = protocole masqué).
    func venues() -> [YieldVenue]
    /// Les positions de `holder` chez ce protocole, lues sur la chaîne. Les pannes réseau remontent.
    func discover(holder: String) async throws -> [YieldPosition]
    /// Dépôt de `amount` (unités on-chain de l'actif du lieu) au nom de `authorizer`.
    func depositCall(venue: YieldVenue, amount: Int128, authorizer: String) async throws -> ContractCall
    /// Retrait de `amount` de l'actif (ou de toute la position si `all`), minimum signé compris.
    func withdrawCall(position: YieldPosition, amount: Int128, all: Bool) async throws -> ContractCall
    func authShape() -> any AuthShape
    func terms(of call: ContractCall) throws -> SignedTerms
}
