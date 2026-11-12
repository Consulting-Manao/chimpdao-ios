#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug) : « Somebody likes you! » avec un faux contrat `prize` (aucun réseau), chaque issue choisie d'avance.
struct PrizeCatalogPage: View {
    let settings: CatalogSettings
    @State private var scenario = Scenario.sent
    @State private var isShowingDemo = false

    enum Scenario: String, CaseIterable, Identifiable {
        case sent = "Opened"
        case changed = "Amount changed"
        case alreadyOpened = "Already opened"
        case notOwner = "Not the owner"
        case waiting = "Not moved (signature still valid)"
        case nothing = "Nothing was moved"
        case unsure = "Not sure yet"

        var id: String { rawValue }

        var mock: MockPrizeService.Scenario {
            switch self {
            case .sent: .success
            case .changed: .amountChanged(320)
            case .alreadyOpened: .amountChanged(0)
            case .notOwner: .notOwner
            case .waiting: .unanswered(.waiting(untilLedger: 1_120, estimatedEnd: .now.addingTimeInterval(90)))
            case .nothing: .unanswered(.nothingSent)
            case .unsure: .unanswered(.undetermined("RPC history too short"))
            }
        }
    }

    var body: some View {
        CatalogPage("Partner card", settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $scenario) {
                        ForEach(Scenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text("Result").chimpFont(.rowTitle)
                    }
                } header: {
                    Text("Mock prize contract")
                } footer: {
                    Text("No network. The real screen opens from the Wallet when a card of the account has money reserved.")
                }
                .listRowBackground(Color(.chimpSurface))
                Section("Try it") {
                    Button { isShowingDemo = true } label: {
                        Text(verbatim: "Somebody likes you! (H1)").chimpFont(.rowTitle)
                    }
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
        .fullScreenCover(isPresented: $isShowingDemo) {
            NavigationStack {
                PrizeClaimRoot(service: MockPrizeService(scenario: scenario.mock), gift: MockPrizeService.banana) {
                    isShowingDemo = false
                }
            }
            .catalogOverrides(settings)
        }
    }
}
#endif
