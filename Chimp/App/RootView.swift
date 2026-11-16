import SwiftUI

/// Écran de départ : l'onboarding tant qu'aucun compte n'est ouvert sur ce téléphone, puis le Wallet.
struct RootView: View {
    let session: AppSession
    let lock: AppLock
    /// Les dessins imprimés des cartes (NFT). Ici et pas dans les onglets : l'onboarding et la reconnexion nomment des
    /// cartes eux aussi, et changer de compte ne doit pas faire tout relire.
    @State private var cardArt: CardArtStore

    init(session: AppSession, lock: AppLock) {
        self.session = session
        self.lock = lock
        _cardArt = State(initialValue: CardArtStore(reader: ChainCardArtReader(config: session.config)))
    }

    var body: some View {
        Group {
            if !session.showsOnboarding {
                // Un écran principal par compte : changer de compte (I6) le reconstruit, avec ses soldes et son historique.
                MainTabView(session: session, cardArt: cardArt)
                    .id(session.wallet.account?.address)
                    .transition(.opacity)
            } else {
                OnboardingFlow(model: .live(session: session))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.showsOnboarding)
        .chimpWindowStyle(session.preferences.look.interfaceStyle)
        .chimpAppLock(lock, style: session.preferences.look.interfaceStyle)
        // Arrivée sur un autre compte (ou plus de compte) : Face ID si ce compte l'a activé, aucun verrou sinon.
        .onChange(of: session.wallet.account?.address) {
            Task { await lock.accountDidChange() }
        }
        // Testnet (Chimp Test, Chimp Dev) : au premier lancement, une fenêtre à valider. Jamais sur le mainnet.
        .alert(TestnetNotice.title, isPresented: Binding(
            get: { session.network == .testnet && !session.preferences.hasAcceptedTestnetNotice },
            set: { _ in }
        )) {
            Button(TestnetNotice.accept) { session.preferences.hasAcceptedTestnetNotice = true }
        } message: {
            Text(TestnetNotice.message)
        }
        .environment(\.chimpCardArt) { [cardArt] key in cardArt.art(forKey: key) }
        .environment(\.chimpCardArtStore, cardArt)
        .environment(session)
        .environment(lock)
    }
}
