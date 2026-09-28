#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : le vrai écran Recevoir dans chaque état, avec les données factices.
struct ReceiveStatesCatalogPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Receive states", settings: settings, scrolls: false) {
            List(ReceiveStateDemo.allCases) { demo in
                NavigationLink {
                    ReceiveStateDemoView(demo: demo, settings: settings)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(demo.title).chimpFont(.rowTitle)
                        Text(demo.detail).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    }
                    .foregroundStyle(.chimpTextPrimary)
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// Un état à montrer : un scénario du mock, et éventuellement le tiroir choisi à l'ouverture.
private enum ReceiveStateDemo: String, CaseIterable, Identifiable {
    case standard, cardSelected, mainOnly, mainnet, loading, networkError

    var id: String { rawValue }

    var scenario: MockReceiveDataSource.Scenario {
        switch self {
        case .standard, .cardSelected: .standard
        case .mainOnly: .mainOnly
        case .mainnet: .mainnet
        case .loading: .loadingForever
        case .networkError: .networkError
        }
    }

    var initialDrawerID: String? {
        self == .cardSelected ? "0421" : nil
    }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Mockup"
        case .cardSelected: "Card's wallet chosen"
        case .mainOnly: "Main only"
        case .mainnet: "Mainnet"
        case .loading: "Loading"
        case .networkError: "Network error"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .standard: "Into Main, Testnet badge, tap Copy for the copied state."
        case .cardSelected: "Opens on Jungle's wallet, with the only-this-card notice."
        case .mainOnly: "No choice: no arrow on the picker."
        case .mainnet: "No Testnet badge, warning says Stellar."
        case .loading: "Skeleton that never finishes."
        case .networkError: "Addresses can't be loaded."
        }
    }
}

/// L'écran en plein écran, avec son propre bouton retour.
private struct ReceiveStateDemoView: View {
    let settings: CatalogSettings
    @State private var model: ReceiveViewModel
    @Environment(\.dismiss) private var dismiss

    init(demo: ReceiveStateDemo, settings: CatalogSettings) {
        self.settings = settings
        _model = State(initialValue: ReceiveViewModel(
            dataSource: MockReceiveDataSource(scenario: demo.scenario),
            initialDrawerID: demo.initialDrawerID
        ))
    }

    var body: some View {
        ReceiveView(model: model, onBack: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
            .catalogOverrides(settings)
    }
}
#endif
