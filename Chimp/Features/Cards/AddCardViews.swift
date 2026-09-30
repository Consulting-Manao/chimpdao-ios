import SwiftUI

/// Parcours « ajouter une carte » : G1 → G1b → PIN → confirmation et tap → code de déblocage → G2 → envois → G3 (Wallet),
/// ou A4 → A5 → A6 → A8 → confirmation et tap → code → A8 (carte du compte) → envois → A9 (rejoindre, onboarding).
/// Un seul écran à la fois (`AddCardModel.screen`) ; retour par le bouton de chaque écran, jamais par glissement.
struct AddCardFlowView: View {
    @Bindable var model: AddCardModel
    /// Quitter le parcours (Wallet : retour au Wallet ; rejoindre : retour à A3).
    let onExit: () -> Void

    var body: some View {
        Group {
            switch model.screen {
            case .tapNew:
                AddCardTapScreen(model: model, target: .newCard, onScan: { Task { await model.scanNewCard() } }, onCancel: onExit)
            case .firstName:
                YourNameView(model: model, step: 1, steps: 3, onBack: back, onContinue: model.continueFromName)
            case .nameCard:
                NameYourCardView(
                    model: model, title: "Name your new card", subtitle: "Before you let it in",
                    step: model.isJoining ? 2 : 0, steps: model.isJoining ? 3 : 0, onBack: back, onContinue: model.continueFromCard
                )
            case .pin:
                PickPINView(model: model, step: model.isJoining ? 3 : 0, steps: model.isJoining ? 3 : 0, continueTitle: "Next",
                            onBack: back, onContinue: model.continueFromPIN)
            case .findAccount:
                AddCardTapScreen(model: model, target: .accountCard, onScan: { Task { await model.scanForAccount() } }, onCancel: back)
            case .confirm:
                AddCardConfirmView(model: model, onBack: back)
            case .unlockCode:
                UnlockCodeView(code: model.unlockCode, isRehearsal: false, isLost: model.unlockCodeLost, onDone: model.acknowledgeUnlockCode)
            case .member:
                AddCardMemberView(model: model, onCancel: onExit)
            case .adding:
                AddingCardView(model: model, onLeave: onExit)
            case .done:
                CardAddedView(model: model) {
                    model.finish()
                    onExit()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .blocksSwipeBack(true)
    }

    private func back() {
        if !model.back() { onExit() }
    }

    /// « Tap 2 of 3 » : où en sont les taps. Wallet : nouvelle carte (lecture), nouvelle carte (signature), carte du
    /// compte. Rejoindre : A2 (lecture), carte du compte (lecture), nouvelle carte (signature), carte du compte.
    static func tapLabel(_ model: AddCardModel, at screen: AddCardModel.Screen) -> LocalizedStringKey {
        let order: [AddCardModel.Screen] = model.isJoining ? [.nameCard, .findAccount, .confirm, .member] : [.tapNew, .confirm, .member]
        guard let index = order.firstIndex(of: screen) else { return "Tap" }
        return "Tap \(index + 1) of \(order.count)"
    }

    /// Messages de Chimpy (textes proposés, DESIGN_NOTES §12).
    static func message(for kind: AddCardProblem.Kind) -> LocalizedStringKey {
        switch kind {
        case .card(let kind): CardReadingView.message(for: kind)
        case .notAChimpCard: "This card wasn't switched on by ChimpDAO, so it can't join an account."
        case .alreadyInAccount: "This card is already in your account. Nothing to add."
        case .otherAccount: "That card is still in another account. Its owner has to give it away first."
        case .notAMember: "That card isn't in the account. Tap one of its cards."
        case .isTheNewCard: "That's the new card. A card can't invite itself: tap one of the account's cards."
        case .network: "I couldn't check this online. Check your connection and try again."
        }
    }
}

/// G1 (lire la nouvelle carte) et A8 (lire une carte du compte à rejoindre) : écran plein, comme A2. Rien n'est signé.
struct AddCardTapScreen: View {
    enum Target {
        case newCard
        case accountCard
    }

    let model: AddCardModel
    let target: Target
    let onScan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ChimpSpacing.s) {
                Text(AddCardFlowView.tapLabel(model, at: target == .newCard ? .tapNew : .findAccount))
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpOnHeaderAccent)
                Text(title)
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .multilineTextAlignment(.center)
            .padding(.top, ChimpSpacing.xxxl)
            .padding(.horizontal, 30)

            ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 260) {
                Image(.tileHead)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130)
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 5, y: 6)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            if target == .accountCard {
                NewCardReadyBadge(name: model.displayCardName, number: model.cardNumber)
                    .padding(.bottom, ChimpSpacing.m)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                if let problem = model.problem {
                    ChimpySays(text: AddCardFlowView.message(for: problem.kind), pose: .head)
                    ChimpTechnicalDetails(details: problem.technicalDetails, onDarkBackground: true)
                } else {
                    ChimpySays(text: chimpy, pose: .banana)
                }
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.m)

