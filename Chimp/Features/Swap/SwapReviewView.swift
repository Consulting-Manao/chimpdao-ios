import SwiftUI

/// E4 · « Here's what happens » (maquette du 2026-10-14) : « You give » (exact), « You get about », **le minimum reçu**
/// exact et mis en avant (c'est ce que la carte signe), slippage, route, protocole, frais « On us », qui peut signer.
/// E4i : au-delà de 5 % d'impact, avertissement rouge, « Swap anyway » et « Change the amount ».
/// Puis les feuilles PIN et tap d'Envoyer (C5, C6), avec « Swapping 400 XLM for at least 99.18 USDC ».
/// E4p par-dessus quand le prix a bougé : rien n'a été signé, « See new price » ramène ici avec les nouvelles bornes.
///
/// Pendant la préparation, le scan et après la signature : pas de retour, ni par bouton ni par glissement.
struct SwapReviewView: View {
    @Bindable var model: SwapFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        Group {
            if model.showsStatus {
                SwapStatusView(model: model)
                    .toolbar(.hidden, for: .navigationBar)
            } else if case .wrongCard(let wrongCard, _) = model.stage {
                WrongCardView(wrongCard: wrongCard, onRetry: model.retryAfterWrongCard, onCancel: model.cancelSigning)
                    .toolbar(.hidden, for: .navigationBar)
                    .blocksSwipeBack(true)
            } else if let moved = model.priceMoved {
                SwapPriceMovedView(model: model, moved: moved)
                    .toolbar(.hidden, for: .navigationBar)
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
                title: "Here's what happens",
                subtitle: model.draft.map { "Swap in \(Self.shortTitle($0.drawer))" },
                onBack: model.isSigningLocked ? nil : { model.isReviewPresented = false }
            )
            if let draft = model.draft {
                ScrollView {
                    content(draft)
                        .padding(.horizontal, ChimpSpacing.xxl)
                        .padding(.vertical, ChimpSpacing.lg)
                }
            }
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                .padding(.horizontal, ChimpSpacing.bottomBar.leading)
                .padding(.top, ChimpSpacing.sm)
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

    static func shortTitle(_ drawer: SendDrawer) -> String {
        if case .main = drawer.kind { return String(localized: "Main") }
        return drawer.title
    }

    // MARK: Vérification

    private func content(_ draft: SwapDraft) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            if draft.quote.needsPriceImpactWarning {
                impactBanner(draft)
            }
            giveAndGet(draft)
            minimumCard(draft)
            details(draft)
            signerBanner(draft)
            if let issue = model.preparationIssue {
                VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                    ChimpFieldMessage(text: Self.message(for: issue, draft: draft), kind: .error)
                    if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
                }
            }
        }
    }

    /// E4i : « Price impact 7.8% », pourquoi, en rouge.
    private func impactBanner(_ draft: SwapDraft) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("Price impact \(SwapAmountView.percent(draft.quote.priceImpactBasisPoints ?? 0, locale: locale))")
                .chimpFont(.displayS)
            Text("This pool is small, so your swap pushes its price. You get a lot less \(draft.received.code) per \(draft.given.code) than the going rate.")
                .chimpFont(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 15)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpNegative), shadow: .card)
        .accessibilityElement(children: .combine)
    }

    /// « You give 400 XLM » (exact) et « You get about 99.68 USDC » (2 décimales).
    private func giveAndGet(_ draft: SwapDraft) -> some View {
        VStack(spacing: 0) {
            row(label: "You give") {
                Text(verbatim: draft.given.formattedWithCode(draft.amount, locale: locale))
            }
            row(label: "You get") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: draft.received.displayedWithCode(draft.quote.expectedOut, locale: locale))
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, ChimpSpacing.l)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: draft.quote.needsPriceImpactWarning ? nil : .card)
    }

    private func row(label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.m) {
            Text(label).chimpFont(.bodyS).fontWeight(.heavy).foregroundStyle(.chimpTextSecondary)
            Spacer(minLength: ChimpSpacing.s)
            value()
                .chimpFont(.displayM)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// Le minimum reçu, exact (7 décimales) : c'est le nombre que la carte signe (règle d'affichage du 2026-10-14).
    private func minimumCard(_ draft: SwapDraft) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("Minimum received")
                .textCase(.uppercase)
                .chimpFont(.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: Self.exact(draft.minimumOut, locale: locale))
                    .chimpFont(.monoAmount)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: draft.received.code)
                    .chimpFont(.monoValue)
            }
            Text(draft.quote.needsPriceImpactWarning
                 ? "This is what your card signs."
                 : "This is what your card signs. If less would arrive, the swap stops and nothing moves.")
                .chimpFont(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(.chimpOnAccent))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, ChimpSpacing.l)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.chimpCard), fill: Color(.chimpAccent), shadow: draft.quote.needsPriceImpactWarning ? nil : .card)
        .accessibilityElement(children: .combine)
    }

    /// Quantité exacte à 7 décimales (« 99.1816000 »), selon la région du téléphone.
    static func exact(_ amount: Decimal, locale: Locale) -> String {
        amount.formatted(.number.locale(locale).precision(.fractionLength(7)))
    }

    /// Slippage, route, protocole, frais (police Space Mono, comme la maquette).
    private func details(_ draft: SwapDraft) -> some View {
        VStack(spacing: 0) {
            detail("Slippage", Text(verbatim: SwapAmountView.percent(draft.slippageBasisPoints, locale: locale)))
            detail("Route", Text(verbatim: draft.quote.route.map(\.code).joined(separator: " → ")))
            detail("Protocol", Text(verbatim: draft.quote.protocolName))
            detail("Fees", Text("On us").foregroundStyle(Color(.chimpPositive)))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 15)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
    }

    private func detail(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack(spacing: ChimpSpacing.m) {
            Text(label).foregroundStyle(.chimpTextSecondary)
            Spacer(minLength: ChimpSpacing.s)
            value.fontWeight(.bold).foregroundStyle(.chimpTextPrimary)
        }
        .chimpFont(.mono)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func signerBanner(_ draft: SwapDraft) -> some View {
        switch draft.drawer.kind {
        case let .card(name, color):
            ChimpNoticeBanner(text: "Only your \(name) card can sign. The \(draft.given.code) is in its own wallet.", marker: .card(color))
        case .main:
            ChimpNoticeBanner(text: "Any of your cards can sign. The \(draft.given.code) is in Main.", marker: .card(.banana))
        }
    }

    static func message(for issue: SwapFlowModel.PreparationIssue, draft: SwapDraft) -> LocalizedStringKey {
        switch issue {
        case .insufficientBalance: "Not enough \(draft.given.code) in \(draft.drawer.title). Nothing was signed."
        case .noRoute: "\(draft.quote.protocolName) has no route for this pair right now. Nothing was signed."
        case .protocolUnavailable: "\(draft.quote.protocolName) is unavailable right now. Nothing was signed. Try again in a minute."
        case .priceMoved: "The price moved. Nothing was signed."
        case .other: "Couldn't get ready to swap. Nothing was signed. Check your connection and try again."
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: ChimpSpacing.sm) {
            if let draft = model.draft, draft.quote.needsPriceImpactWarning {
                ChimpButton("Swap anyway", kind: .destructive, isLoading: model.stage == .preparing) { model.confirmReview() }
                    .disabled(model.stage != .idle && model.stage != .preparing)
                ChimpButton("Change the amount", kind: .secondary) { model.changeAmount() }
                    .disabled(model.stage != .idle)
            } else {
                Text("Swaps can't be undone once signed.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChimpButton("Looks good", isLoading: model.stage == .preparing) { model.confirmReview() }
                    .disabled(model.stage != .idle && model.stage != .preparing)
            }
        }
    }

    // MARK: Feuilles de signature (reprises d'Envoyer)

    @ViewBuilder
    private var signingSheet: some View {
        if let draft = model.draft, let step = model.currentSigningStep {
            switch step {
            case .pin:
                PinSheet(
                    stepLabel: stepLabel(for: .pin),
                    title: pinTitle(draft),
                    subtitle: whatIsSigned(draft),
                    pin: $model.pin,
                    length: model.pinLength,
                    state: $model.pinState,
                    saysNothingWasSent: true,
                    onCancel: { model.cancelSigning() },
                    onComplete: model.pinEntered
                )
            case .tapToRead, .tapToSign:
                let card = tapCard(draft)
                CardTapSheet(
                    cardName: card.name,
                    cardColor: card.color,
                    stepLabel: stepLabel(for: step),
                    title: tapTitle(draft, step: step),
                    what: whatIsSigned(draft),
                    pinStatus: pinStatus(for: step),
                    isScanning: model.isSigningLocked,
                    problem: model.tapProblem.map(SendReviewView.message(for:)),
                    problemDetails: model.tapProblem == nil ? nil : model.technicalDetails,
                    onScan: model.scanCard,
                    onCancel: model.isSigningLocked ? nil : { model.cancelSigning() }
                )
            }
        }
    }

    /// « Swapping 400 XLM for at least 99.18 USDC » (maquette E4k) : le minimum, à 2 décimales dans la feuille.
    private func whatIsSigned(_ draft: SwapDraft) -> LocalizedStringKey {
        "Swapping \(draft.given.formattedWithCode(draft.amount, locale: locale)) for at least \(draft.received.displayedWithCode(draft.minimumOut, locale: locale))"
    }

    private func stepLabel(for step: SigningStep) -> LocalizedStringKey {
        let steps = model.signingSteps
        let isPin = step == .pin
        guard steps.count > 1, let index = steps.firstIndex(of: step) else {
            return isPin ? "Last step · PIN" : "Last step · Tap"
        }
        return isPin ? "Step \(index + 1) of \(steps.count) · PIN" : "Step \(index + 1) of \(steps.count) · Tap"
    }

    private func pinTitle(_ draft: SwapDraft) -> LocalizedStringKey {
        if let check = model.cardCheck { return "\(check.cardName)'s PIN" }
        switch draft.drawer.kind {
        case .card(let name, _): return "\(name)'s PIN"
        case .main: return "PIN of the card you'll tap"
        }
    }

    private func tapCard(_ draft: SwapDraft) -> (name: String, color: ChimpCardColor?) {
        if let check = model.cardCheck { return (check.cardName, check.cardColor) }
        switch draft.drawer.kind {
        case let .card(name, color): return (name, color)
        case .main: return ("", nil)
        }
    }

    private func tapTitle(_ draft: SwapDraft, step: SigningStep) -> LocalizedStringKey? {
        if step == .tapToSign, let check = model.cardCheck { return "Tap your \(check.cardName) card again" }
        if case .main = draft.drawer.kind { return "Tap any of your cards" }
        return nil
    }

    private func pinStatus(for step: SigningStep) -> CardTapPinStatus {
        if step == .tapToRead { return .afterTap }
        return model.signingSteps.contains(.pin) ? .ready : .notNeeded
    }
}

/// E4p · « The price moved » : écran plein (couleur de l'en-tête et motif), Chimpy qui renifle, rien n'a été signé,
/// l'ancien minimum barré, le nouveau, puis « See new price » (retour à la vérification complète).
struct SwapPriceMovedView: View {
    @Bindable var model: SwapFlowModel
    let moved: SwapFlowModel.PriceMoved

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                Image(.chimpySniff)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 220)
                    .accessibilityHidden(true)
                Text("The price moved")
                    .chimpFont(.displayL)
                    .foregroundStyle(Color(.chimpOnHeaderPrimary))
                    .accessibilityAddTraits(.isHeader)
                if let draft = model.draft {
                    Text("Prices swing faster than I do. Nothing was signed, and your \(draft.given.formattedWithCode(draft.amount, locale: locale)) is still in \(SwapReviewView.shortTitle(draft.drawer)).")
                        .chimpFont(.bodyL)
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                minimums
                if moved.failed {
                    Text("I couldn't get the new price. Check your connection and try again.")
                        .chimpFont(.caption)
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            Group {
                if moved.failed {
                    ChimpButton("Try again") { Task { await model.fetchNewPrice() } }
                } else {
                    ChimpButton("See new price", isLoading: moved.newDraft == nil) { model.acceptNewPrice() }
                        .disabled(moved.newDraft == nil)
                }
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }

    /// « MINIMUM RECEIVED · 99.18 USDC → 98.60 USDC ».
    private var minimums: some View {
        VStack(spacing: ChimpSpacing.xxs) {
            Text("Minimum received")
                .textCase(.uppercase)
                .chimpFont(.label)
                .foregroundStyle(Color(.chimpOnHeaderSecondary))
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.m) {
                Text(verbatim: moved.received.displayedWithCode(moved.oldMinimum, locale: locale))
                    .chimpFont(.greeting)
                    .strikethrough()
                    .foregroundStyle(Color(.chimpOnHeaderSecondary))
                    .accessibilityLabel(Text("Before: \(moved.received.displayedWithCode(moved.oldMinimum, locale: locale))"))
                Text(verbatim: "→").chimpFont(.greeting).foregroundStyle(Color(.chimpOnHeaderPrimary)).accessibilityHidden(true)
                if let newDraft = moved.newDraft {
                    Text(verbatim: moved.received.displayedWithCode(newDraft.minimumOut, locale: locale))
                        .chimpFont(.amountM)
                        .foregroundStyle(Color(.chimpOnHeaderAccent))
                        .accessibilityLabel(Text("Now: \(moved.received.displayedWithCode(newDraft.minimumOut, locale: locale))"))
                } else {
                    ProgressView().tint(Color(.chimpOnHeaderPrimary))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, ChimpSpacing.l)
        .background(RoundedRectangle(cornerRadius: ChimpRadius.control).fill(.black.opacity(0.22)))
        .overlay { RoundedRectangle(cornerRadius: ChimpRadius.control).strokeBorder(.white.opacity(0.45), lineWidth: ChimpBorder.regular) }
        .accessibilityElement(children: .combine)
    }
}
