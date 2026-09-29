import SwiftUI

/// Écran de départ : l'onboarding tant qu'aucun compte n'est ouvert sur ce téléphone, puis le Wallet.
struct RootView: View {
    let session: AppSession

    var body: some View {
        Group {
            if !session.showsOnboarding {
                MainTabView(session: session)
                    .transition(.opacity)
            } else {
                OnboardingFlow(model: .live(session: session))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.showsOnboarding)
        .environment(session)
    }
}