            ChimpButton(model.problem == nil ? "Scan my card" : "Try again", size: .large, isLoading: model.isReading, action: onScan)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            ChimpButton(target == .newCard ? "Cancel" : "Back", kind: .linkOnHeader, action: onCancel)
                .disabled(model.isReading)
                .padding(.bottom, ChimpSpacing.l)
        }
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }

    private var title: LocalizedStringKey {
        if model.isReading { return "Checking the card…" }
        switch target {
        case .newCard: return "Hold the new card to your phone"
        case .accountCard: return "Now tap a card from that account"
        }
    }

    private var chimpy: LocalizedStringKey {
        switch target {
        case .newCard: "Anything already on it stays on it. I don't touch other people's bananas."
        case .accountCard: "I'm just finding your account. Nothing is signed yet."
        }
    }
}

/// « ✓ New card N°0913 read » (maquettes A8 et G2).
private struct NewCardReadyBadge: View {
    let name: String
    let number: String

    var body: some View {
        HStack(spacing: ChimpSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(.chimpPositive))
                .accessibilityHidden(true)
            Text("\(name) · N°\(number) is ready")
                .chimpFont(.captionStrong)
                .foregroundStyle(.chimpOnHeaderPrimary)
        }
        .padding(.vertical, ChimpSpacing.xs)
        .padding(.horizontal, ChimpSpacing.m)
        .background(Capsule().fill(Color(.chimpHeaderShade)))
        .accessibilityElement(children: .combine)
    }
}

/// « Let {carte} in? » : ce qui va se passer, puis le tap qui fait signer à la nouvelle carte son lien au compte
/// (`set_owner`), avec SET PIN si elle n'a pas encore de PIN (règle 8 : tout est dit avant la session NFC).
struct AddCardConfirmView: View {
    @Bindable var model: AddCardModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Let \(model.displayCardName) in?", onBack: model.isLocked ? nil : onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpReviewSteps(steps: steps)
                    if model.pinMode == .choose, model.newCardMustSign {
                        ChimpNoticeBanner(text: "Your PIN can't be removed from the card. Have a pen ready: the card shows an unlock code only once.", marker: .error)
                    }
                    if let problem = model.problem {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: AddCardFlowView.message(for: problem.kind), pose: .head)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpButton(model.newCardMustSign ? "Tap \(model.displayCardName)" : "Continue", isLoading: model.isBusy, action: model.openTapSheet)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .chimpSheet(isPresented: $model.isShowingTapSheet, height: ChimpSize.cardTapSheetHeight, isDismissDisabled: model.isBusy) {
            CardTapSheet(
                cardName: model.displayCardName,
                cardColor: model.cardColor,
                stepLabel: AddCardFlowView.tapLabel(model, at: .confirm),
                what: "\(model.displayCardName) signs its link to your account.",
                who: model.pinMode == .choose ? "The card receives your PIN, then signs." : nil,
                pinStatus: model.pinMode == .none ? .notNeeded : .ready,
                isScanning: model.isBusy,
                problem: sheetProblem,
                problemDetails: model.problem?.technicalDetails,
                onScan: { Task { await model.scanNewCardToSign() } },
                onCancel: model.isBusy ? nil : { model.cancelTapSheet() }
            )
        }
    }

    private var sheetProblem: LocalizedStringKey? {
        model.problem.map { AddCardFlowView.message(for: $0.kind) }
    }

    private var steps: [Text] {
        var steps: [Text] = []
        if model.newCardMustSign {
            switch model.pinMode {
            case .choose: steps.append(Text("\(model.displayCardName) gets your new 4-digit PIN, then links itself to your account."))
            case .existing: steps.append(Text("\(model.displayCardName) links itself to your account. It checks its PIN when you tap."))
            case .none: steps.append(Text("\(model.displayCardName) links itself to your account with a tap."))
            }
        } else {
            steps.append(Text("\(model.displayCardName) already points to your account."))
        }
        steps.append(Text("Then one of your cards says yes. A card can't invite itself."))
        steps.append(Text("Network fees paid by ChimpDAO"))
        return steps
    }
}

