import CoreNFC
import SwiftUI

/// Parcours d'onboarding : A1 (racine), visite, A2, A3, H3. S'affiche tant qu'aucun compte n'est ouvert sur ce téléphone.
struct OnboardingFlow: View {
    @State var model: OnboardingModel
    #if DESIGN_CATALOG
    @State private var isShowingCatalog = false
    #endif

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(onStart: model.start, onDeveloper: developerAction)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OnboardingRoute.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        #if DESIGN_CATALOG
        .sheet(isPresented: $isShowingCatalog) {
            NavigationStack { DesignSystemCatalogView() }
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ route: OnboardingRoute) -> some View {
        switch route {
        case .tour:
            TourView(page: $model.tourPage, onNext: model.nextTourPage, onSkip: model.finishTour)
        case .reading:
            CardReadingView(state: model.readingState) {
                Task { await model.scan() }
            }
        case .choice(let choice):
            CardChoiceView(choice: choice) { model.startNewAccount(with: choice) }
        case .notAChimpCard:
            NotAChimpCardView(onTryAnother: model.tryAnotherCard)
        case .yourName:
            if let setup = model.setup { YourNameView(model: setup, onBack: model.back, onContinue: model.continueFromName) }
        case .nameYourCard:
            if let setup = model.setup { NameYourCardView(model: setup, onBack: model.back, onContinue: model.continueFromCard) }
        case .pickPIN:
            if let setup = model.setup { PickPINView(model: setup, onBack: model.back, onScan: model.scanForSetup) }
        case .unlockCode:
            // Répétition : aucun PIN n'est envoyé à la carte, donc aucun code (étape 4 : le PUK renvoyé par SET PIN).
            UnlockCodeView(code: nil, onDone: model.acknowledgeUnlockCode)
                .blocksSwipeBack(true)
        case .setupCheck:
            if let setup = model.setup { SetupCheckView(model: setup, onContinue: model.continueAfterCheck) }
        case .welcome:
            if let setup = model.setup {
                JungleWelcomeView(
                    cardName: setup.trimmedCardName, cardColor: setup.cardColor, hasPIN: setup.pinMode != .none,
                    isRehearsal: setup.isRehearsal, onFinish: model.finishRehearsal
                )
            }
        }
    }

    /// Roue dentée d'A1 : catalogue et mode admin (Debug et Testing), pour enregistrer une carte avant l'onboarding.
    private var developerAction: (() -> Void)? {
        #if DESIGN_CATALOG
        return { isShowingCatalog = true }
        #else
        return nil
        #endif
    }
}

extension OnboardingModel {
    /// Onboarding branché sur la vraie carte (Core NFC) et le testnet. Sur un appareil sans NFC (simulateur), les
    /// builds Debug et Testing prennent une carte et un réseau factices ; en Release, l'erreur « pas de NFC » s'affiche.
    static func live(session: AppSession) -> OnboardingModel {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable {
            return OnboardingModel(
                session: session, reader: MockChipReader(scenario: .infineon), service: MockOnboardingService(scenario: .fresh),
                makeSetup: { try AccountSetupModel(choice: $0, service: MockAccountSetupService(), signer: MockChipSigner()) }
            )
        }
        #endif
        return OnboardingModel(
            session: session, reader: NFCChipReader(), service: ChainOnboardingService(config: .testnet),
            makeSetup: { try AccountSetupModel(choice: $0, service: ChainAccountSetupService(config: .testnet), signer: NFCChipSigner()) }
        )
    }
}
