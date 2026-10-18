#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : Grow factice (F1 à F8), avec chaque état choisi d'avance. Les cartes, le tap et l'ordre
/// PIN / tap sont ceux de la page « Send ».
struct GrowCatalogPage: View {
    let settings: CatalogSettings
    @State private var scenario = MockVaultService.Scenario.normal
    @State private var resultScenario = MockSendService.ResultScenario.sent
    @State private var isShowingDemo = false

    var body: some View {
        CatalogPage("Grow", settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $scenario) {
                        ForEach(MockVaultService.Scenario.allCases) { scenario in
                            Text(verbatim: scenario.title).tag(scenario)
                        }
                    } label: {
                        Text("Vault").chimpFont(.rowTitle)
                    }
                    Picker(selection: $resultScenario) {
                        ForEach(MockSendService.ResultScenario.allCases) { scenario in
                            Text(verbatim: scenario.rawValue).tag(scenario)
                        }
                    } label: {
                        Text("Result").chimpFont(.rowTitle)
                    }
                } header: {
                    Text("Mock data")
                } footer: {
                    Text("Only for the Grow opened here. The Grow tab puts money in the real testnet vault.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Try it") {
                    Button {
                        isShowingDemo = true
                    } label: {
                        Text(verbatim: "Open Grow (F1)").chimpFont(.rowTitle)
                    }
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
        .fullScreenCover(isPresented: $isShowingDemo) {
            GrowDemoRoot(service: Self.service(scenario, result: resultScenario)) { isShowingDemo = false }
                .catalogOverrides(settings)
        }
    }

    static func service(_ scenario: MockVaultService.Scenario, result: MockSendService.ResultScenario = .sent) -> MockVaultService {
        let service = MockVaultService(scenario: scenario, cardSetup: SendMockSettings.cardSetup, resultScenario: result)
        service.send.tapScenario = SendMockSettings.tapScenario
        return service
    }
}

/// L'onglet Grow sur un service factice : F1, F2, F6, puis les parcours F3 / F7 et leurs issues.
struct GrowDemoRoot: View {
    let service: MockVaultService
    let onClose: () -> Void
    @State private var model: GrowModel
    @State private var path: [GrowRoute]

    let lendingService: MockLendingService

    init(
        service: MockVaultService, savings: MockSavingsService.Scenario = .normal, lending: MockLendingService.Scenario = .noPosition,
        start: [GrowRoute] = [], onClose: @escaping () -> Void
    ) {
        self.service = service
        self.onClose = onClose
        let lendingService = MockLendingService(scenario: lending, cardSetup: SendMockSettings.cardSetup)
        self.lendingService = lendingService
        _model = State(initialValue: GrowModel(
            service: service, savingsService: MockSavingsService(scenario: savings), lendingService: lendingService,
            priceOracle: MockPriceOracle(), history: MemoryPotHistoryStore()
        ))
        _path = State(initialValue: start)
    }

