#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : le parcours Swap factice, avec chaque état des maquettes (E3a à E3f, E4i, E4p, E5,
/// E6, attente, rien n'est parti). Les cartes, le tap et l'ordre PIN / tap sont ceux de la page « Send ».
struct SwapCatalogPage: View {
    let settings: CatalogSettings
    @State private var quoteScenario = MockSwapService.QuoteScenario.normal
    @State private var resultScenario = MockSendService.ResultScenario.sent
    @State private var dataScenario = MockSendService.DataScenario.standard
    @State private var pendingPayment = false
    @State private var isShowingDemo = false

    var body: some View {
        CatalogPage("Swap", settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $quoteScenario) {
                        ForEach(MockSwapService.QuoteScenario.allCases) { scenario in
                            Text(verbatim: scenario.title).tag(scenario)
                        }
                    } label: {
                        Text("Quote").chimpFont(.rowTitle)
                    }
                    Picker(selection: $resultScenario) {
                        ForEach(MockSendService.ResultScenario.allCases) { scenario in
                            Text(verbatim: scenario.rawValue).tag(scenario)
                        }
                    } label: {
                        Text("Result").chimpFont(.rowTitle)
                    }
                    Picker(selection: $dataScenario) {
                        ForEach(MockSendService.DataScenario.allCases) { scenario in
                            Text(verbatim: scenario.rawValue).tag(scenario)
                        }
                    } label: {
                        Text("Balances").chimpFont(.rowTitle)
                    }
                    Toggle(isOn: $pendingPayment) {
                        Text("A payment is still pending (E3f)").chimpFont(.rowTitle)
                    }
                } header: {
                    Text("Mock data")
                } footer: {
                    Text("Only for the flow opened here. The Swap tile of the Wallet swaps for real on testnet.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Try it") {
                    Button {
                        isShowingDemo = true
                    } label: {
                        Text(verbatim: "Open Swap (E3)").chimpFont(.rowTitle)
                    }
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationDestination(isPresented: $isShowingDemo) {
            SwapFlowRoot(service: makeService()) { isShowingDemo = false }
                .catalogOverrides(settings)
        }
    }

    private func makeService() -> SwapService {
        let service = MockSwapService(
            quoteScenario: quoteScenario, dataScenario: dataScenario, cardSetup: SendMockSettings.cardSetup,
            resultScenario: resultScenario
        )
        service.send.tapScenario = SendMockSettings.tapScenario
        if pendingPayment {
            service.pendingSend = PendingSend(
                trace: PaymentTrace(
                    token: "mock", from: MockReceiveDataSource.mainAddress, destination: MockSendService.mayaAddress, units: 1, nonce: 1,
                    preparedAtLedger: 1, expirationLedger: 121
                ),
                recipient: MockSendService.mayaAddress, recipientName: "Maya", drawerTitle: String(localized: "Main account"),
                asset: SendAsset.usdc.rawValue, amount: 25, signedAt: .now
            )
        }
        return service
    }
}

/// Lancement direct du swap factice (Debug et Testing), pour les captures et les essais :
/// `xcrun simctl launch <appareil> com.consulting-manao.chimp -swapDemo bigImpact` (un scénario de devis, ou `pending`
/// pour E3f). Sans l'argument : rien.
struct SwapDemoLaunch: ViewModifier {
    @State private var scenario = UserDefaults.standard.string(forKey: "swapDemo")

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { scenario != nil }, set: { if !$0 { scenario = nil } })) {
            NavigationStack {
                SwapFlowRoot(service: Self.service(scenario ?? "normal")) { scenario = nil }
            }
        }
    }

    static func service(_ scenario: String) -> SwapService {
        let service = MockSwapService(quoteScenario: MockSwapService.QuoteScenario(rawValue: scenario) ?? .normal)
        if scenario == "pending" {
            service.pendingSend = PendingSend(
                trace: PaymentTrace(
                    token: "mock", from: MockReceiveDataSource.mainAddress, destination: MockSendService.mayaAddress, units: 1, nonce: 1,
                    preparedAtLedger: 1, expirationLedger: 121
                ),
                recipient: MockSendService.mayaAddress, recipientName: "Maya", drawerTitle: String(localized: "Main account"),
                asset: SendAsset.usdc.rawValue, amount: 25, signedAt: .now
            )
        }
        return service
    }
}

private extension MockSwapService.QuoteScenario {
    var title: String {
        switch self {
        case .normal: "Normal (1 XLM ≈ 0.2492 USDC)"
        case .noRoute: "No route (E3b)"
        case .protocolUnavailable: "Both protocols are down (E3c)"
        case .bigImpact: "Price impact 8.12% (E3e, E4i)"
        case .priceMovesBeforeSigning: "Price moves before signing (E4p)"
        case .aquariusBest: "Best price from Aquarius"
        case .soroswapDown: "Soroswap is down, Aquarius answers"
        case .implausible: "Implausible quote (blocked)"
        }
    }
}
#endif
