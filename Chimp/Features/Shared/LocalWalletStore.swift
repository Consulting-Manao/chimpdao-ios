import Foundation

/// Ce que l'app garde sur le téléphone. **Aucun secret** (règle 1) : des adresses et des clés publiques, déjà
/// publiques sur la chaîne, plus le prénom et le nom des cartes (décision du 2026-09-29, DESIGN_NOTES §12).
/// Jamais de PIN, de PUK, de clé privée ni de seed.
struct LocalWallet: Codable, Equatable {
    static let currentVersion = 1

    var version = LocalWallet.currentVersion
    /// Prénom du compte ouvert (A4, « Hey Léo »). Chaque compte a le sien : à la déconnexion, il part avec le compte
    /// fermé (`SavedAccount.firstName`) et revient avec lui à la reconnexion.
    var firstName: String?
    /// La visite guidée (A1·1 à A1·4) a été vue ou passée : elle n'est montrée qu'au premier lancement.
    var tourSeen = false
    /// Le Main account ouvert sur ce téléphone, ou `nil` (onboarding à faire).
    var account: SavedAccount?
    /// Dernier compte **vérifié** de chaque carte vue sur ce téléphone (`cardHint` du terminal), le plus récent d'abord.
    var cardHints: [CardHint] = []
    /// Paiement signé dont l'issue n'est pas encore certaine (envoyé sans confirmation, ou autorisation encore valable).
    /// Tant qu'il est là, Envoyer rouvre son écran d'état au lieu d'un nouvel envoi : jamais de double paiement, même
    /// après un redémarrage de l'app (décision de Barth, DESIGN_NOTES §12 et question 16).
    var pendingSend: PendingSend?
    /// Comptes fermés par « Disconnect this phone », avec les noms et couleurs de leurs cartes : une reconnexion au même
    /// compte les retrouve sans rien redemander (demande de Barth du 2026-09-30). Données publiques et noms, comme
    /// `account`. Optionnel : un fichier écrit avant ce champ reste lisible.
    var disconnectedAccounts: [SavedAccount]?
    /// Autres comptes **ouverts** sur ce téléphone (I6 « Switch account »), en plus de `account`, avec leur prénom : on
    /// passe de l'un à l'autre sans carte (l'app ne garde aucun secret). Le plus récemment quitté d'abord. Un compte fermé
    /// par « Disconnect » n'y est pas : il faut une de ses cartes pour le rouvrir. Optionnel : un fichier écrit avant ce
    /// champ reste lisible.
    var otherAccounts: [SavedAccount]?

    /// Compte fermé sur ce téléphone, s'il y en a un à cette adresse.
    func disconnectedAccount(_ address: String) -> SavedAccount? {
        disconnectedAccounts?.first { $0.address == address }
    }

    /// Autre compte ouvert sur ce téléphone, s'il y en a un à cette adresse.
    func otherAccount(_ address: String) -> SavedAccount? {
        otherAccounts?.first { $0.address == address }
    }

    /// Ce que le téléphone sait d'un compte : ouvert, autre compte ouvert, ou fermé par « Disconnect ».
    func knownAccount(_ address: String) -> SavedAccount? {
        if account?.address == address { return account }
        return otherAccount(address) ?? disconnectedAccount(address)
    }

    /// Comptes ouverts sur ce téléphone (I6) : le compte affiché d'abord, puis les autres.
    var openAccounts: [SavedAccount] {
        guard var current = account else { return [] }
        current.firstName = firstName
        return [current] + (otherAccounts ?? [])
    }

    /// Prénom connu de ce téléphone pour ce compte : celui du compte ouvert, ou celui gardé avec le compte fermé.
    /// Fichier écrit par la version précédente (prénom resté au niveau du téléphone après une déconnexion) : il appartient
    /// au dernier compte fermé, et à lui seul.
    func firstName(for address: String) -> String? {
        if account?.address == address { return firstName }
        if let other = otherAccount(address) { return other.firstName }
        guard let closed = disconnectedAccount(address) else { return nil }
        if let name = closed.firstName { return name }
        return account == nil && disconnectedAccounts?.first?.address == address ? firstName : nil
    }

    /// Compte mémorisé pour cette carte, vérifié en premier par la résolution (jamais cru sans `has_card`).
    func hint(for publicKey: ChipPublicKey) -> String? {
        cardHints.first { $0.key == publicKey.hex }?.account
    }
}

/// Un paiement signé à l'issue incertaine. Rien de secret : la trace publique (adresses, montant, nonce, ledgers) et
/// de quoi réafficher ce qui a été signé.
struct PendingSend: Codable, Equatable {
    var trace: PaymentTrace
    /// Adresse exacte payée (G, M ou C) et nom local du destinataire.
    var recipient: String
    var recipientName: String?
    /// Tiroir source tel qu'affiché (« Main account », « Jungle's wallet »).
    var drawerTitle: String
    /// `SendAsset.rawValue`.
    var asset: String
    /// Montant dans l'unité de l'actif.
    var amount: Decimal
    var signedAt: Date
}

