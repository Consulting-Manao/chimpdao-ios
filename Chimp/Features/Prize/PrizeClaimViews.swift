import SwiftUI

/// Entrée de « Somebody likes you! » (carte partenaire, D5) : en plein écran au-dessus du Wallet (dans une pile de
/// navigation), ou poussée dans la pile du Wallet pour reprendre un retrait en attente (`gift == nil` : son état, jamais un
/// nouveau retrait). Un ViewModel neuf à chaque ouverture.
struct PrizeClaimRoot: View {
    @State private var model: PrizeClaimModel

    init(service: PrizeService, gift: PrizeGift?, onExit: @escaping () -> Void) {
        let model = PrizeClaimModel(service: service, gift: gift)
        model.onExit = onExit
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.resumedPending {
                // Une opération signée attend encore son issue : son état, jamais une nouvelle.
                PrizeStatusView(model: model)
            } else {
                PrizeGiftView(model: model)
                    .navigationDestination(isPresented: $model.isReviewPresented) {
                        PrizeReviewView(model: model)
                            .toolbar(.hidden, for: .navigationBar)
                    }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadIfNeeded() }
        // Règle 8 : dans un parcours qui fait signer, les montants restent visibles même si l'œil est fermé.
        .chimpShowsAmounts()
    }
}

// MARK: - H1 · « Somebody likes you! »

/// La maquette H1 (« Somebody likes you! », Chimpy et ses cœurs, la carte et ce qu'elle contient), pour une carte du
/// compte qui a de l'argent mis de côté. Deux choix : « Open it » (la vérification) et « Later ».
struct PrizeGiftView: View {
    @Bindable var model: PrizeClaimModel

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if let gift = model.gift {
                    VStack(spacing: 9) {
                        ChimpCard(
                            name: gift.cardName, color: gift.cardColor, number: gift.cardNumber ?? "····",
                            amount: gift.asset.displayedWithCode(gift.amount, locale: locale), subtitle: "waiting for you"
                        )
                        .frame(width: 230)
                        .padding(.top, ChimpSpacing.xxl)
                        .padding(.bottom, ChimpSpacing.xxxl)
                        Text("Someone put this aside for your \(gift.cardName) card. Only \(gift.cardName) can open it: one tap, and it lands in its wallet.")
                            .chimpFont(.body)
                            .foregroundStyle(.chimpTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.blockedByPendingPayment {
                            ChimpNoticeBanner(text: "Another payment is still being checked. Open it from your wallet first, then come back for your gift.", marker: .error)
                                .padding(.top, ChimpSpacing.m)
                        }
                    }
                    .padding(.horizontal, ChimpSpacing.xxl)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 11) {
                ChimpButton("Open it", action: model.open)
                    .disabled(model.gift == nil || model.blockedByPendingPayment)
                ChimpButton("Later", kind: .secondary, action: model.finish)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.l)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: ChimpSpacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Somebody\nlikes you!")
                    .chimpFont(.tourTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("This card came with bananas.")
                    .chimpFont(.bodyL)
            }
            .foregroundStyle(Color(.chimpOnCardBright))
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(.chimpyHearts)
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .padding(.bottom, -30)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.top, ChimpSpacing.xl)
        .padding(.bottom, 26)
        .background {
            Color(.chimpCardLeaf)
                .overlay { ChimpPattern() }
                .ignoresSafeArea(edges: .top)
        }
        .zIndex(1)
    }
}

// MARK: - Vérification

