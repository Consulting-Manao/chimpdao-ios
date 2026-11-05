import SwiftUI

/// G6 · Remove a card et G7 · I lost a card (maquette), puis l'envoi et la fin. Le PIN et le tap sont les feuilles
/// d'Envoyer, posées sur la revue ; G5 (dernière carte) est une feuille. Le retour est bloqué pendant la signature et l'envoi.
struct RemoveCardFlowView: View {
    @Bindable var model: RemoveCardModel
    let onExit: (_ removed: Bool) -> Void
    /// G5 « Add a card ».
    var onAddCard: () -> Void = {}
    /// G6 : « Move it to Main first » (Chimpy de la maquette).
    var onMoveFirst: (() -> Void)?

    var body: some View {
        Group {
            switch model.screen {
            case .review:
                if model.mode == .remove {
                    RemoveCardReviewView(model: model, onBack: { onExit(false) }, onMoveFirst: onMoveFirst)
                } else {
                    LostCardReviewView(model: model, onBack: { onExit(false) })
                }
            case .removing:
                RemovingCardView(model: model, onLeave: { onExit(false) })
            case .done:
                CardRemovedView(model: model) { onExit(true) }
            }
        }
        .blocksSwipeBack(model.blocksLeaving || model.screen != .review)
        .chimpSheet(
            isPresented: Binding(
                get: { model.isShowingPINSheet || model.isShowingTapSheet },
                set: { if !$0 { model.cancelSigning() } }
            ),
            height: model.isShowingPINSheet ? ChimpSize.sheetHeight : ChimpSize.cardTapSheetHeight,
            isDismissDisabled: model.isBusy
        ) {
            if model.isShowingPINSheet {
                PinSheet(
                    stepLabel: "PIN",
                    title: pinTitle,
                    subtitle: model.mode == .remove ? "Removing \(model.target.name) from your account" : "Locking \(model.target.name) out",
                    pin: $model.pin,
                    length: RemoveCardModel.pinLength,
                    state: $model.pinState,
                    onCancel: { model.cancelSigning() },
                    onComplete: model.pinEntered
                )
            } else {
                CardTapSheet(
                    cardName: model.mode == .remove ? model.target.name : "",
                    cardColor: model.target.color,
                    stepLabel: "Tap",
                    title: tapTitle,
                    what: model.mode == .remove
                        ? "Removing \(model.target.name) from your account. Its wallet stays on the card."
                        : "Removing \(model.target.name) from your account, for good.",
                    who: model.mode == .remove
                        ? "Only \(model.target.name) can sign its own removal."
                        : "Any other card of your account can do it.",
                    pinStatus: model.usesPIN ? .ready : .notNeeded,
                    isScanning: model.isBusy,
                    isGettingReady: model.isGettingReady,
                    problem: model.problem.map { Self.message(for: $0.kind, card: model.target.name) },
                    problemDetails: model.problem?.technicalDetails,
                    onScan: { Task { await model.scan() } },
                    onCancel: model.isBusy ? nil : { model.cancelSigning() }
                )
            }
        }
        .chimpSheet(isPresented: $model.isShowingLastCard, height: 560, fitsContent: true) {
            LastCardSheet(mode: model.mode, name: model.target.name, onAddCard: {
                model.isShowingLastCard = false
                onAddCard()
            }, onOK: { model.isShowingLastCard = false })
        }
    }

    private var pinTitle: LocalizedStringKey {
        model.mode == .remove ? "\(model.target.name)'s PIN" : "Your other card's PIN"
    }

    private var tapTitle: LocalizedStringKey {
        model.mode == .remove ? "Tap your \(model.target.name) card" : "Tap another of your cards"
    }

    /// Textes proposés (absents de la maquette), DESIGN_NOTES §12.
    static func message(for kind: RemoveCardProblem.Kind, card: String) -> LocalizedStringKey {
        switch kind {
        case .card(let kind): CardReadingView.message(for: kind)
        case .notTheCard: "That's not \(card). Only \(card) can sign its own removal. Nothing was sent."
        case .isTheLostCard: "That's \(card), the card you're removing. Tap another card of your account. Nothing was sent."
        case .notAMember: "That card isn't one of yours. Tap another card of your account. Nothing was sent."
        case .network: "I couldn't reach Stellar. Check your connection and try again. Nothing was sent."
        case .pendingPayment: "A payment is still being checked. Open Send to see how it ended, then try again."
        }
    }
}

/// Bloc commun des deux revues : message de problème avant le tap (réseau, paiement en attente).
private struct RemovalProblemNote: View {
    let model: RemoveCardModel

    var body: some View {
        if let problem = model.problem, !model.isShowingTapSheet {
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                ChimpFieldMessage(text: RemoveCardFlowView.message(for: problem.kind, card: model.target.name), kind: .error)
                ChimpTechnicalDetails(details: problem.technicalDetails)
            }
        }
    }
}

