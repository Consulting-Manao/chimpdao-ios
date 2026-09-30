import SwiftUI

/// Entrée du parcours Envoyer, poussée dans une pile de navigation (depuis le Wallet ou le catalogue).
/// Un ViewModel neuf à chaque ouverture, gardé tant que le parcours est affiché. Les écrans suivants
/// (C2, C4…) sont poussés par le ViewModel (`navigationDestination(isPresented:)`), ce qui marche
/// dans n'importe quelle pile.
struct SendFlowRoot: View {
    @State private var model: SendFlowModel
    let onExit: () -> Void

    init(
        service: SendService = SendMockSettings.makeService(),
        signingOrder: SigningOrder = SendMockSettings.signingOrder,
        kind: SendFlowModel.FlowKind = .send,
        prefilledAddress: String? = nil,
        fromDrawerID: String? = nil,
        onExit: @escaping () -> Void
    ) {
        let model = SendFlowModel(service: service, signingOrder: signingOrder, kind: kind, initialDrawerID: fromDrawerID)
        model.onExit = onExit
        // « Pay again » (reçu de l'Activity) : l'adresse est collée en C1, comme si on l'avait collée ; tout le reste
        // (montant, tiroir, vérification, carte) se fait comme pour un nouvel envoi.
        if let prefilledAddress { model.pasteAddress(prefilledAddress) }
        _model = State(initialValue: model)
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if model.resumedPending {
                // Un paiement signé attend encore son issue : son état, jamais un nouvel envoi.
                SendStatusView(model: model)
            } else if model.isMove {
                // E1 : le Move commence directement par les tiroirs et le montant.
                SendAmountView(model: model, onBack: onExit)
                    .task { await model.loadIfNeeded() }
            } else {
                SendRecipientView(model: model, onBack: onExit)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Réglages du parcours, choisis dans le catalogue (page « Send », Debug et Testing) : l'ordre PIN / tap vaut aussi pour
/// le vrai envoi ; les données, les cartes et l'issue seulement pour le parcours factice du catalogue.
/// En Release : ordre « PIN puis tap ».
enum SendMockSettings {
    static let dataScenarioKey = "sendMockDataScenario"
    static let cardSetupKey = "sendMockCardSetup"
    static let signingOrderKey = "sendSigningOrder"
    static let resultScenarioKey = "sendMockResultScenario"
    static let tapScenarioKey = "sendMockTapScenario"

    static var dataScenario: MockSendService.DataScenario {
        #if DESIGN_CATALOG
        stored(dataScenarioKey) ?? .standard
        #else
        .standard
        #endif
    }

    static var cardSetup: MockSendService.CardSetup {
        #if DESIGN_CATALOG
        stored(cardSetupKey) ?? .allWithPin
        #else
        .allWithPin
        #endif
    }

    /// Ordre PIN / tap. TODO(ordre PIN / tap) : figé en Release sur « PIN puis tap » tant que Barth n'a pas
    /// tranché après le test avec une vraie carte (DESIGN_NOTES §12, question 1).
    static var signingOrder: SigningOrder {
        #if DESIGN_CATALOG
        stored(signingOrderKey) ?? .pinThenTap
        #else
        .pinThenTap
        #endif
    }

    static var resultScenario: MockSendService.ResultScenario {
        #if DESIGN_CATALOG
        stored(resultScenarioKey) ?? .sent
        #else
        .sent
        #endif
    }

    static var tapScenario: MockSendService.TapScenario {
        #if DESIGN_CATALOG
        stored(tapScenarioKey) ?? .rightCard
        #else
        .rightCard
        #endif
    }

    /// Parcours factice du catalogue (données, cartes, carte tapée et issue choisies dans la page « Send »).
    static func makeService() -> SendService {
        let service = MockSendService(dataScenario: dataScenario, cardSetup: cardSetup, resultScenario: resultScenario)
        service.tapScenario = tapScenario
        return service
    }

    private static func stored<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:))
    }
}