/// « Check it over » : ce qui arrive, où, qui signe et les frais, dit **avant** la session NFC (règle 8). Puis les feuilles
/// PIN et tap d'Envoyer.
struct PrizeReviewView: View {
    @Bindable var model: PrizeClaimModel

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        Group {
            if model.showsStatus {
                PrizeStatusView(model: model)
            } else if case .wrongCard(let wrongCard) = model.stage {
                WrongCardView(wrongCard: wrongCard, onRetry: model.retryAfterWrongCard, onCancel: model.cancelSigning)
                    .blocksSwipeBack(true)
            } else {
                review
            }
        }
        .onChange(of: model.stage) { old, new in
            if let sound = new.sound, old.sound != sound { ChimpSoundPlayer.shared.play(sound) }
        }
        .chimpSound(.error, trigger: model.tapProblem) { _, new in new != nil }
        .chimpSound(.error, trigger: model.preparationIssue) { _, new in new != nil }
    }

    private var review: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: "Check it over", step: 2, steps: 2,
                onBack: model.isSigningLocked ? nil : { model.isReviewPresented = false }
            )
            if let gift = model.gift {
                ScrollView {
                    content(gift)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, ChimpSpacing.l)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpButton("Tap your card", isLoading: model.stage == .preparing) { model.confirmReview() }
                .disabled((model.stage != .idle && model.stage != .preparing) || !canSign)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
        .blocksSwipeBack(model.isSigningLocked)
        .chimpSheet(
            isPresented: Binding(
                get: { model.isSigningSheetPresented },
                set: { isPresented in if !isPresented { model.cancelSigning() } }
            ),
            height: model.currentSigningStep == .pin ? ChimpSize.sheetHeight : ChimpSize.cardTapSheetHeight,
            isDismissDisabled: model.isSigningLocked
        ) {
            signingSheet
        }
    }

    /// Plus rien à ouvrir, ou la carte ne peut plus : le bouton reste grisé.
    private var canSign: Bool {
        switch model.preparationIssue {
        case .alreadyOpened, .notOwner, .unknownCard: false
        case .amountChanged, .other, nil: true
        }
    }

    private func content(_ gift: PrizeGift) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ChimpPaperReceipt(padding: EdgeInsets(top: 26, leading: 20, bottom: 18, trailing: 20)) {
                VStack(spacing: 0) {
                    Text("You get")
                        .textCase(.uppercase)
                        .chimpFont(.label)
                        .foregroundStyle(Color(.chimpTicketMuted))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: gift.asset.displayed(gift.amount, locale: locale))
                            .chimpFont(.plantAmount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        Text(verbatim: gift.asset.code).chimpFont(.plantUnit).foregroundStyle(Color(.chimpTicketMuted))
                    }
                    .padding(.top, 4)
                    ChimpReceiptRule().padding(.vertical, 18)
                    VStack(spacing: 0) {
                        ChimpReceiptRow(label: "Lands in", value: gift.walletTitle)
                        ChimpReceiptRow(label: "Signed by", value: String(localized: "your \(gift.cardName) card"))
                        ChimpReceiptRow(label: "Fees", value: gift.asset.formattedWithCode(0, locale: locale), tone: .positive)
                    }
                    Text("Your card signs this claim, and nothing else: no money leaves your wallets.")
                        .chimpFont(.caption)
                        .foregroundStyle(Color(.chimpTicketMuted))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .accessibilityElement(children: .combine)
            }
            ChimpySays(text: gift.usesPin
                ? "Only your \(gift.cardName) card can open it. Your PIN, one tap, and it's yours!"
                : "Only your \(gift.cardName) card can open it. One tap, and it's yours!", pose: .wave)
                .padding(.top, 18)
            if let issue = model.preparationIssue {
                VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                    ChimpFieldMessage(text: Self.message(for: issue, gift: gift, locale: locale), kind: issue == .amountChanged ? .info : .error)
                    if let details = model.technicalDetails, issue != .amountChanged { ChimpTechnicalDetails(details: details) }
                }
                .padding(.top, ChimpSpacing.m)
            }
        }
    }

    static func message(for issue: PrizeClaimModel.PreparationIssue, gift: PrizeGift, locale: Locale) -> LocalizedStringKey {
        switch issue {
        case .amountChanged: "The gift changed: it's now \(gift.asset.displayedWithCode(gift.amount, locale: locale)). Nothing was signed. Check it, then tap your card."
        case .alreadyOpened: "This gift was already opened, maybe from another phone. Nothing was signed."
        case .notOwner: "\(gift.cardName)'s wallet can't open this gift. Nothing was signed."
        case .unknownCard: "\(gift.cardName) isn't on your account anymore. Nothing was signed."
        case .other: "Couldn't get ready. Nothing was signed. Check your connection and try again."
        }
    }

    // MARK: Feuilles de signature (reprises d'Envoyer)

    @ViewBuilder
    private var signingSheet: some View {
        if let gift = model.gift, let step = model.currentSigningStep {
            switch step {
            case .pin:
                PinSheet(
                    stepLabel: stepLabel(for: .pin),
                    title: "\(gift.cardName)'s PIN",
                    subtitle: whatIsSigned(gift),
                    pin: $model.pin,
                    length: model.pinLength,
                    state: $model.pinState,
                    saysNothingWasSent: true,
                    onCancel: { model.cancelSigning() },
                    onComplete: model.pinEntered
                )
            case .tapToRead, .tapToSign:
                CardTapSheet(
                    cardName: gift.cardName,
                    cardColor: gift.cardColor,
                    stepLabel: stepLabel(for: step),
                    title: nil,
                    what: whatIsSigned(gift),
                    pinStatus: model.signingSteps.contains(.pin) ? .ready : .notNeeded,
                    isScanning: model.isSigningLocked,
                    isGettingReady: model.isGettingReady,
                    problem: model.tapProblem.map { SendReviewView.message(for: $0) },
                    problemDetails: model.tapProblem == nil ? nil : model.technicalDetails,
                    onScan: model.scanCard,
                    onCancel: model.isSigningLocked ? nil : { model.cancelSigning() }
                )
            }
        }
    }

    /// « Opening a gift of 250 XLM for Banana ».
    private func whatIsSigned(_ gift: PrizeGift) -> LocalizedStringKey {
        "Opening a gift of \(gift.asset.displayedWithCode(gift.amount, locale: locale)) for \(gift.cardName)"
    }

    private func stepLabel(for step: SigningStep) -> LocalizedStringKey {
        let steps = model.signingSteps
        let isPin = step == .pin
        guard steps.count > 1, let index = steps.firstIndex(of: step) else {
            return isPin ? "Last step · PIN" : "Last step · Tap"
        }
        return isPin ? "Step \(index + 1) of \(steps.count) · PIN" : "Step \(index + 1) of \(steps.count) · Tap"
    }
}