/// G6 · Remove a card (maquette) : la carte, « What happens », Chimpy, « Looks good ».
struct RemoveCardReviewView: View {
    let model: RemoveCardModel
    let onBack: () -> Void
    var onMoveFirst: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Remove the \(model.target.name) card", subtitle: subtitle, onBack: model.isBusy ? nil : onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RemovalCardPicture(target: model.target)
                    Text("What happens")
                        .chimpFont(.displayS)
                        .foregroundStyle(.chimpTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ChimpReviewSteps(steps: [
                        Text("\(model.target.name) can no longer use Main"),
                        model.target.walletIsEmpty
                            ? Text("It keeps its own wallet (empty right now)")
                            : Text("It keeps its own wallet and the \(model.target.walletAmount) on it"),
                        Text("It can start its own account later"),
                    ])
                    .padding(.top, ChimpSpacing.sm)
                    RemovalProblemNote(model: model)
                        .padding(.top, ChimpSpacing.m)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.m) {
                if !model.target.walletIsEmpty {
                    ChimpySays(text: "Want the \(model.target.walletAmount) back in Main? Move it before you remove \(model.target.name).", pose: .teacher)
                }
                ChimpButton("Looks good", isLoading: model.isBusy) { Task { await model.start() } }
                if !model.target.walletIsEmpty, let onMoveFirst {
                    ChimpButton("Move it to Main first", kind: .link, action: onMoveFirst)
                        .disabled(model.isBusy)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.ml)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var subtitle: LocalizedStringKey {
        if let name = model.accountOwnerName { return "From \(name)'s account" }
        return "From your account"
    }
}

/// G7 · I lost a card (maquette) : ce qui reste à l'abri (Main), ce qui reste lié à la carte perdue (son wallet), « What
/// happens », Chimpy, « Remove the {carte} card · Tap another card to confirm ». Précision de Barth : le montant du
/// wallet perdu est affiché et l'écran dit qu'il reste lié à cette carte (personne d'autre ne peut le dépenser).
struct LostCardReviewView: View {
    let model: RemoveCardModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Your \(model.target.name) card is lost", subtitle: "Let's lock it out", onBack: model.isBusy ? nil : onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: ChimpSpacing.sm) {
                        status(
                            label: "Safe", tone: Color(.chimpPositive),
                            title: Text("Main · \(model.target.mainAmount)"),
                            detail: Text("Your other cards can still open it.")
                        )
                        status(
                            label: "Stays on the lost card", tone: Color(.chimpNegative),
                            title: Text("\(model.target.name)'s wallet · \(model.target.walletAmount)"),
                            detail: walletDetail
                        )
                    }
                    Text("What happens")
                        .chimpFont(.displayS)
                        .foregroundStyle(.chimpTextPrimary)
                        .padding(.top, ChimpSpacing.xxl)
                        .accessibilityAddTraits(.isHeader)
                    ChimpReviewSteps(steps: [
                        Text("\(model.target.name) is removed from your account"),
                        Text("It can never open Main again, even with the PIN"),
                        model.target.walletIsEmpty
                            ? Text("Its wallet is empty: nothing is left behind")
                            : Text("Its \(model.target.walletAmount) stays locked on the lost card"),
                    ])
                    .padding(.top, ChimpSpacing.sm)
                    RemovalProblemNote(model: model)
                        .padding(.top, ChimpSpacing.m)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.m) {
                ChimpySays(text: "Sorry bro. Tip for next time: keep card wallets small, keep Main big.", pose: .head)
                Button { Task { await model.start() } } label: {
                    VStack(spacing: 2) {
                        Text("Remove the \(model.target.name) card")
                        Text("Tap another card to confirm")
                            .chimpFont(.captionStrong)
                    }
                }
                .buttonStyle(ChimpButtonStyle(kind: .primary, isLoading: model.isBusy))
                .allowsHitTesting(!model.isBusy)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.ml)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    /// Ce que devient l'argent du wallet perdu : lié à la carte, et ce qui la protège (PIN, ou rien pour une DUOX).
    private var walletDetail: Text {
        if model.target.walletIsEmpty { return Text("Nothing on it. Good.") }
        let tied = Text("It stays tied to that card: only that card can ever spend it. You can't get it back without it.")
        let guardText = model.target.chip == .duox
            ? Text("This card has no PIN: whoever finds it can spend it.")
            : Text("Whoever finds it would also need its PIN.")
        return tied + Text(verbatim: " ") + guardText
    }

    private func status(label: LocalizedStringKey, tone: Color, title: Text, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .chimpFont(.labelS)
                .textCase(.uppercase)
                .foregroundStyle(tone)
            title
                .chimpFont(.rowTitle)
                .foregroundStyle(.chimpTextPrimary)
            detail
                .chimpFont(.captionS)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }
}

/// La carte, penchée, qui flotte (G4 à G6).
private struct RemovalCardPicture: View {
    let target: RemovalTarget

