import Foundation
import Observation

/// État de l'app sur ce téléphone : le `LocalWallet` et son stockage. Décide de l'écran de départ :
/// pas de compte → onboarding (A1) ; un compte → Wallet.
@Observable
final class AppSession {
    private(set) var wallet: LocalWallet
    /// Le fichier n'a pas pu être lu au lancement (texte technique) : l'app repart de l'onboarding.
    private(set) var loadError: String?
    /// Le réseau, ses contrats et ses URLs : la configuration de ce build (`ChimpNetworkConfig.forThisBuild`), passée à
    /// tous les services. Aucun service ne choisit son réseau lui-même.
    let config: ChimpNetworkConfig
    var network: StellarNetwork { config.network }
    /// Historique (onglet Activity), dans son propre fichier.
    let activity: ActivityStore
    /// Réglages du téléphone (apparence, devise, Face ID), à part du `LocalWallet`.
    let preferences: AppPreferences
    private let store: LocalWalletStore

    init(
        store: LocalWalletStore, config: ChimpNetworkConfig, activity: ActivityStore = InMemoryActivityStore(),
        preferences: AppPreferences = AppPreferences(store: InMemoryPreferencesStore())
    ) {
        self.store = store
        self.config = config
        self.activity = activity
        self.preferences = preferences
        do {
            wallet = try store.load()
        } catch {
            wallet = LocalWallet()
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Session de l'app : fichier sur le téléphone, réseau de ce build (`ChimpNetworkConfig.forThisBuild`).
    static func live(config: ChimpNetworkConfig) -> AppSession {
        let network = config.network
        do {
            let activity: ActivityStore = (try? FileActivityStore(network: network)) ?? InMemoryActivityStore()
            return AppSession(
                store: try FileLocalWalletStore(network: network), config: config, activity: activity, preferences: .live()
            )
        } catch {
            // Application Support inaccessible : l'app fonctionne, mais sans rien retenir.
            let session = AppSession(store: InMemoryLocalWalletStore(), config: config, preferences: .live())
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
    /// Les noms et couleurs des cartes d'un compte déjà connu (fermé, ou autre compte ouvert) sont repris.
    /// Un autre compte déjà affiché (« + Add an account », I6) **reste ouvert** : il rejoint les autres comptes du
    /// téléphone. Refusé si un paiement de ce compte-là attend encore son issue.
    func signIn(account: String, card: SavedCard, firstName: String? = nil, at date: Date = .now) throws {
        if let current = wallet.account, current.address != account, wallet.pendingSend != nil {
            throw SettingsError.pendingPayment
        }
        var next = wallet
        next.firstName = firstName ?? wallet.firstName(for: account)
        var cards = Self.knownCards(of: account, in: wallet)
        next.disconnectedAccounts = Self.removing(account, from: next.disconnectedAccounts)
        next.otherAccounts = Self.removing(account, from: next.otherAccounts)
        if var previous = wallet.account, previous.address != account {
            previous.firstName = wallet.firstName
            next.otherAccounts = [previous] + (next.otherAccounts ?? [])
        }
        if let index = cards.firstIndex(where: { $0.publicKey == card.publicKey }) {
            // Garder le nom et la couleur déjà choisis sur ce téléphone.
            var merged = card
            merged.name = card.name ?? cards[index].name
            merged.color = card.color ?? cards[index].color
            cards[index] = merged
        } else {
            cards.append(card)
        }
        // Le réglage Face ID d'un compte déjà connu de ce téléphone revient avec lui.
        next.account = SavedAccount(address: account, cards: cards, opensWithFaceID: wallet.knownAccount(account)?.opensWithFaceID)
        next.cardHints = CardHint.adding(CardHint(key: card.publicKey, account: account, at: date), to: next.cardHints)
        try persist(next)
    }

    /// « Face ID to open the app » (I2) pour le compte affiché. Lève une erreur si aucun compte n'est ouvert ou si le
    /// téléphone n'a pas pu l'écrire.
    func setOpensWithFaceID(_ isOn: Bool) throws {
        guard var account = wallet.account else { throw SettingsError.noAccount }
        account.opensWithFaceID = isOn ? true : nil
        var next = wallet
        next.account = account
        try persist(next)
    }

    // MARK: Plusieurs comptes (I6 « Switch account »)

    /// Passe à un autre compte ouvert sur ce téléphone, **sans carte** (l'app ne garde aucun secret ; la maquette I6 est
    /// 🔓). Le compte quitté reste ouvert, en tête des autres. Refusé tant qu'un paiement signé attend son issue : il
    /// appartient au compte affiché.
    func switchAccount(to address: String) throws {
        guard wallet.pendingSend == nil else { throw SettingsError.pendingPayment }
        guard let current = wallet.account else { throw SettingsError.noAccount }
        guard current.address != address else { return }
        guard var target = wallet.otherAccount(address) else { throw SettingsError.unknownAccount }
        var next = wallet
        var leaving = current
        leaving.firstName = wallet.firstName
        next.otherAccounts = Self.removing(address, from: [leaving] + (wallet.otherAccounts ?? []))
        next.firstName = target.firstName
        target.firstName = nil
        next.account = target
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
        let known = SavedAccount(
            address: account, cards: Self.knownCards(of: account, in: next), opensWithFaceID: next.knownAccount(account)?.opensWithFaceID
        )
        next.account = Self.upserting(card, into: known)
        next.disconnectedAccounts = Self.removing(account, from: next.disconnectedAccounts)
        next.otherAccounts = Self.removing(account, from: next.otherAccounts)
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
        /// Ce compte n'est pas ouvert sur ce téléphone.
        case unknownAccount

        var errorDescription: String? {
            switch self {
            case .noAccount: "No account is open on this phone."
            case .pendingPayment: "A payment is still being checked."
            case .unknownAccount: "This account isn't open on this phone."
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

    /// Carte retirée du compte (G6) ou déclarée perdue (G7), **après** confirmation sur la chaîne (`has_card` faux) : elle
    /// quitte la liste du compte sur ce téléphone, avec son indice « carte → compte » (il désignerait un compte qui ne la
    /// liste plus ; la résolution la verrait orpheline de toute façon).
    func removeCard(_ publicKey: String, account address: String) throws {
        guard var account = wallet.account, account.address == address else { throw SettingsError.noAccount }
        var next = wallet
        account.cards.removeAll { $0.publicKey == publicKey }
        next.account = account
        next.cardHints.removeAll { $0.key == publicKey && $0.account == address }
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

    /// « Disconnect this phone » (I2, I6) : le compte affiché se ferme sur ce téléphone. Comme `logout` du terminal, les
    /// indices « carte → compte » restent ; la visite reste vue. Le prénom et le compte fermé (avec les noms et couleurs
    /// de ses cartes) sont **gardés** : une reconnexion au même compte les retrouve, sans « Welcome back! » (demande de
    /// Barth du 2026-09-30). Rien ne change on-chain : un tap d'une carte du compte le rouvre.
    /// S'il reste un autre compte ouvert, il s'affiche (le plus récemment quitté) ; sinon l'app revient à A1 (décision de
    /// Barth du 2026-09-30). Refusé tant qu'un paiement signé attend son issue.
    func disconnect() throws {
        guard wallet.pendingSend == nil else { throw SettingsError.pendingPayment }
        var next = wallet
        if var account = next.account {
            account.firstName = next.firstName
            next.disconnectedAccounts = [account] + (Self.removing(account.address, from: next.disconnectedAccounts) ?? [])
        }
        if var following = next.otherAccounts?.first {
            next.otherAccounts = Self.removing(following.address, from: next.otherAccounts)
            next.firstName = following.firstName
            following.firstName = nil
            next.account = following
        } else {
            next.account = nil
            next.firstName = nil
        }
        try persist(next)
    }

    /// « Erase everything on this phone » (I2, demandé par Barth le 2026-09-30) : pour un téléphone qu'on donne ou qu'on
    /// vend. Tout ce que l'app garde s'en va : compte ouvert, comptes fermés (prénoms, noms et couleurs des cartes), indices
    /// « carte → compte », visite, historique de l'Activity, réglages du téléphone, et tous les comptes ouverts. L'app
    /// revient à A1. Rien ne change on-chain : l'argent reste
    /// sur les cartes. Refusé tant qu'un paiement signé attend son issue (le téléphone doit le garder).
    func eraseEverything() throws {
        guard wallet.pendingSend == nil else { throw SettingsError.pendingPayment }
        try activity.erase()
        try store.erase()
        preferences.reset()
        wallet = LocalWallet()
        isFinishingOnboarding = false
    }

    /// Cartes connues de ce téléphone pour ce compte : compte affiché, autre compte ouvert, ou compte fermé.
    private static func knownCards(of account: String, in wallet: LocalWallet) -> [SavedCard] {
        wallet.knownAccount(account)?.cards ?? []
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