// MARK: - Après le tap

/// Après le tap (écrans du vault, textes du cadeau). On n'en sort que par leurs boutons.
/// - « Opening it… » : les étapes ; « It's yours! » : le reçu ; « Not sure yet » → « Check again » ;
///   « Not moved » : la signature peut encore servir → attendre ; « Nothing was moved » : certain → « Try again ».
struct PrizeStatusView: View {
    @Bindable var model: PrizeClaimModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var seed = ChimpyLines.seed()

    var body: some View {
        Group {
            switch model.stage {
            case .finished(.sent(let receipt)):
                PrizeSentView(receipt: receipt, onDone: model.finish)
            case .finished(.notConfirmed), .finished(.undetermined):
                fullScreen(pose: .chimpyTeacher, title: "Not sure yet",
                           text: "We couldn't confirm it. Your gift may already be in \(model.shownGift?.walletTitle ?? String(localized: "your card's wallet")). Check again before trying anything else.") {
                    ChimpButton("Check again", action: model.checkAgain)
                    if let url = model.explorerURL {
                        ChimpButton("View on Stellar Expert", kind: .linkOnHeader) { openURL(url) }
                    }
                    ChimpButton("Back to my wallet", kind: .linkOnHeader, action: model.finish)
                }
            case .finished(.nothingSent):
                fullScreen(pose: .chimpyPeel, title: "Nothing was moved",
                           text: "The network said no. Your gift is still waiting for \(model.shownGift?.cardName ?? String(localized: "your card")), safe and sound. Probably a hiccup.") {
                    if model.canTryAgain {
                        ChimpButton("Try again", action: model.tryAgain)
                        ChimpButton("Back to my wallet", kind: .linkOnHeader, action: model.finish)
                    } else {
                        ChimpButton("Back to my wallet", action: model.finish)
                    }
                }
            default:
                statusScreen
            }
        }
        .blocksSwipeBack(true)
    }

