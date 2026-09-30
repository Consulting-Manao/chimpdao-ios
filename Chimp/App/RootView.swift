import SwiftUI

/// Écran de départ : l'onboarding tant qu'aucun compte n'est ouvert sur ce téléphone, puis le Wallet.
struct RootView: View {
    let session: AppSession

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
        .environment(session)
    }
}
