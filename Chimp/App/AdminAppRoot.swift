#if CHIMP_ADMIN_APP
import SwiftUI

/// Chimp Admin (configuration Admin) : l'app de l'équipe pour les cartes, par tâche et en langage simple (demande de
/// Barth du 2026-10-22). Sans clé : « Set up Chimp Admin ». Avec la clé : la ligne d'état en haut et les onglets.
/// Aucun écran du wallet, pas de catalogue (il reste dans Chimp Dev). Verrouillée par Face ID à chaque ouverture.
struct AdminAppRoot: View {
    let session: AppSession
    let lock: AppLock
    @State private var admin = AdminSession.live()
    @State private var prepareCards = PrepareCardsView.live()

    var body: some View {
        Group {
            if admin.hasKey {
                VStack(spacing: 0) {
                    AdminStatusLine(session: admin)
                    TabView {
                        NavigationStack { cards }
                            .tabItem { Label { Text(verbatim: "Cards") } icon: { Image(systemName: "creditcard.fill") } }
                    }
                    .tint(Color(.chimpTextPrimary))
                }
                .background(Color(.chimpSurfaceSecondary))
                .onAppear { admin.refreshBalance() }
            } else {
                AdminSetupView(session: admin)
            }
        }
        .chimpWindowStyle(session.preferences.look.interfaceStyle)
        .chimpAppLock(lock, style: session.preferences.look.interfaceStyle)
        .environment(session)
        .environment(lock)
    }

    @ViewBuilder
    private var cards: some View {
        if let prepareCards {
            PrepareCardsView(model: prepareCards, hasAdminKey: admin.hasKey)
                // L'argent de départ part de l'admin : son solde change.
                .onChange(of: prepareCards.cards) { admin.refreshBalance() }
        } else {
            ChimpNoticeBanner(text: untranslated("The list of cards couldn't be opened on this iPhone."), marker: .error)
                .padding(ChimpSpacing.screenMargin)
        }
    }
}
#endif
