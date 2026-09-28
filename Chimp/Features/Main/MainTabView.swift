import SwiftUI

/// Coque de l'app : onglets Wallet / Grow / Activity et barre d'onglets du design system.
/// Chaque onglet a sa propre pile de navigation pour les écrans à venir. La barre d'onglets
/// appartient à l'écran racine de chaque onglet : les écrans poussés la recouvrent
/// (DESIGN_NOTES §8.1 : les flux d'action s'ouvrent sans barre d'onglets).
struct MainTabView: View {
    @State private var selection = ChimpTab.wallet
    /// Gardé ici pour que les soldes restent chargés quand on change d'onglet.
    @State private var walletModel = WalletViewModel(dataSource: MockWalletDataSource())
    #if DESIGN_CATALOG
    @State private var isShowingCatalog = false
    #endif

    var body: some View {
        switch selection {
        case .wallet:
            NavigationStack {
                WalletView(model: walletModel, onSettings: settingsAction)
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                #if DESIGN_CATALOG
                    .navigationDestination(isPresented: $isShowingCatalog) {
                        DesignSystemCatalogView()
                    }
                #endif
            }
        case .grow, .activity:
            NavigationStack {
                PlaceholderTabView(tab: selection)
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
            }
        }
    }

    /// Roue dentée : en attendant les réglages (I2), elle ouvre le catalogue en Debug et Testing,
    /// et n'est pas affichée en Release.
    private var settingsAction: (() -> Void)? {
        #if DESIGN_CATALOG
        return { isShowingCatalog = true }
        #else
        return nil
        #endif
    }
}

/// Onglet pas encore construit (Grow, Activity) : en-tête seul.
struct PlaceholderTabView: View {
    let tab: ChimpTab

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: tab.title)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.chimpBackground))
    }
}

private extension View {
    /// Pose la barre d'onglets en bas de l'écran racine d'un onglet ; le contenu défilant en tient compte.
    func withTabBar(_ selection: Binding<ChimpTab>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpTabBar(selection: selection)
        }
    }
}

#Preview {
    MainTabView()
}