    var body: some View {
        NavigationStack(path: $path) {
            GrowView(model: model) { path.append($0) }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChimpButton("Close the demo", kind: .link, action: onClose).padding(ChimpSpacing.bottomBar)
                }
                .navigationDestination(for: GrowRoute.self) { route in
                    destination(route).toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: GrowRoute) -> some View {
        switch route {
        case .pot(let mark, let address):
            switch mark {
            case .defindex:
                VaultPositionView(
                    model: model, drawerAddress: address, onBack: pop,
                    onWithdraw: { path.append(.withdraw(drawerID: $0)) }, onDeposit: { path.append(.deposit(drawerID: $0)) }
                )
            case .xoxno:
                if let lending = model.lending {
                    LendingPositionView(
                        model: lending, drawerAddress: address, onBack: pop,
                        onWithdraw: { path.append(.lendingWithdraw(drawerID: $0)) }, onDeposit: { path.append(.lendingDeposit(drawerID: $0)) }
                    )
                }
            case .etherfuse:
                SavingsView(model: model, drawerAddress: address, onBack: pop) { path.append(.swap($0)) }
            }
        case .vault:
            VaultInfoView(model: model, onBack: pop) { path.append(.deposit(drawerID: nil)) }
        case .position(let address):
            VaultPositionView(
                model: model, drawerAddress: address, onBack: pop,
                onWithdraw: { path.append(.withdraw(drawerID: $0)) }, onDeposit: { path.append(.deposit(drawerID: $0)) }
            )
        case .deposit(let drawerID):
            VaultFlowRoot(service: service, action: .deposit, drawerID: drawerID, onSeePosition: showPosition, onExit: pop)
        case .withdraw(let drawerID):
            VaultFlowRoot(service: service, action: .withdraw, drawerID: drawerID, onSeePosition: showPosition, onExit: pop)
        case .savings(let address):
            SavingsView(model: model, drawerAddress: address, onBack: pop) { path.append(.swap($0)) }
        case .swap(let prefill):
            SwapFlowRoot(service: MockSwapService(), prefill: prefill, onExit: pop)
        case .lending:
            if let lending = model.lending {
                LendingInfoView(model: lending, onBack: pop) { path.append(.lendingDeposit(drawerID: nil)) }
            }
        case .lendingPosition(let address):
            if let lending = model.lending {
                LendingPositionView(
                    model: lending, drawerAddress: address, onBack: pop,
                    onWithdraw: { path.append(.lendingWithdraw(drawerID: $0)) }, onDeposit: { path.append(.lendingDeposit(drawerID: $0)) }
                )
            }
        case .lendingDeposit(let drawerID):
            VaultFlowRoot(service: lendingService, action: .deposit, drawerID: drawerID, onSeePosition: { path = [.lendingPosition(drawerAddress: $0)] }, onExit: pop)
        case .lendingWithdraw(let drawerID):
            VaultFlowRoot(service: lendingService, action: .withdraw, drawerID: drawerID, onSeePosition: { path = [.lendingPosition(drawerAddress: $0)] }, onExit: pop)
        }
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    private func showPosition(_ address: String) {
        path = [.position(drawerAddress: address)]
    }
}

/// Lancement direct de Grow factice (Debug et Testing), pour les captures et les essais :
/// `xcrun simctl launch <appareil> com.consulting-manao.chimp -vaultDemo lentOut` (un scénario du vault ; suffixes
/// `:deposit`, `:withdraw`, `:vault`, `:position` ou `:savings` pour ouvrir directement cet écran). Les CETES :
/// `-savingsDemo frozen` (un scénario de `MockSavingsService`). Sans l'argument : rien.
struct VaultDemoLaunch: ViewModifier {
    @State private var argument = UserDefaults.standard.string(forKey: "vaultDemo") ?? UserDefaults.standard.string(forKey: "lendingDemo").map { _ in "normal" }
    /// Prêt XOXNO (phase 7) : `-lendingDemo lentOut` (un scénario de `MockLendingService`) ; suffixes `:lending`,
    /// `:lendingPosition`, `:lendingDeposit`, `:lendingWithdraw` pour ouvrir directement cet écran.
    private let lending = UserDefaults.standard.string(forKey: "lendingDemo")
    private let savings = UserDefaults.standard.string(forKey: "savingsDemo").flatMap(MockSavingsService.Scenario.init(rawValue:)) ?? .normal

    func body(content: Content) -> some View {
        content.overlay {
            if argument != nil {
                let parts = (argument ?? "normal").split(separator: ":").map(String.init)
                let scenario = MockVaultService.Scenario(rawValue: parts.first ?? "normal") ?? .normal
                let lendingParts = (lending ?? "noPosition").split(separator: ":").map(String.init)
                let lendingScenario = MockLendingService.Scenario(rawValue: lendingParts.first ?? "noPosition") ?? .noPosition
                GrowDemoRoot(
                    service: GrowCatalogPage.service(scenario), savings: savings, lending: lendingScenario,
                    start: Self.start(lending == nil ? parts.dropFirst().first : lendingParts.dropFirst().first)
                ) {
                    argument = nil
                }
                    .background(Color(.chimpBackground))
            }
        }
    }

    private static func start(_ screen: String?) -> [GrowRoute] {
        switch screen {
        case "deposit": [.deposit(drawerID: nil)]
        case "withdraw": [.withdraw(drawerID: "main")]
        case "vault": [.vault]
        case "position": [.position(drawerAddress: MockReceiveDataSource.mainAddress)]
        case "savings": [.savings(drawerAddress: MockReceiveDataSource.mainAddress)]
        case "lending": [.lending]
        case "lendingPosition": [.lendingPosition(drawerAddress: MockReceiveDataSource.mainAddress)]
        case "lendingDeposit": [.lendingDeposit(drawerID: nil)]
        case "lendingWithdraw": [.lendingWithdraw(drawerID: "main")]
        default: []
        }
    }
}

private extension MockVaultService.Scenario {
    var title: String {
        switch self {
        case .normal: "A position in Main"
        case .noPosition: "Nothing growing yet"
        case .vaultUnavailable: "DeFindex isn't answering"
        case .priceMovesBeforeSigning: "The vault moves before signing"
        case .implausible: "Implausible value (blocked)"
        case .lentOut: "Lent out on Blend: 30 XLM available"
        }
    }
}
#endif
