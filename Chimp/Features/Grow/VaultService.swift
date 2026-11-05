import Foundation

/// Mettre dans le vault ou en retirer (F3 à F5, F7).
enum VaultAction: String, Codable, Equatable, Sendable {
    case deposit
    case withdraw
}

/// Le vault proposé (un seul pour l'instant : le vault XLM de DeFindex), tel que l'écran le nomme.
struct VaultInfo: Equatable {
    /// Adresse du vault.
    let id: String
    /// « DeFindex XLM ».
    let name: String
    /// « DeFindex », « Blend » : nommés partout avec l'avertissement (principe 6).
    let protocols: [String]
    /// L'actif du vault (XLM).
    let asset: SendAsset
    /// Montant que le vault prête en ce moment, dans l'actif (sur testnet le 2026-10-15 : 0, tout attend).
    let invested: Decimal
    let totalManaged: Decimal

    /// « DeFindex → Blend ».
    var protocolChain: String { protocols.joined(separator: " → ") }

    /// Un vault DeFindex, ou un marché de prêt XOXNO (phase 7 : dépôt seulement, sans parts, montant exact), ou un vault
    /// Sentora (montant exact aussi : le même parcours que le prêt).
    var kind: VaultKind = .vault
    /// Le pot de ce lieu (logo, nom).
    var mark: ChimpPotProtocol = .defindex
    /// Prêt : ce que le marché laisse retirer maintenant (limite d'utilisation comprise), `nil` pour un vault.
    var withdrawableNow: Decimal? = nil
    /// Prêt : le marché refuse les dépôts (gel ou pause), ou les retraits (pause).
    var depositsBlocked = false
    var withdrawalsBlocked = false

    /// Ce que le vault peut rendre tout de suite : ce qui n'est pas prêté (le reste revient quand les emprunteurs
    /// remboursent). Prêt : ce que le marché laisse retirer.
    var availableNow: Decimal { withdrawableNow ?? max(0, totalManaged - invested) }
}

enum VaultKind: Equatable, Sendable {
    case vault
    case lending
}

/// Une position du compte : un tiroir qui détient des parts du vault.
struct VaultHolding: Equatable {
    let drawerID: String
    let drawerAddress: String
    /// Parts détenues (exactes, 7 décimales).
    let shares: Decimal
    /// Valeur actuelle, dans l'actif du vault (exacte).
    let value: Decimal
    /// Ce qui a été mis et depuis quand (historique) ; `nil` si on ne le sait pas.
    let basis: VaultBasis?
    let readAt: Date

    /// Prêt : une position avec dette (jamais créée par l'app) ou dont les données ont expiré ne se déplace pas.
    var condition: HoldingCondition = .movable

    /// Évolution réelle depuis le dépôt (`nil` sans base connue).
    var change: Decimal? { basis?.change(value: value) }
}

enum HoldingCondition: Equatable, Sendable {
    case movable
    /// Une dette existe sur la position : montrée sans action possible (décision de Barth du 2026-10-16).
    case hasDebt
    /// Les données de la position ont expiré sur la chaîne : `value` n'est pas connue (jamais affichée comme zéro).
    case needsRenewal
}

/// Ce que le parcours du vault a besoin de connaître avant de commencer.
struct VaultContext: Equatable {
    var network: StellarNetwork
    /// Main d'abord, puis les wallets des cartes.
    var drawers: [SendDrawer]
    var vault: VaultInfo
    var holdings: [VaultHolding]

    /// La position déplaçable du tiroir d'abord (un tiroir peut détenir une position à renouveler en plus).
    func holding(drawerID: String) -> VaultHolding? {
        holdings.first { $0.drawerID == drawerID && $0.condition == .movable } ?? holdings.first { $0.drawerID == drawerID }
    }
}

/// Le devis d'un dépôt ou d'un retrait (lecture seule, rien n'est signé). Montants en `TokenAmount` (aucun montant
/// 128 bits nu ne traverse une fonction `async`).
struct VaultQuote: Equatable {
    let action: VaultAction
    /// Dépôt : l'actif mis. Retrait : l'actif demandé (« about » pour « All »).
    let amount: Decimal
    /// Dépôt : parts attendues (« about »). Retrait : parts rendues (exactes, celles que la carte signe).
    let shares: TokenAmount
    /// Retrait : ce que le vault rendrait au prix du moment, et le minimum signé (− 0,5 %). `nil` pour un dépôt.
    let expectedOut: TokenAmount?
    let minimumOut: TokenAmount?
    /// Retrait de toutes les parts.
    let all: Bool
    /// Décimales on-chain des unités ci-dessus : 7, ou 8 chez Solv (SolvBTC et xSolvBTC).
    var decimals = SACClient.decimals

