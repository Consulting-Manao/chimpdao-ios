#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : le vrai écran Wallet dans chaque état, avec les données factices.
struct WalletStatesCatalogPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Wallet states", settings: settings, scrolls: false) {
            List(MockWalletDataSource.Scenario.allCases) { scenario in
                NavigationLink {
                    WalletStateDemo(scenario: scenario, settings: settings)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenario.title).chimpFont(.rowTitle)
                        Text(scenario.detail).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    }
                    .foregroundStyle(.chimpTextPrimary)
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// Le Wallet en plein écran (son en-tête passe sous la barre d'état), avec un bouton pour revenir à la liste.
private struct WalletStateDemo: View {
    let scenario: MockWalletDataSource.Scenario
    let settings: CatalogSettings
    @State private var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    init(scenario: MockWalletDataSource.Scenario, settings: CatalogSettings) {
        self.scenario = scenario
        self.settings = settings
        _model = State(initialValue: WalletViewModel(dataSource: MockWalletDataSource(scenario: scenario)))
    }

    var body: some View {
        WalletView(model: model)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChimpButton("Back to states", kind: .secondary) { dismiss() }
                    .padding(.horizontal, ChimpSpacing.screenMargin)
                    .padding(.vertical, ChimpSpacing.s)
                    .background(Color(.chimpBackground))
            }
            .toolbar(.hidden, for: .navigationBar)
            .catalogOverrides(settings)
    }
}

private extension MockWalletDataSource.Scenario {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Mockup"
        case .withoutSavings: "Without savings"
        case .minimal: "No first name, no weekly change"
        case .zeroBalance: "Zero balance"
        case .noCards: "No cards"
        case .loadingForever: "Loading"
        case .networkError: "Network error"
        case .staleAfterRefresh: "Refresh fails"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .standard: "Main $1,320 with $500 growing, two cards."
        case .withoutSavings: "Same total, everything ready to spend."
        case .minimal: "Greeting adapts, weekly line hidden."
        case .zeroBalance: "Only Receive is available."
        case .noCards: "Safety net: should never happen."
        case .loadingForever: "Skeleton that never finishes."
        case .networkError: "First load fails."
        case .staleAfterRefresh: "Loads, then pull to refresh to see the banner."
        }
    }
}
#endif
