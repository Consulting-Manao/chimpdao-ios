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
#endif
