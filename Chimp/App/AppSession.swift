import Foundation
import Observation

/// État de l'app sur ce téléphone : le `LocalWallet` et son stockage. Décide de l'écran de départ :
/// pas de compte → onboarding (A1) ; un compte → Wallet.
@Observable
final class AppSession {
    private(set) var wallet: LocalWallet
    /// Le fichier n'a pas pu être lu au lancement (texte technique) : l'app repart de l'onboarding.
    private(set) var loadError: String?
    let network: StellarNetwork
    /// Historique (onglet Activity), dans son propre fichier.
    let activity: ActivityStore
    private let store: LocalWalletStore

    init(store: LocalWalletStore, network: StellarNetwork, activity: ActivityStore = InMemoryActivityStore()) {
        self.store = store
        self.network = network
        self.activity = activity
        do {
            wallet = try store.load()
        } catch {
            wallet = LocalWallet()
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Session de l'app : fichier sur le téléphone, réseau testnet (V1, CLAUDE.md « Périmètre V1 »).
    static func live() -> AppSession {
        let network = ChimpNetworkConfig.testnet.network
        do {
            let activity: ActivityStore = (try? FileActivityStore(network: network)) ?? InMemoryActivityStore()
            return AppSession(store: try FileLocalWalletStore(network: network), network: network, activity: activity)
        } catch {
            // Application Support inaccessible : l'app fonctionne, mais sans rien retenir.
            let session = AppSession(store: InMemoryLocalWalletStore(), network: network)
            session.loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return session
        }
    }

    var hasAccount: Bool { wallet.account != nil }

    /// Compte tout juste créé, mais A7 (« How your Jungle works ») est encore à l'écran : l'onboarding reste affiché
    /// jusqu'à « Let's swing ». Pas enregistré : au prochain lancement, le compte ouvre directement le Wallet.
    private(set) var isFinishingOnboarding = false

    /// Écran de départ : l'onboarding tant qu'il n'y a pas de compte, ou tant qu'A7 n'est pas passé.
    var showsOnboarding: Bool { !hasAccount || isFinishingOnboarding }

    /// La visite guidée a été vue ou passée. Si l'écriture échoue, elle sera simplement proposée à nouveau.
    func markTourSeen() {
        guard !wallet.tourSeen else { return }
        var next = wallet
        next.tourSeen = true
        try? persist(next)
        wallet.tourSeen = true
    }

    /// Carte déjà membre d'un Main account (`signIn` de la résolution) : on ouvre ce compte sur le téléphone.
    /// Comme le terminal : rien n'est signé (une Infineon a d'abord vérifié son PIN, `ReconnectModel`). L'indice
    /// « carte → compte » est mis à jour. `firstName` : prénom redemandé par « Welcome back! » (sinon, celui du téléphone).
    /// Les noms et couleurs des cartes d'un compte fermé par « Disconnect this phone » sont repris.
    func signIn(account: String, card: SavedCard, firstName: String? = nil, at date: Date = .now) throws {
        var next = wallet
        next.firstName = firstName ?? next.firstName(for: account)
        var cards = Self.knownCards(of: account, in: next)
        next.disconnectedAccounts = Self.removing(account, from: next.disconnectedAccounts)
        if let index = cards.firstIndex(where: { $0.publicKey == card.publicKey }) {
            // Garder le nom et la couleur déjà choisis sur ce téléphone.
            var merged = card
            merged.name = card.name ?? cards[index].name
            merged.color = card.color ?? cards[index].color
            cards[index] = merged
        } else {
            cards.append(card)
        }
        next.account = SavedAccount(address: account, cards: cards)
        next.cardHints = CardHint.adding(CardHint(key: card.publicKey, account: account, at: date), to: next.cardHints)
        try persist(next)
    }

    /// Cartes que le compte déclare lui-même (`cards()`, lu par le Wallet) : gardées comme indices « carte → compte »,
    /// comme `loadAccountView` du terminal. N'écrit que si quelque chose change ; un échec d'écriture est sans gravité.
    func rememberCards(_ keys: [String], account: String, at date: Date = .now) {
        let missing = keys.filter { key in !wallet.cardHints.contains { $0.key == key && $0.account == account } }
        guard !missing.isEmpty else { return }
        var next = wallet
        for key in missing.reversed() {
            next.cardHints = CardHint.adding(CardHint(key: key, account: account, at: date), to: next.cardHints)
        }
        try? persist(next)
    }

    /// Paiement à l'issue incertaine (`nil` : aucun). Enregistré **avant** d'afficher l'état, effacé quand l'issue est
    /// certaine (envoyé, ou rien n'est parti). Lève une erreur si le téléphone n'a pas pu l'écrire.
    func setPendingSend(_ pending: PendingSend?) throws {
        guard wallet.pendingSend != pending else { return }
        var next = wallet
        next.pendingSend = pending
        try persist(next)
    }

    /// Compte créé **et confirmé sur la chaîne** (étape 4) : on l'enregistre sur le téléphone, avec le prénom, le nom
    /// et la couleur de la carte (données locales), puis A7 s'affiche avant le Wallet.
    func completeOnboarding(account: String, card: SavedCard, firstName: String, at date: Date = .now) throws {
        var next = wallet
        next.firstName = firstName
        // Un compte déjà ouvert puis fermé sur ce téléphone (rejoindre) garde les noms de ses autres cartes.
        let known = SavedAccount(address: account, cards: Self.knownCards(of: account, in: next))
        next.account = Self.upserting(card, into: known)
        next.disconnectedAccounts = Self.removing(account, from: next.disconnectedAccounts)
        next.cardHints = CardHint.adding(CardHint(key: card.publicKey, account: account, at: date), to: next.cardHints)
        isFinishingOnboarding = true
        do {
            try persist(next)
        } catch {
            isFinishingOnboarding = false
            throw error
        }
    }

    /// « Let's swing » (A7) : le Wallet remplace l'onboarding.
    func finishOnboarding() {
        isFinishingOnboarding = false
    }

    // MARK: Réglages (I2)

    enum SettingsError: Error, Equatable, LocalizedError {
        /// Pas de compte ouvert sur ce téléphone.
        case noAccount
        /// Un paiement signé attend encore son issue : le téléphone doit le garder (garde-fou contre un double envoi).
        case pendingPayment

        var errorDescription: String? {
            switch self {
            case .noAccount: "No account is open on this phone."
            case .pendingPayment: "A payment is still being checked."
            }
        }
    }

    /// Nom et couleur d'une carte du compte (données locales, rien on-chain). Une carte que ce téléphone ne connaissait
    /// pas encore (ajoutée ailleurs, lue par `cards()`) y est enregistrée avec ce que le Wallet a lu d'elle.
    func renameCard(_ card: SavedCard) throws {
        guard let account = wallet.account else { throw SettingsError.noAccount }
        var next = wallet
        next.account = Self.upserting(card, into: account)
        try persist(next)
    }

    /// Carte ajoutée au compte (G3), **après** confirmation sur la chaîne : enregistrée avec son nom et sa couleur, et
    /// gardée comme indice « carte → compte » : une carte ajoutée n'a que lui pour retrouver son compte sur un téléphone
    /// (`account.add_card` n'écrit aucun pointeur, `cardHint.ts`).
    func addCard(_ card: SavedCard, account address: String, at date: Date = .now) throws {
        guard let account = wallet.account, account.address == address else { throw SettingsError.noAccount }
        var next = wallet
        next.account = Self.upserting(card, into: account)
        next.cardHints = CardHint.adding(CardHint(key: card.publicKey, account: address, at: date), to: next.cardHints)
        try persist(next)
    }

    /// Ligne d'historique écrite par ce téléphone (envoi, Move ou carte ajoutée **confirmés**), rangée avec ce compte.
    func recordActivity(_ record: ActivityRecord, account: String) {
        activity.recordLocal(record, account: account)
    }

    /// Rejoindre un compte depuis l'onboarding (A9) : même enregistrement qu'une création (`completeOnboarding`).
    func completeJoin(account: String, card: SavedCard, firstName: String, at date: Date = .now) throws {
        try completeOnboarding(account: account, card: card, firstName: firstName, at: date)
    }

    /// Une carte connue garde sa puce, son NFT et son wallet ; seuls le nom et la couleur changent. Sinon, elle est ajoutée.
    private static func upserting(_ card: SavedCard, into account: SavedAccount) -> SavedAccount {
        var account = account
        if let index = account.cards.firstIndex(where: { $0.publicKey == card.publicKey }) {
            account.cards[index].name = card.name
            account.cards[index].color = card.color
        } else {
            account.cards.append(card)
        }
        return account
    }

    /// Prénom de « Hey Léo » (A4 : « you can change it in Settings »).
    func setFirstName(_ firstName: String) throws {
        var next = wallet
        next.firstName = firstName
        try persist(next)
    }

    /// « Disconnect this phone » (I2) : le compte se ferme sur ce téléphone et l'app revient à A1. Comme `logout` du
    /// terminal, les indices « carte → compte » restent ; la visite reste vue. Le prénom et le compte fermé (avec les noms
    /// et couleurs de ses cartes) sont **gardés** : une reconnexion au même compte les retrouve, sans « Welcome back! »
    /// (demande de Barth du 2026-09-30). Rien ne change on-chain : un tap d'une carte du compte le rouvre.
    /// Refusé tant qu'un paiement signé attend son issue.
    func disconnect() throws {
        guard wallet.pendingSend == nil else { throw SettingsError.pendingPayment }
        var next = wallet
        if var account = next.account {
            account.firstName = next.firstName
            next.disconnectedAccounts = [account] + (Self.removing(account.address, from: next.disconnectedAccounts) ?? [])
        }
        next.account = nil
        next.firstName = nil
        try persist(next)
    }

    /// Cartes connues de ce téléphone pour ce compte : celles du compte ouvert, sinon celles du compte fermé.
    private static func knownCards(of account: String, in wallet: LocalWallet) -> [SavedCard] {
        if wallet.account?.address == account { return wallet.account?.cards ?? [] }
        return wallet.disconnectedAccount(account)?.cards ?? []
    }

    private static func removing(_ account: String, from accounts: [SavedAccount]?) -> [SavedAccount]? {
        let rest = accounts?.filter { $0.address != account } ?? []
        return rest.isEmpty ? nil : rest
    }

    #if DESIGN_CATALOG
    /// Mode développeur : oublier le compte de ce téléphone pour refaire l'onboarding. Rien ne change on-chain.
    func forgetAccount() throws {
        try store.erase()
        wallet = LocalWallet()
    }
    #endif

    private func persist(_ next: LocalWallet) throws {
        try store.save(next)
        wallet = next
    }
}
