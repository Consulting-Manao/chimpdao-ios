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
    private let store: LocalWalletStore

    init(store: LocalWalletStore, network: StellarNetwork) {
        self.store = store
        self.network = network
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
            return AppSession(store: try FileLocalWalletStore(network: network), network: network)
        } catch {
            // Application Support inaccessible : l'app fonctionne, mais sans rien retenir.
            let session = AppSession(store: InMemoryLocalWalletStore(), network: network)
            session.loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return session
        }
    }

    var hasAccount: Bool { wallet.account != nil }

    /// La visite guidée a été vue ou passée. Si l'écriture échoue, elle sera simplement proposée à nouveau.
    func markTourSeen() {
        guard !wallet.tourSeen else { return }
        var next = wallet
        next.tourSeen = true
        try? persist(next)
        wallet.tourSeen = true
    }

    /// Carte déjà membre d'un Main account (`signIn` de la résolution) : on ouvre ce compte sur le téléphone.
    /// Comme le terminal : une simple lecture suffit, rien n'est signé. L'indice « carte → compte » est mis à jour.
    func signIn(account: String, card: SavedCard, at date: Date = .now) throws {
        var next = wallet
        var cards = next.account?.address == account ? next.account?.cards ?? [] : []
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
