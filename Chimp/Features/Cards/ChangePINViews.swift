import SwiftUI

/// Écran d'entrée du changement de PIN : un ViewModel neuf à chaque ouverture (réglages, page d'une carte).
struct ChangePINScreen: View {
    @State private var model: ChangePINModel
    let onExit: () -> Void

    init(card: PINCard, onExit: @escaping () -> Void) {
        _model = State(initialValue: ChangePINModel.live(card: card))
        self.onExit = onExit
    }

    var body: some View {
        ChangePINFlowView(model: model, onExit: onExit)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Changer le PIN d'une carte (non dessiné ; mise en page d'A6 et des revues G6/G7) : revue, PIN actuel, nouveau PIN deux
/// fois, un tap qui démarre tout seul, nouveau code de déblocage. Textes proposés : DESIGN_NOTES §12.
struct ChangePINFlowView: View {
    @Bindable var model: ChangePINModel
    let onExit: () -> Void

    var body: some View {
        Group {
            switch model.screen {
            case .current, .new, .confirmNew:
                entry
            case .review:
                review
            case .unlockCode:
                UnlockCodeView(code: model.unlockCode, isRehearsal: false, replacesOldCode: true, onDone: model.acknowledgeUnlockCode)
            case .unknownOutcome:
                unknownOutcome
            case .done(let codeLost):
                done(codeLost: codeLost)
            }
        }
        .blocksSwipeBack(model.blocksLeaving)
        .chimpSheet(
            isPresented: Binding(get: { model.isShowingTapSheet }, set: { if !$0 { model.cancelTapSheet() } }),
            height: ChimpSize.cardTapSheetHeight,
            isDismissDisabled: model.isBusy
        ) {
            CardTapSheet(
                cardName: model.card.name,
                cardColor: model.card.color,
                stepLabel: "Tap",
                title: "Tap your \(model.card.name) card",
                what: "Changing \(model.card.name)'s PIN. Nothing is signed or moved.",
                who: "The card checks your current PIN first.",
                pinStatus: .ready,
                isScanning: model.isBusy,
                problem: model.problem.map { Self.message(for: $0.kind, card: model.card.name) },
                problemDetails: model.problem?.technicalDetails,
                onScan: { Task { await model.scan() } },
                onCancel: model.isBusy ? nil : { model.cancelTapSheet() }
            )
        }
    }

    private func back() {
        if !model.back() { onExit() }
    }

    // MARK: Saisie

    private var entry: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: entryTitle, subtitle: "\(model.card.name) · N°\(model.card.number)", step: entryStep, steps: 3, onBack: back)
            ChimpPinPad(pin: $model.pinEntry, length: ChangePINModel.pinLength, state: $model.pinState, onComplete: { model.pinCompleted($0) }) {
                ChimpySays(text: entryChimpy, pose: .banana)
                    .padding(.top, ChimpSpacing.xl)
            }
            .padding(.horizontal, ChimpSpacing.lg)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var entryStep: Int {
        switch model.screen {
        case .current: 1
        case .new: 2
        default: 3
        }
    }

    private var entryTitle: LocalizedStringKey {
        switch model.screen {
        case .current: "Your current PIN"
        case .new: "Pick a new 4-digit PIN"
        default: "Type it again"
        }
    }

    private var entryChimpy: LocalizedStringKey {
        switch model.screen {
        case .current:
            if case .oldPINStillActive(let triesLeft) = model.recoveryResult {
                return "Your old PIN still works: nothing was changed. The card has \(triesLeft) tries left. Let's start again."
            }
            return "Type \(model.card.name)'s PIN as it is today. The card checks it when you tap."
        case .new:
            return "Pick one you won't forget. I don't keep a copy."
        default:
            return "Once more, to be sure."
        }
    }

    // MARK: Revue

    private var review: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Change \(model.card.name)'s PIN?", subtitle: "N°\(model.card.number)", onBack: model.isBusy ? nil : { back() })
            ScrollView { reviewContent }
                .scrollBounceBehavior(.basedOnSize)
            ChimpButton("Continue", action: model.continueFromReview)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var reviewContent: some View {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpCard(name: model.card.name, color: model.card.color, number: model.card.number)
                        .frame(width: 210)
                        .rotationEffect(ChimpMotion.Bob.tiltedCardAngle)
                        .chimpBob(duration: 3.4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, ChimpSpacing.l)
                        .padding(.bottom, 30)
                    Text("What happens")
                        .chimpFont(.displayS)
                        .foregroundStyle(.chimpTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ChimpReviewSteps(steps: [
                        Text("\(model.card.name) checks your current PIN"),
                        Text("It saves your new PIN"),
                        Text("It gives you a new unlock code. The old one stops working."),
                    ])
                    .padding(.top, ChimpSpacing.sm)
                    ChimpNoticeBanner(text: "Have a pen ready and keep the card still until it's done: the new unlock code is shown only once.")
                        .padding(.top, ChimpSpacing.l)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
    }

    // MARK: Réponse perdue

    private var unknownOutcome: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Did it work?", subtitle: "\(model.card.name) · N°\(model.card.number)")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpySays(text: "The card moved away before it answered. I can't tell if your new PIN was saved.", pose: .head)
                    Text("Tap the card once more: I'll try your new PIN. If the old one is still the right one, the card counts it as one wrong try.")
                        .chimpFont(.bodyM)
                        .lineSpacing(4)
                        .foregroundStyle(.chimpTextSecondary)
                    if let problem = model.problem {
                        ChimpTechnicalDetails(details: problem.technicalDetails)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.xs) {
                ChimpButton("Check with my new PIN", isLoading: model.isBusy) { Task { await model.checkNewPIN() } }
                ChimpButton("Not now", kind: .link, action: onExit)
                    .disabled(model.isBusy)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    // MARK: Fin

    private func done(codeLost: Bool) -> some View {
        VStack(spacing: ChimpSpacing.l) {
            Spacer(minLength: ChimpSpacing.l)
            Image(.chimpyBanana)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .accessibilityHidden(true)
            Text("\(model.card.name)'s PIN is changed")
                .chimpFont(.displayL)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Use your new PIN from now on. The old one doesn't work anymore.")
                .chimpFont(.bodyL)
                .lineSpacing(4)
                .foregroundStyle(.chimpTextSecondary)
            if codeLost {
                ChimpNoticeBanner(text: "Its new unlock code couldn't be shown. Change the PIN once more to get one.", marker: .error)
            }
            Spacer(minLength: ChimpSpacing.l)
            ChimpButton("Done", action: onExit)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.bottom, ChimpSpacing.l)
        .frame(maxWidth: .infinity)
        .background(Color(.chimpBackground))
    }

    /// Textes proposés (DESIGN_NOTES §12).
    static func message(for kind: ChangePINProblem.Kind, card: String) -> LocalizedStringKey {
        switch kind {
        case .card(let kind): CardReadingView.message(for: kind)
        case .otherCard: "That's not \(card). Tap \(card) to change its PIN. Nothing was changed."
        case .noPIN: "This card has no PIN to change. Nothing was changed."
        }
    }
}
