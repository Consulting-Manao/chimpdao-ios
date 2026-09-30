import SwiftUI

/// Écran de départ : l'onboarding tant qu'aucun compte n'est ouvert sur ce téléphone, puis le Wallet.
struct RootView: View {
    let session: AppSession
    let lock: AppLock

    var body: some View {
        Group {
            if !session.showsOnboarding {
                // Un écran principal par compte : changer de compte (I6) le reconstruit, avec ses soldes et son historique.
                MainTabView(session: session)
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
        .environment(session)
        .environment(lock)
    }
}