    var sharesAmount: Decimal { SACClient.amount(fromUnits: Decimal(string: String(shares.units)) ?? 0, chainDecimals: decimals) }
    var expected: Decimal? { expectedOut.map { SACClient.amount(fromUnits: Decimal(string: String($0.units)) ?? 0, chainDecimals: decimals) } }
    var minimum: Decimal? { minimumOut.map { SACClient.amount(fromUnits: Decimal(string: String($0.units)) ?? 0, chainDecimals: decimals) } }
}

/// Ce qui sera signé, figé au passage à la vérification (F4, F7r). Affiché tel quel.
struct VaultDraft: Equatable {
    let drawer: SendDrawer
    let vault: VaultInfo
    let quote: VaultQuote
    let network: StellarNetwork

    var action: VaultAction { quote.action }
    var amount: Decimal { quote.amount }
}

/// Préparé **avant** la session NFC (règle 9) : appel construit, bornes vérifiées, autorisation à signer.
struct PreparedVault: Equatable {
    let draft: VaultDraft
    let integration: PreparedIntegrationCall?

    init(draft: VaultDraft, integration: PreparedIntegrationCall? = nil) {
        self.draft = draft
        self.integration = integration
    }

    static func == (lhs: PreparedVault, rhs: PreparedVault) -> Bool {
        lhs.draft == rhs.draft && lhs.integration?.digest == rhs.integration?.digest
    }
}

struct SignedVault: Equatable {
    let prepared: PreparedVault
    let cardName: String
    let card: CardSignatures?

    init(prepared: PreparedVault, cardName: String, card: CardSignatures? = nil) {
        self.prepared = prepared
        self.cardName = cardName
        self.card = card
    }
}

struct VaultCardRead: Equatable {
    let check: CardCheck
    let signed: SignedVault?
}

/// Ce qui a été signé, tel qu'on le réaffiche après coup (envoi, succès, issue incertaine), y compris depuis une opération
/// en attente gardée sur le téléphone.
struct VaultSummary: Equatable {
    let action: VaultAction
    let drawerTitle: String
    /// « Main » pour le Main account, sinon le titre du wallet.
    let drawerShortTitle: String
    let drawerAddress: String
    let vaultName: String
    let asset: SendAsset
    /// Dépôt : ce qui est mis. Retrait : ce qui est attendu.
    let amount: Decimal
    let shares: Decimal?
    let minimumOut: Decimal?
    let network: StellarNetwork
    /// Un vault, ou un marché de prêt (XOXNO).
    let kind: VaultKind

    /// « the vault », ou le protocole (« XOXNO », « Sentora ») pour un lieu à montant exact.
    var placeName: String { kind == .lending ? protocolName : String(localized: "the vault") }

    /// « XOXNO », « Sentora » (premier mot du nom du lieu), ou « DeFindex ».
    var protocolName: String {
        kind == .lending ? String(vaultName.split(separator: " ").first ?? "XOXNO") : "DeFindex"
    }

    init(_ draft: VaultDraft) {
        action = draft.action
        drawerTitle = draft.drawer.title
        drawerShortTitle = if case .main = draft.drawer.kind { String(localized: "Main") } else { draft.drawer.title }
        drawerAddress = draft.drawer.address
        vaultName = draft.vault.name
        asset = draft.vault.asset
        amount = draft.action == .deposit ? draft.amount : (draft.quote.expected ?? draft.amount)
        shares = draft.quote.sharesAmount
        minimumOut = draft.quote.minimum
        network = draft.network
        kind = draft.vault.kind
    }

