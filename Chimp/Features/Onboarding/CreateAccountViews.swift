import SwiftUI

/// Confirmation juste avant le vrai tap (demandée le 2026-09-29) : « This will create your account and set your PIN
/// for good. » Ce qui va se passer, puis « Create my account » ouvre la feuille du tap. En Debug et Testing, la
/// répétition à blanc est proposée à côté.
struct CreateAccountConfirmView: View {
    @Bindable var model: AccountSetupModel
    let onBack: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Create your account?", onBack: model.isBusy ? nil : onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    Text(headline)
                        .chimpFont(.sheetTitle)
                        .foregroundStyle(.chimpTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    ChimpReviewSteps(steps: steps)
                    if model.pinMode == .choose {
                        ChimpNoticeBanner(text: "Your PIN can't be removed from the card. Have a pen ready: the card shows an unlock code only once.", marker: .error)
                    }
                    if let problem = model.tapProblem {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: CardReadingView.message(for: problem.kind), pose: .head)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.xs) {
                ChimpButton("Create my account", isLoading: model.isBusy && !model.isRehearsal) { model.openTapSheet(.real) }
                    .disabled(!model.canFinish)
                #if CHIMP_ADMIN
                if model.canRehearse, !model.pinWasSet {
                    ChimpButton(untranslated("Practice run instead (nothing sent)"), kind: .secondary) { model.openTapSheet(.rehearsal) }
                        .disabled(!model.canFinish)
                }
                #endif
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(model.isBusy)
        .chimpSheet(isPresented: $model.isShowingTapSheet, height: ChimpSize.cardTapSheetHeight, isDismissDisabled: model.isBusy) {
            tapSheet
        }
    }

    private var headline: LocalizedStringKey {
        switch model.pinMode {
        case .choose: "This will create your account and set your PIN for good."
        case .existing, .none: "This will create your account."
        }
    }

    private var steps: [Text] {
        var steps = [
            model.network == .testnet
                ? Text("Your Main account is created on Stellar Testnet. Network fees are paid by ChimpDAO.")
                : Text("Your Main account is created on Stellar. Network fees are paid by ChimpDAO."),
            Text("\(model.displayCardName) becomes its first card."),
        ]
        switch model.pinMode {
        case .choose: steps.append(Text("Your 4-digit PIN is written on the card. It'll ask for it every time it signs."))
        case .existing: steps.append(Text("The card checks its PIN when you tap."))
        case .none: steps.append(Text("This card has no PIN: a tap is all it takes."))
        }
        return steps
    }

    private var tapSheet: some View {
        var who: LocalizedStringKey? = model.pinMode == .choose ? "The card receives your PIN, then signs." : nil
        #if CHIMP_ADMIN
        if model.isRehearsal { who = untranslated("Practice run: nothing is sent, and the PIN isn't set on the card.") }
        #endif
        let cancel: (() -> Void)? = model.isBusy ? nil : { model.cancelTapSheet() }
        return CardTapSheet(
            cardName: model.displayCardName,
            cardColor: model.cardColor,
            stepLabel: "Last step",
            what: "Your card signs two things: a check that it's really yours, and the link to your new Main account.",
            who: who,
            pinStatus: model.pinMode == .none ? .notNeeded : .ready,
            isScanning: model.isBusy,
            onScan: onScan,
            onCancel: cancel
        )
    }
}

/// Création en cours : les étapes (vérification de la carte, création du compte, lien, confirmation), puis A7.
/// En cas d'échec : message de Chimpy, détails techniques, et la bonne action (réessayer, vérifier à nouveau, retaper).
/// Rien ne peut interrompre la création : pas de retour, ni par bouton ni par glissement.
struct CreatingAccountView: View {
    let model: AccountSetupModel
    let onRetry: () -> Void
    let onNewTap: () -> Void
    let onStartOver: () -> Void
    let onCreated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpProgressSteps(steps: CreationStep.allCases.enumerated().map { index, step in
                        ChimpProgressStep(id: index, label: Text(label(step)), state: state(of: step))
                    })

                    if case .failed(let problem) = model.phase {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: Self.message(for: problem.kind), pose: .head)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    } else if model.createdResult == nil {
                        ChimpySays(text: "Hang on, I'm setting everything up. It takes a few seconds.", pose: .banana)
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(true)
        .onChange(of: model.createdResult, initial: true) { _, result in
            if result != nil { onCreated() }
        }
    }

    private var title: LocalizedStringKey {
        switch model.phase {
        case .failed: "Not quite there"
        case .created: "All set!"
        default: "Setting up your account"
        }
    }

    private var subtitle: LocalizedStringKey {
        if case .failed = model.phase { return "Nothing is lost" }
        return "Keep the app open"
    }

    @ViewBuilder
    private var actions: some View {
        if case .failed(let problem) = model.phase {
            VStack(spacing: ChimpSpacing.xs) {
                if problem.needsNewTap {
                    ChimpButton("Tap your card again", action: onNewTap)
                } else {
                    ChimpButton(problem.kind == .notConfirmed ? "Check again" : "Try again", action: onRetry)
                }
                ChimpButton("Start over", kind: .link, action: onStartOver)
            }
        } else {
            ChimpButton("Continue", isLoading: model.createdResult == nil, action: onCreated)
                .disabled(model.createdResult == nil)
        }
    }

    /// Étape où l'on en est (la dernière atteinte, même en cas d'échec).
    private var reached: CreationStep? {
        switch model.phase {
        case .creating(let step): step
        case .created: nil
        default: lastStep
        }
    }

    /// Mémorise la dernière étape atteinte pour l'affichage de l'échec.
    private var lastStep: CreationStep? { model.lastReachedStep }

    private func state(of step: CreationStep) -> ChimpProgressStep.State {
        if model.createdResult != nil { return .done }
        guard let reached else { return .todo }
        if step < reached { return .done }
        if step == reached {
            if case .failed = model.phase { return .failed }
            return .current
        }
        return .todo
    }

    private func label(_ step: CreationStep) -> LocalizedStringKey {
        switch step {
        case .checkingCard: "Checking it's really your card"
        case .creatingAccount: "Creating your Main account"
        case .linkingCard: "Linking \(model.displayCardName) to it"
        case .confirming: "Confirming on Stellar"
        }
    }

    /// Messages de Chimpy (textes proposés, états absents de la maquette).
    static func message(for kind: CreationProblem.Kind) -> LocalizedStringKey {
        switch kind {
        case .network: "I couldn't reach Stellar. Check your connection and try again: I'll pick up where I stopped."
        case .feeHelperBusy: "ChimpDAO's fee helper is busy right now. Try again in a moment."
        case .feeHelperRefused: "ChimpDAO's fee helper said no. Please send the technical details to support."
        case .notConfirmed: "It was sent, but Stellar hasn't confirmed it yet. Check again in a moment. Don't worry, nothing is sent twice."
        case .signatureExpired: "The card's signature is too old now. Tap your card once more to finish."
        case .cardCheckFailed: "The card's signature didn't check out. Tap the same card again."
        case .saveFailed: "Your account is ready, but this phone couldn't save it. Try again."
        case .other: "Something went wrong on Stellar. Try again, or send the technical details to support."
        }
    }
}