    private func fullScreen(
        pose: ImageResource, title: LocalizedStringKey, text: LocalizedStringKey, @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                Image(pose).resizable().scaledToFit().frame(height: 230).accessibilityHidden(true)
                Text(title)
                    .chimpFont(.displayL)
                    .foregroundStyle(Color(.chimpOnHeaderPrimary))
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .chimpFont(.bodyL)
                    .foregroundStyle(Color(.chimpOnHeaderSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = model.failureReason {
                    Text(SendStatusView.message(for: reason))
                        .chimpFont(.caption)
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                }
                if model.pendingSaveFailed {
                    Text("This phone couldn't save this operation. Don't try again before you've checked it.")
                        .chimpFont(.captionStrong)
                        .foregroundStyle(Color(.chimpOnHeaderPrimary))
                        .multilineTextAlignment(.center)
                }
                if let details = model.technicalDetails {
                    ChimpTechnicalDetails(details: details)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.xs) { actions() }
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }

    private var statusScreen: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    content
                    if model.pendingSaveFailed {
                        ChimpNoticeBanner(text: "This phone couldn't save this operation. Don't try again before you've checked it.", marker: .error)
                    }
                    if let gift = model.shownGift {
                        ChimpDetailList(items: [
                            ChimpDetailItem(id: "gift", label: "Gift", value: gift.asset.displayedWithCode(gift.amount, locale: locale)),
                            ChimpDetailItem(id: "to", label: "Lands in", value: gift.walletTitle),
                        ])
                    }
                    if let details = model.technicalDetails, case .finished = model.stage {
                        ChimpTechnicalDetails(details: details)
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

    private var title: LocalizedStringKey {
        switch model.stage {
        case .finished(.waiting): "Not moved"
        case .checking: "Checking with Stellar"
        default: "Opening it…"
        }
    }

    private var subtitle: LocalizedStringKey? {
        switch model.stage {
        case .sending, .checking: "Keep the app open"
        default: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .sending(let progress):
            ChimpProgressSteps(steps: sendingSteps(progress))
            Text(ChimpyLines.pick(ChimpyLines.sending, seed: seed))
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
        case .checking:
            HStack(spacing: ChimpSpacing.m) {
                ProgressView()
                Text("Checking with Stellar").chimpFont(.reviewStep).foregroundStyle(.chimpTextPrimary)
            }
        case .finished(.waiting(let until)):
            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                Text(model.canResend
                     ? "Not opened yet. Your card's signature still works until \(until.formatted(date: .omitted, time: .shortened))."
                     : "Not opened. Please wait until \(until.formatted(date: .omitted, time: .shortened)) before trying again.")
                    .chimpFont(.sheetTitle)
                    .foregroundStyle(.chimpTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.canResend {
                    Text("Try again sends that same signature again, with no new tap. It can only go through once.")
                        .chimpFont(.body)
                        .foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, until.timeIntervalSince(context.date))
                    Text(Duration.seconds(Int(seconds.rounded(.up))).formatted(.time(pattern: .minuteSecond)))
                        .chimpFont(.amountL)
                        .monospacedDigit()
                        .foregroundStyle(.chimpTextPrimary)
                        .accessibilityLabel(Text("Time left"))
                }
            }
            if let reason = model.failureReason {
                ChimpFieldMessage(text: SendStatusView.message(for: reason), kind: .info)
            }
        default:
            EmptyView()
        }
    }

    private func sendingSteps(_ progress: PaymentProgress) -> [ChimpProgressStep] {
        let order: [PaymentProgress] = [.checking, .sending, .confirming]
        let reached = order.firstIndex(of: progress) ?? 0
        let labels = [Text("Checking with Stellar"), Text("Opening your gift"), Text("Confirming")]
        var steps = [ChimpProgressStep(id: 0, label: Text("Signed by \(model.shownGift?.cardName ?? "")"), state: .done)]
        for (index, label) in labels.enumerated() {
            let state: ChimpProgressStep.State = index < reached ? .done : (index == reached ? .current : .todo)
            steps.append(ChimpProgressStep(id: index + 1, label: label, state: state))
        }
        return steps
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: ChimpSpacing.xs) {
            switch model.stage {
            case .finished(.waiting):
                if model.canResend {
                    ChimpButton("Try again", action: model.resend)
                    ChimpButton("Back to my wallet", kind: .link, action: model.finish)
                } else {
                    ChimpButton("Back to my wallet", kind: .secondary, action: model.finish)
                }
            default:
                ChimpButton("Back to my wallet", isLoading: true) {}
                    .disabled(true)
            }
        }
    }
}

/// « It's yours! » : fond vert et motif, Chimpy et ses cœurs, ce qui est entré et où ; « Done ».
struct PrizeSentView: View {
    let receipt: PrizeReceipt
    let onDone: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 0) {
                Image(.chimpyHearts)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .chimpBob(duration: 3.5)
                    .accessibilityHidden(true)
                Text("It's yours!")
                    .chimpFont(.growCelebration)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text("\(receipt.gift.asset.displayedWithCode(receipt.gift.amount, locale: locale)) is in \(receipt.gift.walletTitle), ready to use.")
                    .chimpFont(.bodyL)
                    .fontWeight(.heavy)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(.chimpTicketInk))
            .padding(.horizontal, 28)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 14) {
                ChimpButton("Done", action: onDone)
                if let url = receipt.explorerURL {
                    Button { openURL(url) } label: {
                        Text("View on Stellar Expert")
                            .chimpFont(.link)
                            .foregroundStyle(Color(.chimpTicketInk))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .background {
            Color(.chimpCardLeaf)
                .overlay { ChimpPattern(opacity: 0.14) }
                .ignoresSafeArea()
        }
    }
}
