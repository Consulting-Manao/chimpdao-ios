#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : l'onboarding sur des scénarios factices, et chaque écran dans chaque état.
/// Tout se passe sur une session en mémoire : le vrai compte du téléphone n'est jamais touché.
struct OnboardingCatalogPage: View {
    let settings: CatalogSettings

    @State private var readerScenario = MockChipReader.Scenario.infineon
    @State private var serviceScenario = MockOnboardingService.Scenario.fresh
    @State private var tourSeen = false
    @State private var setupScenario = MockAccountSetupService.Scenario.success
    @State private var creationScenario = MockAccountCreationChain.Scenario.success
    @State private var pinScenario = ReconnectPINScenario.accepted
    @State private var joinScenario = MockAddCardService.Scenario.success
    @State private var runningFlow: OnboardingModel?
    @State private var runningSession: AppSession?

    var body: some View {
        CatalogPage(LocalizedStringKey("Onboarding"), settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $readerScenario) {
                        ForEach(MockChipReader.Scenario.allCases) { Text(verbatim: $0.label).tag($0) }
                    } label: {
                        Text(verbatim: "Card")
                    }
                    Picker(selection: $serviceScenario) {
                        ForEach(MockOnboardingService.Scenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text(verbatim: "Network answer")
                    }
                    Picker(selection: $setupScenario) {
                        ForEach(MockAccountSetupService.Scenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text(verbatim: "Practice run checks")
                    }
                    Picker(selection: $creationScenario) {
                        ForEach(MockAccountCreationChain.Scenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text(verbatim: "Real creation (fake chain)")
                    }
                    Picker(selection: $pinScenario) {
                        ForEach(ReconnectPINScenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text(verbatim: "PIN check (member card with PIN)")
                    }
                    Picker(selection: $joinScenario) {
                        ForEach(MockAddCardService.Scenario.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: {
                        Text(verbatim: "Join (fake chain)")
                    }
                    Toggle(isOn: $tourSeen) { Text(verbatim: "Tour already seen") }
                    Button {
                        let session = AppSession(store: InMemoryLocalWalletStore(LocalWallet(tourSeen: tourSeen)), network: .testnet)
                        runningSession = session
                        let setupScenario = self.setupScenario
                        let creationScenario = self.creationScenario
                        runningFlow = OnboardingModel(
                            session: session,
                            reader: MockChipReader(scenario: readerScenario),
                            service: MockOnboardingService(scenario: serviceScenario),
                            signer: MockChipSigner(outcome: pinScenario.outcome),
                            joinService: MockAddCardService(scenario: joinScenario),
                            makeSetup: { choice in
                                try AccountSetupModel(
                                    choice: choice, service: MockAccountSetupService(scenario: setupScenario),
                                    creator: AccountCreator(chain: MockAccountCreationChain(scenario: creationScenario)),
                                    signer: MockChipSigner(), session: session,
                                    rehearsal: MockAccountSetupService(scenario: setupScenario)
                                )
                            }
                        )
                    } label: {
                        Text(verbatim: "Start at A1 · Welcome")
                    }
                } header: {
                    Text(verbatim: "Run the flow")
                }
                .listRowBackground(Color(.chimpSurface))

                Section {
                    demo("A1 · Welcome") { WelcomeView(onStart: {}) }
                    ForEach(0..<OnboardingModel.tourPageCount, id: \.self) { page in
                        demo("A1·\(page + 1) · Tour") { TourDemo(page: page) }
                    }
                    demo("A2 · Waiting for a scan") { CardReadingView(state: .idle, onScan: {}) }
                    demo("A2 · Scanning") { CardReadingView(state: .scanning, onScan: {}) }
                    demo("A2 · Checking online") { CardReadingView(state: .checking, onScan: {}) }
                    ForEach(Self.problems, id: \.title) { problem in
                        demo(problem.title) { CardReadingView(state: .failed(problem.value), onScan: {}) }
                    }
                    demo("A3 · Fresh card, empty") { CardChoiceView(choice: Self.choice(.fresh, empty: true), onStartNewAccount: {}) }
                    demo("A3 · Fresh card with money") { CardChoiceView(choice: Self.choice(.fresh, empty: false), onStartNewAccount: {}) }
                    demo("A3 · Orphan card") { CardChoiceView(choice: Self.choice(.orphan(lastKnown: nil), empty: nil), onStartNewAccount: {}) }
                    demo("H1 · A gift card") {
                        GiftCardView(model: GiftCardModel(choice: Self.giftChoice, oracle: nil), onJoin: {}, onStartNewAccount: {})
                    }
                    demo("H2 · New phone (Look who's back!)") { CardReadingView(state: .idle, isReturning: true, onScan: {}) }
                    demo("H3 · Not a real Chimp card") { NotAChimpCardView(onTryAnother: {}) }
                } header: {
                    Text(verbatim: "Screens")
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
            .chimpFont(.rowTitle)
            .foregroundStyle(.chimpTextPrimary)
        }
        .fullScreenCover(item: Binding(
            get: { runningFlow.map(FlowBox.init) },
            set: { runningFlow = $0?.model }
        )) { box in
            OnboardingFlow(model: box.model)
                .overlay(alignment: .topTrailing) {
                    Button { runningFlow = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.hierarchical)
                    }
                    .padding(.trailing, ChimpSpacing.screenMargin)
                    .accessibilityLabel(Text(verbatim: "Close"))
                }
                .catalogOverrides(settings)
                // Compte ouvert (connexion, ou création après A7) : l'app afficherait le Wallet ; ici, on referme le parcours.
                .onChange(of: runningSession.map { !$0.showsOnboarding } ?? false) { _, opened in
                    if opened { runningFlow = nil }
                }
        }
    }

    private func demo(_ title: String, @ViewBuilder screen: @escaping () -> some View) -> some View {
        NavigationLink {
            CatalogScreenDemo(settings: settings, screen: screen)
        } label: {
            Text(verbatim: title)
        }
    }

    private static let problems: [(title: String, value: OnboardingProblem)] = [
        ("A2 · No NFC on this iPhone", .init(kind: .nfcUnavailable, technicalDetails: "This device can't read NFC.")),
        ("A2 · Timeout", .init(kind: .timeout, technicalDetails: "The scan timed out (60 s).")),
        ("A2 · Card moved", .init(kind: .cardMoved, technicalDetails: "The connection to the card was lost: Tag connection lost")),
        ("A2 · Two cards", .init(kind: .multipleCards, technicalDetails: "More than one card in the field. Use only one card.")),
        ("A2 · Couldn't check online", .init(kind: .couldntCheck, technicalDetails: "Stellar RPC error: The request timed out.")),
        ("A2 · Read failed", .init(kind: .readFailed, technicalDetails: "GET KEY INFO failed (status 6D00).")),
    ]

    /// Carte cadeau de la maquette H1 : 250 XLM et 40 USDC (prix en dollars absents : montants par actif).
    private static let giftChoice = CardChoice(
        kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
        tokenID: 688, pocket: nil, pocketIsEmpty: false,
        pocketBalances: [AssetAmount(code: "XLM", amount: 250), AssetAmount(code: "USDC", amount: 40)]
    )

    private static func choice(_ kind: CardChoice.Kind, empty: Bool?) -> CardChoice {
        CardChoice(kind: kind, card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
                   tokenID: 7, pocket: nil, pocketIsEmpty: empty)
    }
}

/// Réponse de la fausse carte à VERIFY PIN, à la reconnexion (carte « member » avec PIN).
enum ReconnectPINScenario: String, CaseIterable, Identifiable {
    case accepted
    case wrongPIN
    case locked
    case otherCard

    var id: String { rawValue }

    var outcome: Result<ChipSignedDigest, ChipError> {
        switch self {
        case .accepted: .success(.secp256k1(signature: Data(repeating: 0x11, count: 64)))
        case .wrongPIN: .failure(.wrongPIN(retriesLeft: 2))
        case .locked: .failure(.pinLocked)
        case .otherCard: .failure(.wrongCard)
        }
    }
}

/// Un écran en plein écran, avec un bouton pour revenir à la liste.
private struct CatalogScreenDemo<Screen: View>: View {
    let settings: CatalogSettings
    @ViewBuilder let screen: () -> Screen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        screen()
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.hierarchical)
                }
                .padding(.trailing, ChimpSpacing.screenMargin)
                .accessibilityLabel(Text(verbatim: "Back to states"))
            }
            .toolbar(.hidden, for: .navigationBar)
            .catalogOverrides(settings)
    }
}

private struct TourDemo: View {
    @State var page: Int

    var body: some View {
        TourView(page: $page, onNext: { page = min(page + 1, OnboardingModel.tourPageCount - 1) }, onSkip: {})
    }
}

/// `fullScreenCover(item:)` demande un élément `Identifiable`.
private struct FlowBox: Identifiable {
    let model: OnboardingModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}
#endif