/// Un Main account et ses cartes connues sur ce téléphone.
struct SavedAccount: Codable, Equatable {
    /// Adresse C du Main account.
    var address: String
    var cards: [SavedCard]
    /// Prénom de ce compte, gardé ici quand ce n'est pas le compte affiché (autre compte ouvert, ou compte fermé par
    /// « Disconnect this phone »).
    var firstName: String? = nil
}

/// Une carte du compte : données publiques (clé, puce, NFT, Pocket) et données locales (nom, couleur).
struct SavedCard: Codable, Equatable, Identifiable {
    /// Clé publique, 130 caractères hexadécimaux (format du bridge).
    var publicKey: String
    /// `ChipKind.rawValue` (`infineon2Go`, `duox`).
    var chip: String
    /// Numéro du NFT (`nfc-nft.token_id`), affiché « N°0007 ».
    var tokenID: UInt32?
    /// Adresse C de la Pocket (le wallet de la carte).
    var pocket: String?
    /// Nom et couleur choisis à l'onboarding (A5) ; `nil` pour une carte retrouvée sur un nouveau téléphone.
    var name: String?
    var color: String?

    var id: String { publicKey }
}

/// `CardHint` de `reference/terminal/src/session/cardHint.ts` : un **indice**, jamais une autorité.
/// Chaque entrée est la copie d'une réponse que `has_card` a déjà donnée, et chaque lecture est revérifiée
/// par `has_card` avant de servir. Il existe parce que `account.add_card` n'écrit aucun pointeur on-chain :
/// une carte ajoutée à un compte ne le retrouve que grâce à lui.
struct CardHint: Codable, Equatable {
    /// Clé publique de la carte (hexadécimal).
    var key: String
    /// Adresse C du Main account.
    var account: String
    var at: Date

    /// `MAX_HINTS` : au-delà, les plus anciens sont oubliés (ils se retrouvent par la chaîne).
    static let maximum = 32

    /// `withHint` : le plus récent d'abord, une seule entrée par carte, les plus anciens retirés au-delà du plafond.
    static func adding(_ hint: CardHint, to hints: [CardHint], maximum: Int = CardHint.maximum) -> [CardHint] {
        Array(([hint] + hints.filter { $0.key != hint.key }).prefix(maximum))
    }
}

/// Lecture et écriture du `LocalWallet`. Implémenté par `FileLocalWalletStore` (fichier) et `InMemoryLocalWalletStore`.
protocol LocalWalletStore {
    func load() throws -> LocalWallet
    func save(_ wallet: LocalWallet) throws
    /// Efface tout (mode développeur : refaire l'onboarding).
    func erase() throws
}

/// Un fichier JSON dans Application Support, un par réseau, protégé par iOS (`NSFileProtectionComplete` :
/// illisible tant que le téléphone est verrouillé). Décision du 2026-09-29.
struct FileLocalWalletStore: LocalWalletStore {
    let fileURL: URL

    init(network: StellarNetwork, directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appending(path: "ChimpDAO", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "wallet-\(network.rawValue).json")
    }

    /// Fichier absent : un `LocalWallet` vide. Fichier illisible (abîmé, version inconnue) : il est mis de côté
    /// (`.unreadable`) plutôt qu'écrasé, et l'app repart d'un état vide. Rien n'est perdu on-chain : une carte
    /// retrouve son compte par la chaîne (sauf une carte ajoutée, qui a besoin de son indice).
    func load() throws -> LocalWallet {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LocalWallet() }
        let data = try Data(contentsOf: fileURL)
        do {
            let wallet = try Self.decoder.decode(LocalWallet.self, from: data)
            guard wallet.version == LocalWallet.currentVersion else { throw CocoaError(.fileReadCorruptFile) }
            return wallet
        } catch {
            let aside = fileURL.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: fileURL, to: aside)
            return LocalWallet()
        }
    }

    func save(_ wallet: LocalWallet) throws {
        let data = try Self.encoder.encode(wallet)
        try data.write(to: fileURL, options: Self.writingOptions)
    }

    /// Écriture atomique, fichier protégé (`NSFileProtectionComplete`). Le simulateur n'applique pas la protection.
    static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    /// Supprime le fichier, et sa copie mise de côté s'il y en a une (`.unreadable`) : rien ne reste sur le téléphone.
    func erase() throws {
        for url in [fileURL, fileURL.appendingPathExtension("unreadable")] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Stockage en mémoire, pour les tests et le catalogue.
final class InMemoryLocalWalletStore: LocalWalletStore, @unchecked Sendable {
    private(set) var wallet: LocalWallet
    private(set) var saveCount = 0

    init(_ wallet: LocalWallet = LocalWallet()) {
        self.wallet = wallet
    }

    func load() throws -> LocalWallet { wallet }

    func save(_ wallet: LocalWallet) throws {
        self.wallet = wallet
        saveCount += 1
    }

    func erase() throws {
        wallet = LocalWallet()
    }
}
