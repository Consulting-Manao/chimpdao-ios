#if DESIGN_CATALOG
import SwiftUI

/// Lancement direct de N1 sur des devis factices (Debug et Testing) :
/// `xcrun simctl launch <appareil> com.consulting-manao.chimp -crossChainDemo normal` (`pairUnavailable`, `offline`).
struct CrossChainDemoLaunch: ViewModifier {
    @State private var scenario = UserDefaults.standard.string(forKey: "crossChainDemo").flatMap(MockOneClick.Scenario.init(rawValue:))

    func body(content: Content) -> some View {
        content.overlay {
            if let scenario {
                NavigationStack {
                    CrossChainQuoteView(
                        model: CrossChainQuoteModel(client: MockOneClick(scenario: scenario), recipient: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2")
                    ) { self.scenario = nil }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}

/// Lancement direct de N2 sur des commandes factices (Debug et Testing) :
/// `xcrun simctl launch <appareil> com.consulting-manao.chimp -rozoDemo normal` (`bounced`, `expired`, `offline`, `mismatch`).
/// La commande avance d'un état toutes les deux secondes.
struct RozoDemoLaunch: ViewModifier {
    @State private var scenario = UserDefaults.standard.string(forKey: "rozoDemo").flatMap(MockRozo.Scenario.init(rawValue:))

    func body(content: Content) -> some View {
        content.overlay {
            if let scenario {
                NavigationStack {
                    RozoTransferView(
                        model: RozoTransferModel(
                            client: MockRozo(scenario: scenario), config: IntegrationConfig.testnet.rozo,
                            recipient: "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP", pollInterval: .seconds(2)
                        ),
                        explorerURL: ChimpNetworkConfig.testnet.explorerURL(transactionHash:),
                        onBack: { self.scenario = nil }, onDone: { self.scenario = nil }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}
#endif
