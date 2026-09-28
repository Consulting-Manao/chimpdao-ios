#if DESIGN_CATALOG
import SwiftUI

/// Barre d'onglets montrée en vraie position, en bas de l'écran.
struct CatalogTabBarPage: View {
    let settings: CatalogSettings
    @State private var selection = ChimpTab.wallet

    var body: some View {
        CatalogPage("Tab bar", settings: settings, scrolls: false) {
            VStack(spacing: ChimpSpacing.l) {
                Spacer()
                Text(selection.title).chimpFont(.displayL)
                Text("Tap a tab. Each tab is at least 44 pt tall.")
                    .chimpFont(.body)
                    .foregroundStyle(.chimpTextSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChimpTabBar(selection: $selection)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CatalogTabBarPage(settings: CatalogSettings())
    }
}
#endif