/// G2 / A8 · « Now tap one of your cards » (maquette) : une carte du compte dit oui (`add_card`). PIN d'abord s'il en
/// faut un, puis le tap ; la clé de la carte tapée est comparée avant tout PIN.
struct AddCardMemberView: View {
    @Bindable var model: AddCardModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ChimpSpacing.s) {
                Text(AddCardFlowView.tapLabel(model, at: .member))
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpOnHeaderAccent)
                Text(title)
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .multilineTextAlignment(.center)
            .padding(.top, ChimpSpacing.xxxl)
            .padding(.horizontal, 30)

            ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 260) {
                Image(.tileHead)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130)
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 5, y: 6)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            NewCardReadyBadge(name: model.displayCardName, number: model.cardNumber)
                .padding(.bottom, ChimpSpacing.m)

            ChimpySays(text: "A card can't invite itself. One of the gang has to vouch for it.", pose: .banana)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.m)

            ChimpButton("Scan my card", size: .large, isLoading: model.isBusy, action: model.startMemberStep)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            ChimpButton("Not now", kind: .linkOnHeader, action: onCancel)
                .disabled(model.isBusy)
                .padding(.bottom, ChimpSpacing.l)
        }
        .chimpFullScreenBackground(patternOpacity: 0.12)
        .chimpSheet(
            isPresented: Binding(
                get: { model.isShowingMemberPINSheet || model.isShowingMemberTapSheet },
                set: { isPresented in if !isPresented { model.cancelMemberStep() } }
            ),
            height: model.isShowingMemberPINSheet ? ChimpSize.sheetHeight : ChimpSize.cardTapSheetHeight,
            isDismissDisabled: model.isBusy
        ) {
            if model.isShowingMemberPINSheet {
                PinSheet(
                    stepLabel: "PIN",
                    title: pinTitle,
                    subtitle: "Letting \(model.displayCardName) in",
                    pin: $model.memberPIN,
                    length: AddCardModel.pinLength,
                    state: $model.memberPINState,
                    onCancel: { model.cancelMemberStep() },
                    onComplete: model.memberPINEntered
                )
            } else {
                CardTapSheet(
                    cardName: model.expectedMemberName ?? "",
                    cardColor: .banana,
                    stepLabel: AddCardFlowView.tapLabel(model, at: .member),
                    title: tapTitle,
                    what: "Letting \(model.displayCardName) into your account.",
                    who: model.member == nil ? "Any card of your account can say yes." : "Use the same card as before: your PIN is for it.",
                    pinStatus: model.memberUsesPIN ? .ready : .notNeeded,
                    isScanning: model.isBusy,
                    problem: model.problem.map { AddCardFlowView.message(for: $0.kind) },
                    problemDetails: model.problem?.technicalDetails,
                    onScan: { Task { await model.scanMember() } },
                    onCancel: model.isBusy ? nil : { model.cancelMemberStep() }
                )
            }
        }
    }

    private var title: LocalizedStringKey {
        if model.member != nil { return "Now tap that account's card again" }
        return "Now tap one of your cards"
    }

    private var pinTitle: LocalizedStringKey {
        if let name = model.expectedMemberName { return "\(name)'s PIN" }
        return "Your card's PIN"
    }

    private var tapTitle: LocalizedStringKey {
        if let name = model.expectedMemberName { return "Tap your \(name) card again" }
        if model.member != nil { return "Tap the same card again" }
        return "Tap any of your cards"
    }
}

