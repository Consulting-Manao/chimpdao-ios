#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : la vraie page d'un tiroir (B1) sur les données factices du Wallet et de Grow.
struct DrawerCatalogPage: View {
    let settings: CatalogSettings

    private enum Demo: String, CaseIterable, Identifiable {
        case main, jungle, banana, empty
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .main: "Main · $500 growing"
            case .jungle: "Jungle card"
            case .banana: "Banana card"
            case .empty: "Main · empty"
            }
        }

        var selection: DrawerSelection {
            switch self {
            case .main, .empty: .main
            case .jungle: .card("jungle")
            case .banana: .card("banana")
            }
        }
    }

    var body: some View {
        CatalogPage("Drawer page (B1)", settings: settings, scrolls: false) {
            List(Demo.allCases) { demo in
                NavigationLink {
                    DrawerDemo(selection: demo.selection, scenario: demo == .empty ? .zeroBalance : .standard, settings: settings)
                } label: {
                    Text(demo.title).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct DrawerDemo: View {
    let settings: CatalogSettings
    @State private var model: DrawerDetailModel
    @State private var grow: GrowModel
    @Environment(\.dismiss) private var dismiss

    init(selection: DrawerSelection, scenario: MockWalletDataSource.Scenario, settings: CatalogSettings) {
        self.settings = settings
        let session = AppSession(
            store: InMemoryLocalWalletStore(LocalWallet(
                firstName: "Léo", tourSeen: true, account: SavedAccount(address: MockReceiveDataSource.mainAddress, cards: [])
            )),
            config: .testnet
        )
        let wallet = WalletViewModel(dataSource: MockWalletDataSource(scenario: scenario))
        _model = State(initialValue: DrawerDetailModel(selection: selection, wallet: wallet, session: session))
        _grow = State(initialValue: GrowModel(
            service: MockVaultService(scenario: scenario == .zeroBalance ? .noPosition : .normal),
            savingsService: MockSavingsService(scenario: .normal),
            lendingService: MockLendingService(scenario: .noPosition, cardSetup: SendMockSettings.cardSetup),
            sentoraService: MockLendingService(scenario: .noPosition, cardSetup: SendMockSettings.cardSetup, mark: .sentora),
            priceOracle: MockPriceOracle(), history: MemoryPotHistoryStore(), rateReader: MockGrowRates()
        ))
    }

    var body: some View {
        DrawerDetailView(model: model, actions: DrawerDetailActions(onBack: { dismiss() }), grow: grow)
            .task { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .catalogOverrides(settings)
    }
}
#endif
