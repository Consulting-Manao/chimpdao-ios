import Foundation

/// Un cadeau qui attend sur une carte du compte (carte partenaire, contrat `prize`, D5) : de l'argent mis de côté pour
/// cette carte, que seule elle peut faire entrer dans son wallet.
struct PrizeGift: Equatable, Identifiable, Sendable {
    let cardKey: ChipPublicKey
    /// Nom et couleur locaux de la carte (« Banana »).
    let cardName: String
    let cardColor: ChimpCardColor
    /// « 0007 », `nil` si ce téléphone ne connaît pas le numéro.
    let cardNumber: String?
    /// Le wallet de la carte (Pocket) : là où l'argent arrive.
    let wallet: String
    /// Ce qui est mis de côté, dans l'unité de l'actif (XLM).
    let amount: Decimal
    /// Infineon : un PIN est demandé avant le tap. DUOX : jamais.
    let usesPin: Bool
    let curve: ChipCurve

    var id: String { cardKey.hex }
    /// Le jeton du contrat sur testnet.
    var asset: SendAsset { .xlm }
    /// « Banana's wallet ».
    var walletTitle: String { String(localized: "\(cardName)'s wallet") }
}

/// Le cadeau entré dans le wallet, confirmé sur la chaîne.
struct PrizeReceipt: Equatable {
    let gift: PrizeGift
    let transactionHash: String
    let sentAt: Date
    let explorerURL: URL?

    /// La ligne que ce téléphone écrit dans son historique.
    func activityRecord(prize: String) -> ActivityRecord {
        .gift(hash: transactionHash, prize: prize, wallet: gift.wallet, assetCode: gift.asset.code, amount: gift.amount, at: sentAt)
    }
}

/// Ce qu'un retrait à l'issue incertaine portait (« Check again »). Rangé dans `PendingSend.prize`.
struct PendingPrize: Codable, Equatable {
    var cardKey: String
    var cardName: String
}

/// Ce qu'un écran peut dire d'un retrait impossible **avant** toute signature.
enum PrizeServiceError: Error, Equatable, LocalizedError {
    /// Pas de contrat `prize` sur ce réseau (pas encore déployé).
    case unavailable
    case noAccount
    /// La carte n'est plus dans le compte, ou n'a pas de wallet.
    case unknownCard

    var errorDescription: String? {
        switch self {
        case .unavailable: "Gifts aren't available on this network yet."
        case .noAccount: "No account is open on this phone."
        case .unknownCard: "This card isn't on your account anymore."
        }
    }
}

/// Service des cadeaux. `ChainPrizeService` (testnet, `Core/`) dans l'app, `MockPrizeService` dans le catalogue et les
/// tests. Mêmes étapes et mêmes garanties qu'Envoyer, Swap et le vault.
protocol PrizeService {
    var network: StellarNetwork { get }
    /// Les cartes du compte qui ont quelque chose de mis de côté (aucune si le contrat n'est pas configuré).
    func gifts() async throws -> [PrizeGift]
    /// Avant la session NFC (règle 9) : coffre relu (refus s'il est vide), propriétaire du NFT vérifié, nonces, ledger.
    func prepare(_ gift: PrizeGift) async throws -> PreparedPrizeClaim
    /// Juste avant d'ouvrir la session NFC : à préparer de nouveau si l'autorisation expire bientôt.
    func refreshedIfNeeded(_ prepared: PreparedPrizeClaim, gift: PrizeGift) async throws -> PreparedPrizeClaim
    /// Le tap : l'attestation, puis l'autorisation du wallet de la carte, dans la même session.
    func sign(_ prepared: PreparedPrizeClaim, pin: String?) async throws -> CardSignatures
    func knownCard(_ key: ChipPublicKey) -> KnownCard?
    /// Après le tap. Toute erreur est un `PaymentFailure` : l'issue se vérifie avec `check`.
    func submit(_ prepared: PreparedPrizeClaim, gift: PrizeGift, signed: CardSignatures, onProgress: @escaping (PaymentProgress) -> Void) async throws -> PrizeReceipt
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck
    var pendingSend: PendingSend? { get }
    func setPendingSend(_ pending: PendingSend?) throws
    func explorerURL(transactionHash: String) -> URL?
}
