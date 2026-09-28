import SwiftUI

/// Entrée du parcours Envoyer, poussée dans une pile de navigation (depuis le Wallet ou le catalogue).
/// Un ViewModel neuf à chaque ouverture, gardé tant que le parcours est affiché. Les écrans suivants
/// (C2, C4…) sont poussés par le ViewModel (`navigationDestination(isPresented:)`), ce qui marche
/// dans n'importe quelle pile.
struct SendFlowRoot: View {
    @State private var model: SendFlowModel
    let onExit: () -> Void

    init(service: SendService = SendMockSettings.makeService(), onExit: @escaping () -> Void) {
        _model = State(initialValue: SendFlowModel(service: service))
        self.onExit = onExit
    }

    var body: some View {
        SendRecipientView(model: model, onBack: onExit)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Réglages du service factice, choisis dans le catalogue (page « Send », Debug et Testing).
/// En Release, le parcours utilise les données de la maquette.
enum SendMockSettings {
    static let dataScenarioKey = "sendMockDataScenario"

    static var dataScenario: MockSendService.DataScenario {
        get {
            #if DESIGN_CATALOG
            UserDefaults.standard.string(forKey: dataScenarioKey).flatMap(MockSendService.DataScenario.init(rawValue:)) ?? .standard
            #else
            .standard
            #endif
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dataScenarioKey) }
    }

    static func makeService() -> SendService {
        MockSendService(dataScenario: dataScenario)
    }
}