/// Envois : le lien (`set_owner`), l'entrée dans le compte (`add_card`), la confirmation. En cas d'échec : message de
/// Chimpy, détails techniques et la bonne action (réessayer, vérifier à nouveau, retaper la bonne carte).
struct AddingCardView: View {
    let model: AddCardModel
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: isFailed ? "Not quite there" : "Adding \(model.displayCardName)", subtitle: isFailed ? "Nothing is lost" : "Keep the app open")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpProgressSteps(steps: AddCardModel.AddStep.allCases.map { step in
                        ChimpProgressStep(id: step.rawValue, label: Text(label(step)), state: state(of: step))
                    })
                    if case .failed(_, let problem) = model.addingPhase {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: message(for: problem), pose: .head)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    } else {
                        ChimpySays(text: "Hang on, I'm letting it in. It takes a few seconds.", pose: .banana)
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

    private var isFailed: Bool {
        if case .failed = model.addingPhase { return true }
        return false
    }

    @ViewBuilder
    private var actions: some View {
        if case .failed(let step, let problem) = model.addingPhase {
            VStack(spacing: ChimpSpacing.xs) {
                if problem.needsNewTap {
                    ChimpButton(step == .linking ? "Tap \(model.displayCardName) again" : "Tap one of your cards again", action: model.newTapAfterFailure)
                } else {
                    ChimpButton(problem.kind == .notConfirmed ? "Check again" : "Try again", action: model.retryAdding)
                }
                ChimpButton("Not now", kind: .link, action: onLeave)
            }
        } else {
            ChimpButton("Let's swing", isLoading: true) {}
                .disabled(true)
        }
    }

    private func state(of step: AddCardModel.AddStep) -> ChimpProgressStep.State {
        switch model.addingPhase {
        case .running(let current):
            step < current ? .done : (step == current ? .current : .todo)
        case .failed(let failed, _):
            step < failed ? .done : (step == failed ? .failed : .todo)
        }
    }

    private func label(_ step: AddCardModel.AddStep) -> LocalizedStringKey {
        switch step {
        case .linking: "Linking \(model.displayCardName) to your account"
        case .admitting: "Letting it in"
        case .confirming: "Confirming on Stellar"
        }
    }

    private func message(for problem: CreationProblem) -> LocalizedStringKey {
        switch problem.kind {
        case .saveFailed: "The card is in your account, but this phone couldn't save it. Try again."
        default: CreatingAccountView.message(for: problem.kind)
        }
    }
}

/// G3 · Card added / A9 · Joined! (maquettes) : Chimpy à la banane, la carte, deux rappels, « Let's swing ».
struct CardAddedView: View {
    let model: AddCardModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: ChimpSpacing.l) {
                    Image(.chimpyBanana)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 170)
                        .chimpBob(duration: 3.5)
                        .accessibilityHidden(true)
                    ChimpCard(name: model.displayCardName, color: model.cardColor, number: model.cardNumber)
                        .frame(width: 160)
                    Text(model.isJoining ? "Welcome to the gang!" : "\(model.displayCardName) is in the gang!")
                        .chimpFont(.welcomeTitle)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .chimpFont(.lead)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                        check("It can spend from Main, like your other cards")
                        check("It keeps its own wallet, only it can spend that")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.chimpTextPrimary)
                .padding(.top, ChimpSpacing.xxl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpButton("Let's swing", action: onFinish)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
            Text("Chimpy is doing his happy dance. Please don't look.")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
                .padding(.vertical, ChimpSpacing.m)
        }
        .background(Color(.chimpBackground))
    }

    private var subtitle: LocalizedStringKey {
        if model.isJoining { return "Your new card is now part of the account." }
        if let count = model.cardCount { return "\(count) cards in your account now. Keep one at home as a spare." }
        return "It's part of your account now. Keep one card at home as a spare."
    }

    private func check(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: ChimpSpacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(.chimpPositive))
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.bodyM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