    /// Depuis une opération en attente (`PendingSend.vault`) ; `nil` si ce n'en est pas une.
    init?(_ pending: PendingSend, network: StellarNetwork) {
        guard let vault = pending.vault, let action = VaultAction(rawValue: vault.action) else { return nil }
        self.action = action
        drawerTitle = pending.drawerTitle
        drawerShortTitle = pending.drawerTitle == String(localized: "Main account") ? String(localized: "Main") : pending.drawerTitle
        drawerAddress = pending.trace.from
        vaultName = vault.vaultName
        asset = SendAsset(rawValue: pending.asset) ?? .xlm
        amount = pending.amount
        shares = vault.shares
        minimumOut = vault.minimumReceived
        self.network = network
        // L'opération gardée sur le téléphone ne porte pas le type de lieu : un nom XOXNO ou Sentora le dit.
        kind = vault.vaultName.hasPrefix("XOXNO") || vault.vaultName.hasPrefix("Sentora") ? .lending : .vault
    }
}

/// Dépôt ou retrait confirmé sur la chaîne.
struct VaultReceipt: Equatable {
    let summary: VaultSummary
    let transactionHash: String
    let sentAt: Date
    let explorerURL: URL?
    /// Dépôt : parts reçues ; retrait : actif revenu. Lus dans la valeur rendue par le vault, `nil` si illisibles.
    let shares: Decimal?
    let received: Decimal?

    /// La ligne que ce téléphone écrit dans son historique (I1g) : « See the receipt » ouvre le même reçu.
    func activityRecord(vault: String, label: ActivityRecord.VaultLabel) -> ActivityRecord {
        switch summary.action {
        case .deposit:
            .vaultDeposit(
                hash: transactionHash, drawer: summary.drawerAddress, vault: vault, label: label, assetCode: summary.asset.code,
                amount: summary.amount, shares: shares, at: sentAt
            )
        case .withdraw:
            .vaultWithdraw(
                hash: transactionHash, drawer: summary.drawerAddress, vault: vault, label: label, assetCode: summary.asset.code,
                received: received, shares: summary.shares, at: sentAt
            )
        }
    }
}

/// Ce qu'un écran peut dire d'une opération impossible **avant** toute signature.
enum VaultServiceError: Error, Equatable, LocalizedError {
    /// Le vault ne répond pas (réseau, RPC, contrat en panne) : F3b.
    case vaultUnavailable
    case noVault
    case noAccount
    case unknownDrawer(String)
    /// Le dépôt ou le retrait a bougé depuis la vérification (le vault rendrait moins que le minimum affiché).
    case priceMoved

    var errorDescription: String? {
        switch self {
        case .vaultUnavailable: "The vault is unavailable right now."
        case .noVault: "No vault on this network."
        case .noAccount: "No account is open on this phone."
        case .unknownDrawer(let id): "Unknown drawer \(id)."
        case .priceMoved: "The vault's numbers moved since you checked them."
        }
    }
}

/// Service du vault. `ChainVaultService` (testnet, `Core/`) dans l'app, `MockVaultService` dans le catalogue et les tests.
/// Mêmes étapes et mêmes garanties qu'Envoyer et Swap.
protocol VaultService {
    /// Le réseau du vault (celui de la session) : résumés d'une opération en attente.
    var network: StellarNetwork { get }
    func fetchContext() async throws -> VaultContext
    /// Devis d'un dépôt de `amount` depuis `drawer` : parts attendues (lecture seule).
    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote
    /// Devis d'un retrait de `amount` (ou de tout) de la position de `drawer` : parts, valeur attendue, minimum.
    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote
    /// Avant la session NFC : solde ou parts relus, appel construit **avec les bornes du brouillon**, bornes vérifiées,
    /// autorisation préparée. Rien n'est signé.
    func prepare(_ draft: VaultDraft) async throws -> PreparedVault
    func refreshedIfNeeded(_ prepared: PreparedVault) async throws -> PreparedVault
    func readCard(for prepared: PreparedVault) async throws -> VaultCardRead
    func sign(_ prepared: PreparedVault, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedVault
    func knownCard(_ key: ChipPublicKey) -> KnownCard?
    /// Après le tap. Toute erreur est un `PaymentFailure` : l'issue se vérifie avec `check`.
    /// La trace que l'envoi suivra, connue **avant** l'envoi : gardée sur le téléphone dès le retour de la carte (revue
    /// de sécurité F7), pour qu'une app tuée pendant l'envoi ne permette jamais une nouvelle signature.
    func trace(for signed: SignedVault) throws -> PaymentTrace
    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck
    var pendingSend: PendingSend? { get }
    func setPendingSend(_ pending: PendingSend?) throws
    func explorerURL(transactionHash: String) -> URL?
}
