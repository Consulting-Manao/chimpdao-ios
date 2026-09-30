#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : le vrai onglet Activity dans chaque état, avec les données factices.
struct ActivityStatesCatalogPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Activity states", settings: settings, scrolls: false) {
            List(MockActivityDataSource.Scenario.allCases) { scenario in
                NavigationLink {
                    ActivityStateDemo(scenario: scenario, settings: settings)
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

/// L'onglet en plein écran (son en-tête passe sous la barre d'état), avec un bouton pour revenir à la liste.
private struct ActivityStateDemo: View {
    let scenario: MockActivityDataSource.Scenario
    let settings: CatalogSettings
    @State private var model: ActivityViewModel
    @Environment(\.dismiss) private var dismiss

    init(scenario: MockActivityDataSource.Scenario, settings: CatalogSettings) {
        self.scenario = scenario
        self.settings = settings
        _model = State(initialValue: ActivityViewModel(source: MockActivityDataSource(scenario: scenario)))
    }

    var body: some View {
        ActivityView(model: model)
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

private extension MockActivityDataSource.Scenario {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Mockup"
        case .pending: "Payment waiting"
        case .mixedAssets: "XLM and USDC the same day"
        case .empty: "Empty"
        case .loadingForever: "Loading"
        case .networkError: "Network error"
        case .staleAfterRefresh: "Refresh failed"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .standard: "Today, yesterday and older: paid, got, moved, new card"
        case .pending: "A signed payment not confirmed yet, on top"
        case .mixedAssets: "Day total per asset"
        case .empty: "Nothing moved yet"
        case .loadingForever: "First read that never ends"
        case .networkError: "Nothing kept, Stellar unreachable"
        case .staleAfterRefresh: "Kept lines, refresh fails"
        }
    }
}
#endif
