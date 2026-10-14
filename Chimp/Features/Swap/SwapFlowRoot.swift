import SwiftUI

/// Entrée du parcours Swap, poussée dans une pile de navigation (Wallet, page d'un tiroir, reçu, catalogue).
/// Un ViewModel neuf à chaque ouverture, gardé tant que le parcours est affiché ; la vérification est poussée par le
/// ViewModel (`navigationDestination(isPresented:)`), comme Envoyer.
struct SwapFlowRoot: View {
    @State private var model: SwapFlowModel
    let onExit: () -> Void
    private let service: SwapService
    private let signingOrder: SigningOrder

    init(
        service: SwapService,
        signingOrder: SigningOrder = SendMockSettings.signingOrder,
        fromDrawerID: String? = nil,
        prefill: SwapPrefill? = nil,
        onExit: @escaping () -> Void
    ) {
        let model = SwapFlowModel(service: service, signingOrder: signingOrder, initialDrawerID: fromDrawerID, prefill: prefill)
        model.onExit = onExit
        _model = State(initialValue: model)
        self.onExit = onExit
        self.service = service
        self.signingOrder = signingOrder
    }

    /// « Swap again » du reçu de E5 : un parcours neuf, prérempli, à la place de celui qui vient de finir.
    private func startOver(with prefill: SwapPrefill) {
        let fresh = SwapFlowModel(service: service, signingOrder: signingOrder, prefill: prefill)
        fresh.onExit = onExit
        fresh.onSwapAgain = startOver(with:)
        model = fresh
    }

    var body: some View {
        Group {
            if model.resumedPending {
                // Un swap signé attend encore son issue : son état, jamais un nouveau swap.
                SwapStatusView(model: model)
            } else {
                SwapAmountView(model: model, onBack: onExit)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.onSwapAgain = startOver(with:) }
        .task { await model.loadIfNeeded() }
    }
}