    var body: some View {
        ChimpCard(name: target.name, color: target.color, number: target.number)
            .frame(width: 210)
            .rotationEffect(ChimpMotion.Bob.tiltedCardAngle)
            .chimpBob(duration: 3.4)
            .frame(maxWidth: .infinity)
            .padding(.top, ChimpSpacing.l)
            .padding(.bottom, 30)
    }
}

/// G5 · Last card — not allowed (maquette, adaptée au retrait et à la carte perdue).
struct LastCardSheet: View {
    let mode: RemoveCardModel.Mode
    let name: String
    let onAddCard: () -> Void
    let onOK: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(.chimpyStop)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .accessibilityHidden(true)
            Text("\(name) is your only card")
                .chimpFont(.sheetTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpTextPrimary)
                .padding(.top, ChimpSpacing.m)
                .accessibilityAddTraits(.isHeader)
            Text(body(for: mode))
                .chimpFont(.bodyL)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ChimpSpacing.sm)
            VStack(spacing: 11) {
                if mode == .remove {
                    ChimpButton("Add a card", action: onAddCard)
                }
                ChimpButton("OK", kind: mode == .remove ? .link : .primary, action: onOK)
            }
            .padding(.top, ChimpSpacing.xl)
        }
        // Pas de marge du bas ici : la feuille met déjà celle de la maquette (42 pt, barre d'accueil comprise).
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    private func body(for mode: RemoveCardModel.Mode) -> LocalizedStringKey {
        switch mode {
        case .remove:
            "If it goes, nobody could ever open Main again. Add another card first, then you can remove this one."
        case .lost:
            "No other card can lock it out, and Main only opens with it. If you find it, add a second card right away."
        }
    }
}

/// Envoi de `remove_card` et relecture. En cas d'échec : message de Chimpy, détails techniques, la bonne action.
struct RemovingCardView: View {
    let model: RemoveCardModel
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: model.isFailed ? "Not quite there" : "Removing \(model.target.name)", subtitle: model.isFailed ? "Nothing is lost" : "Keep the app open")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpProgressSteps(steps: RemoveCardModel.Step.allCases.map { step in
                        ChimpProgressStep(id: step.rawValue, label: Text(label(step)), state: state(of: step))
                    })
                    if case .failed(_, let problem) = model.phase {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: message(for: problem), pose: .head)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    } else {
                        ChimpySays(text: "Hang on, I'm telling your account. It takes a few seconds.", pose: .banana)
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
    }

    @ViewBuilder
    private var actions: some View {
        if case .failed(_, let problem) = model.phase {
            VStack(spacing: ChimpSpacing.xs) {
                if problem.needsNewTap {
                    ChimpButton("Tap the card again", action: model.newTapAfterFailure)
                } else {
                    ChimpButton(problem.kind == .notConfirmed ? "Check again" : "Try again", action: model.retry)
                }
                ChimpButton("Not now", kind: .link, action: onLeave)
            }
        } else {
            ChimpButton("Done", isLoading: true) {}
                .disabled(true)
        }
    }

    private func state(of step: RemoveCardModel.Step) -> ChimpProgressStep.State {
        switch model.phase {
        case .running(let current): step < current ? .done : (step == current ? .current : .todo)
        case .failed(let failed, _): step < failed ? .done : (step == failed ? .failed : .todo)
        }
    }

    private func label(_ step: RemoveCardModel.Step) -> LocalizedStringKey {
        switch step {
        case .removing: "Removing \(model.target.name) from your account"
        case .confirming: "Confirming on Stellar"
        }
    }

    private func message(for problem: CreationProblem) -> LocalizedStringKey {
        switch problem.kind {
        case .saveFailed: "The card is out of your account, but this phone couldn't update itself. Try again."
        case .notConfirmed: "It was sent, but Stellar still lists the card. Check again in a moment. Nothing is sent twice."
        default: CreatingAccountView.message(for: problem.kind)
        }
    }
}

/// Fin (non dessinée) : la carte est sortie du compte.
struct CardRemovedView: View {
    let model: RemoveCardModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: ChimpSpacing.l) {
            Spacer(minLength: ChimpSpacing.l)
            Image(.chimpyStand)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .accessibilityHidden(true)
            Text(model.mode == .remove ? "\(model.target.name) left your account" : "\(model.target.name) is locked out")
                .chimpFont(.displayL)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(model.mode == .remove
                 ? "It keeps its own wallet. Tap it on any phone to start a new account with it."
                 : "It can't open Main anymore, even with its PIN. Your other cards work as before.")
                .chimpFont(.bodyL)
                .lineSpacing(4)
                .foregroundStyle(.chimpTextSecondary)
            Spacer(minLength: ChimpSpacing.l)
            ChimpButton("Back to my wallet", action: onDone)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.bottom, ChimpSpacing.l)
        .frame(maxWidth: .infinity)
        .background(Color(.chimpBackground))
    }
}
