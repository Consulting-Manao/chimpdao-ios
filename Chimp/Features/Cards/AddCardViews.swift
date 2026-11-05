import SwiftUI

/// Parcours « ajouter une carte » : G1 → G1b → confirmation → PIN et tap → code de déblocage → G2 → envois → G3 (Wallet),
/// ou A4 → A5 → A8 → confirmation → A6 et tap → code → A8 (carte du compte) → envois → A9 (rejoindre, onboarding).
/// Le tap démarre tout seul dès le PIN prêt (`AutoScan`).
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
                YourNameView(model: model, step: step(.firstName), steps: steps, onBack: back, onContinue: model.continueFromName)
            case .nameCard:
                NameYourCardView(
                    model: model, title: "Name your new card", subtitle: "Before you let it in",
                    step: step(.nameCard), steps: steps, onBack: back, onContinue: model.continueFromCard
                )
            case .pin:
                PickPINView(model: model, step: step(.pin), steps: steps, subtitle: "For \(model.displayCardName), the new card",
                            onBack: back, onContinue: model.continueFromPIN)
                    .modifier(NewCardTapSheet(model: model))
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
        // Sons : un tap réussi fait avancer le parcours ; carte ajoutée ; problème.
        .onChange(of: model.screen) { old, new in
            if let sound = Self.sound(from: old, to: new) { ChimpSoundPlayer.shared.play(sound) }
        }
        .onChange(of: model.problem) { _, new in
            if let new { ChimpSoundPlayer.shared.play(Self.sound(for: new.kind)) }
        }
    }

    /// Le son d'un passage d'écran : après un tap réussi (lecture ou signature) et la carte ajoutée.
    static func sound(from old: AddCardModel.Screen, to new: AddCardModel.Screen) -> ChimpSound? {
        switch (old, new) {
        case (_, .done), (.tapNew, .nameCard), (.findAccount, .confirm), (.confirm, .unlockCode), (.confirm, .member),
             (.pin, .unlockCode), (.pin, .member), (.member, .adding):
            .confirmation
        default: nil
        }
    }

    /// Mauvaise carte tapée (hurt) ou souci technique (error).
    static func sound(for problem: AddCardProblem.Kind) -> ChimpSound {
        switch problem {
        case .isTheNewCard, .notTheChosenCard, .notAMember, .alreadyInAccount, .otherAccount, .notAChimpCard: .hurt
        case .card, .network: .error
        }
    }

    private func back() {
        if !model.back() { onExit() }
    }

    private func step(_ screen: AddCardModel.Screen) -> Int { model.progress(at: screen)?.step ?? 0 }
    private var steps: Int { model.progressScreens.count }

    /// « Step 4 of 5 » : la même numérotation sur tous les écrans du parcours (`AddCardModel.progressScreens`).
    static func stepLabel(_ model: AddCardModel, at screen: AddCardModel.Screen) -> LocalizedStringKey {
        guard let progress = model.progress(at: screen) else { return "Tap" }
        return "Step \(progress.step) of \(progress.of)"
    }

    /// Carte refusée : Chimpy se bouche le nez ; souci technique : la tête, comme les autres erreurs.
    static func pose(for kind: AddCardProblem.Kind) -> ChimpyPose {
        sound(for: kind) == .hurt ? .stop : .head
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
        case .notTheChosenCard(let name): "That's another card of your account. Tap \(name), the one you picked, or pick this one instead."
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
                Text(AddCardFlowView.stepLabel(model, at: target == .newCard ? .tapNew : .findAccount))
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpOnHeaderAccent)
                Text(title)
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(which)
                    .chimpFont(.bodyS)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, ChimpSpacing.xxxl)
            .padding(.horizontal, 30)

            // La carte attendue, pas la tête de Chimpy (retour du 2026-10-01 : on ne savait pas quelle carte taper).
            ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 260) {
                ChimpCardThumbnail(color: nil, badge: target == .newCard ? "New" : nil)
                    .scaleEffect(1.25)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            if target == .accountCard {
                NewCardReadyBadge(name: model.displayCardName, number: model.cardNumber)
                    .padding(.bottom, ChimpSpacing.m)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                if let problem = model.problem {
                    ChimpySays(text: AddCardFlowView.message(for: problem.kind), pose: AddCardFlowView.pose(for: problem.kind))
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

    /// Quelle carte poser, en une phrase.
    private var which: LocalizedStringKey {
        switch target {
        case .newCard: "The card you're adding, not one that's already in your account."
        case .accountCard: "Any card already in the account you're joining. Not \(model.displayCardName)."
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
        .chimpPopIn()
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
            ChimpHeader(
                title: "Let \(model.displayCardName) in?",
                step: model.progress(at: .confirm)?.step ?? 0, steps: model.progressScreens.count,
                onBack: model.isLocked ? nil : onBack
            )
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpReviewSteps(steps: steps)
                    if model.pinMode == .choose, model.newCardMustSign {
                        ChimpNoticeBanner(text: "Your PIN can't be removed from the card. Have a pen ready: the card shows an unlock code only once.", marker: .error)
                    }
                    if let problem = model.problem {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: AddCardFlowView.message(for: problem.kind), pose: AddCardFlowView.pose(for: problem.kind))
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpButton(confirmTitle, isLoading: model.isBusy, action: model.openTapSheet)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .modifier(NewCardTapSheet(model: model))
    }

    /// « Continue » si le PIN vient ensuite (il ouvrira le tap tout seul), « Tap {carte} » s'il est déjà prêt.
    private var confirmTitle: LocalizedStringKey {
        model.newCardMustSign && !model.confirmLeadsToPIN ? "Tap \(model.displayCardName)" : "Continue"
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

/// Feuille du tap de la nouvelle carte (`set_owner`), sur la confirmation (rien à saisir) et sur l'écran du PIN.
/// Elle s'ouvre avec la fenêtre NFC d'iOS (`AutoScan`) ; « Scan my card » sert à retaper après une annulation ou un échec.
private struct NewCardTapSheet: ViewModifier {
    @Bindable var model: AddCardModel

    func body(content: Content) -> some View {
        content.chimpSheet(isPresented: $model.isShowingTapSheet, height: ChimpSize.cardTapSheetHeight, isDismissDisabled: model.isBusy) {
            CardTapSheet(
                cardName: model.displayCardName,
                cardColor: model.cardColor,
                cardBadge: "New",
                stepLabel: AddCardFlowView.stepLabel(model, at: model.screen == .pin ? .pin : .confirm),
                title: "Hold \(model.displayCardName), the new card, to your phone",
                what: "\(model.displayCardName) signs its link to your account.",
                who: model.pinMode == .choose ? "\(model.displayCardName) receives the PIN you just picked, then signs." : nil,
                pinStatus: model.pinMode == .none ? .notNeeded : .ready,
                isScanning: model.isBusy,
                isGettingReady: model.isGettingReady,
                problem: model.problem.map { AddCardFlowView.message(for: $0.kind) },
                problemDetails: model.problem?.technicalDetails,
                onScan: { Task { await model.scanNewCardToSign() } },
                onCancel: model.isBusy ? nil : { model.cancelTapSheet() }
            )
        }
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
                Text(AddCardFlowView.stepLabel(model, at: .member))
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpOnHeaderAccent)
                Text(title)
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("A card already in your account, not \(model.displayCardName). It vouches for the new one.")
                    .chimpFont(.bodyS)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, ChimpSpacing.xxxl)
            .padding(.horizontal, 30)

            // La carte attendue (sa couleur) ; grise tant qu'on ne sait pas laquelle.
            ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 230) {
                ChimpCardThumbnail(color: model.expectedMemberColor)
                    .scaleEffect(1.25)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            if model.member == nil, model.memberCandidates.count > 1 {
                memberChoice
                    .padding(.bottom, ChimpSpacing.m)
            } else {
                NewCardReadyBadge(name: model.displayCardName, number: model.cardNumber)
                    .padding(.bottom, ChimpSpacing.m)
            }

            ChimpySays(text: "A card can't invite itself. One of the gang has to vouch for it.", pose: .banana)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.m)

            ChimpButton("Scan my card", size: .large, isLoading: model.isBusy, action: model.startMemberStep)
                .disabled(model.needsMemberChoice)
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
                    stepLabel: AddCardFlowView.stepLabel(model, at: .member),
                    title: pinTitle,
                    subtitle: pinSubtitle,
                    pin: $model.memberPIN,
                    length: AddCardModel.pinLength,
                    state: $model.memberPINState,
                    onCancel: { model.cancelMemberStep() },
                    onComplete: model.memberPINEntered
                )
            } else {
                CardTapSheet(
                    cardName: model.expectedMemberName ?? "",
                    cardColor: model.expectedMemberColor,
                    stepLabel: AddCardFlowView.stepLabel(model, at: .member),
                    title: tapTitle,
                    what: "Letting \(model.displayCardName) into your account.",
                    pinStatus: model.memberUsesPIN ? .ready : .notNeeded,
                    isScanning: model.isBusy,
                    isGettingReady: model.isGettingReady,
                    problem: model.problem.map { AddCardFlowView.message(for: $0.kind) },
                    problemDetails: model.problem?.technicalDetails,
                    onScan: { Task { await model.scanMember() } },
                    onCancel: model.isBusy ? nil : { model.cancelMemberStep() }
                )
            }
        }
    }

    /// « Which card says yes? » : les cartes du compte (sauf la nouvelle), avec leur couleur. Le PIN demandé ensuite
    /// est celui de la carte choisie, et seule elle est acceptée au tap.
    private var memberChoice: some View {
        VStack(spacing: ChimpSpacing.xs) {
            Text("Which card says yes?")
                .chimpFont(.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(.chimpOnHeaderSecondary)
            // Centrées si elles tiennent, sinon elles défilent.
            ViewThatFits(in: .horizontal) {
                memberChips
                    .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                ScrollView(.horizontal, showsIndicators: false) {
                    memberChips
                        .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                        .padding(.vertical, ChimpSpacing.xxs)
                }
            }
        }
    }

    private var memberChips: some View {
        HStack(spacing: ChimpSpacing.s) {
            ForEach(model.memberCandidates) { card in
                MemberCardChip(
                    name: card.name ?? String(localized: "Card N°\(card.tokenID.map { String(format: "%04u", $0) } ?? "····")"),
                    color: card.color.flatMap(ChimpCardColor.init(rawValue:)),
                    isSelected: model.chosenMember?.publicKey == card.publicKey
                ) {
                    model.chooseMember(card.publicKey)
                }
            }
        }
    }

    private var title: LocalizedStringKey {
        if model.member != nil { return "Now tap that account's card again" }
        if let name = model.expectedMemberName { return "Now tap \(name)" }
        return "Now tap one of your cards"
    }

    /// À qui est ce PIN : jamais celui de la nouvelle carte.
    private var pinTitle: LocalizedStringKey {
        if let name = model.expectedMemberName { return "\(name)'s PIN" }
        return "PIN of the card you'll tap"
    }

    private var pinSubtitle: LocalizedStringKey {
        if let name = model.expectedMemberName {
            return "\(name) is already in your account. Not \(model.displayCardName)'s PIN."
        }
        return "A card already in your account. Not \(model.displayCardName)'s PIN."
    }

    private var tapTitle: LocalizedStringKey {
        if let name = model.expectedMemberName {
            return model.member == nil ? "Hold \(name) to your phone" : "Tap your \(name) card again"
        }
        if model.member != nil { return "Tap the same card again" }
        return "Tap any of your cards"
    }
}

/// Une carte du compte à choisir (G2) : pastille de sa couleur et son nom ; la carte choisie est jaune.
private struct MemberCardChip: View {
    let name: String
    let color: ChimpCardColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.xs) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color?.fill ?? Color(.chimpSurfaceSecondary))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                    .frame(width: 22, height: 15)
                Text(verbatim: name)
                    .chimpFont(.rowTitle)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
            .padding(.vertical, ChimpSpacing.s)
            .padding(.horizontal, ChimpSpacing.m)
            .frame(minHeight: ChimpSize.minimumTouchTarget)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: Capsule(),
            fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface),
            shadow: isSelected ? .tile : ChimpShadow(x: 0, y: 0)
        ))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    Image(.chimpyHearts)
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
