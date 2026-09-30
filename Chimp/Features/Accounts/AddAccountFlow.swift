import SwiftUI

/// « + Add an account · tap one of its cards » (I6) : la reconnexion de l'onboarding (A2, PIN d'une Infineon, « Welcome
/// back! »), par-dessus le compte affiché. Quand le compte s'ouvre, l'app affiche son Wallet (l'écran principal est
/// reconstruit pour le nouveau compte, ce parcours disparaît avec lui). Rien n'est signé ni payé.
struct AddAccountFlow: View {
    @State var model: OnboardingModel
    let onCancel: () -> Void

    var body: some View {
        NavigationStack(path: $model.path) {
            CardReadingView(state: model.readingState, onCancel: onCancel) {
                Task { await model.scan() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OnboardingRoute.self) { route in
                destination(route)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .task { model.openReading() }
    }

    @ViewBuilder
    private func destination(_ route: OnboardingRoute) -> some View {
        switch route {
        case .notAChimpCard:
            NotAChimpCardView(onTryAnother: model.tryAnotherCard)
        case .reconnectPIN:
            if let reconnection = model.reconnection {
                ReconnectPINView(
                    model: reconnection, onBack: model.cancelReconnection,
                    onScan: { Task { await model.scanForReconnection() } }, onOtherCard: model.tryAnotherCard
                )
            }
        case .welcomeBack:
            if let reconnection = model.reconnection {
                WelcomeBackView(model: reconnection, onBack: model.cancelReconnection, onFinish: model.finishWelcomeBack)
            }
        default:
            // Les autres écrans de l'onboarding (création, rejoindre) ne sont pas proposés ici.
            EmptyView()
        }
    }
}
