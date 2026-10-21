#if CHIMP_ADMIN_APP
import CoreNFC
import SwiftUI

/// Chimp Admin (configuration Admin) : l'app de l'équipe pour les cartes, sans aucun écran du wallet (demande de Barth du
/// 2026-10-21). Trois onglets : Cards (« Prepare cards »), Tools (clé admin, argent de test, enregistrement manuel,
/// durée de vie du vault), Design (le catalogue). Verrouillée par Face ID à chaque ouverture, comme avant.
struct AdminAppRoot: View {
    let session: AppSession
    let lock: AppLock
    /// Partagé par Cards et Tools : une clé admin enregistrée dans Tools est vue aussitôt par Cards.
    @State private var keyModel = AdminKeyModel(store: KeychainAdminKeyStore(network: .testnet))
    @State private var prepareCards = PrepareCardsView.live()

    var body: some View {
        TabView {
            NavigationStack { cards }
                .tabItem { Label { Text(verbatim: "Cards") } icon: { Image(systemName: "creditcard.fill") } }
            NavigationStack { AdminView(keyModel: keyModel, showsPrepareCards: false) }
                .tabItem { Label { Text(verbatim: "Tools") } icon: { Image(systemName: "wrench.and.screwdriver.fill") } }
            NavigationStack { DesignSystemCatalogView() }
                .tabItem { Label { Text(verbatim: "Design") } icon: { Image(systemName: "paintpalette.fill") } }
        }
        .tint(Color(.chimpTextPrimary))
        .chimpWindowStyle(session.preferences.look.interfaceStyle)
        .chimpAppLock(lock, style: session.preferences.look.interfaceStyle)
        .environment(session)
        .environment(lock)
    }

    @ViewBuilder
    private var cards: some View {
        if let prepareCards {
            PrepareCardsView(model: prepareCards, hasAdminKey: keyModel.hasKey || Self.isSimulator)
        } else {
            ChimpNoticeBanner(text: untranslated("The card journal couldn't be opened on this iPhone."), marker: .error)
                .padding(ChimpSpacing.screenMargin)
        }
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
#endif
