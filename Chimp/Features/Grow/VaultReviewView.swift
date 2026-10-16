import SwiftUI

/// F4 et F7r · « Here's what happens » (maquettes du 2026-10-15) : ce qui part, le vault, les protocoles, les frais
/// « On us », qui peut signer, l'avertissement. Retirer : le minimum reçu exact, mis en avant (c'est ce que la carte
/// signe), comme le swap. Les parts ne s'affichent que sur les reçus (décision de Barth du 2026-10-15).
/// Puis les feuilles PIN et tap d'Envoyer (F4k, F4t, F7k, F7t). Par-dessus : « le montant a bougé » (comme E4p).
struct VaultReviewView: View {
    @Bindable var model: VaultFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        Group {
            if model.showsStatus {
                VaultStatusView(model: model)
                    .toolbar(.hidden, for: .navigationBar)
            } else if case .wrongCard(let wrongCard, _) = model.stage {
                WrongCardView(wrongCard: wrongCard, onRetry: model.retryAfterWrongCard, onCancel: model.cancelSigning)
                    .toolbar(.hidden, for: .navigationBar)
                    .blocksSwipeBack(true)
            } else if let moved = model.amountMoved {
                VaultAmountMovedView(model: model, moved: moved)
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
                subtitle: model.draft.map { draft in
                    draft.action == .deposit
                        ? "Put money in · from \(GrowView.shortTitle(draft.drawer))"
                        : "Take money out · back to \(GrowView.shortTitle(draft.drawer))"
                },
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
            VStack(spacing: ChimpSpacing.sm) {
                Text("Vaults can earn little or nothing. Not guaranteed.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChimpButton("Looks good", isLoading: model.stage == .preparing) { model.confirmReview() }
                    .disabled(model.stage != .idle && model.stage != .preparing)
            }
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

    // MARK: Vérification

    private func content(_ draft: VaultDraft) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            amounts(draft)
            if draft.action == .withdraw, let minimum = draft.quote.minimum {
                minimumCard(minimum, asset: draft.vault.asset, lending: draft.vault.kind == .lending)
            }
            details(draft)
            signerBanner(draft)
            if draft.vault.kind == .lending {
                LendingRiskNotice(asset: draft.vault.asset.code)
            } else {
                ChimpVaultNotice(asset: draft.vault.asset.code, protocols: draft.vault.protocols)
            }
            if let issue = model.preparationIssue {
                VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                    ChimpFieldMessage(text: Self.message(for: issue, draft: draft, locale: locale), kind: .error)
                    if issue == .notEnoughLiquidity, let now = draft.vault.availableNow as Decimal?, now > 0 {
                        ChimpButton("Take out \(draft.vault.asset.displayedWithCode(now, locale: locale))", kind: .secondary, size: .compact) {
                            model.takeOutAvailableNow()
                        }
                    }
                    if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
                }
            }
        }
    }

    /// Mettre : « You put in 50 XLM » (exact). Retirer : « You get about 50.12 XLM ».
    private func amounts(_ draft: VaultDraft) -> some View {
        let asset = draft.vault.asset
        return VStack(spacing: 0) {
            if draft.action == .deposit {
                row(label: "You put in") { Text(verbatim: asset.formattedWithCode(draft.amount, locale: locale)) }
            } else {
                row(label: "You get") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Prêt : un montant exact (pas de parts), sauf « tout », qui comprend les intérêts du moment.
                        if draft.vault.kind != .lending || draft.quote.all {
                            Text(draft.vault.kind == .lending ? "at least" : "about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                        }
                        Text(verbatim: asset.displayedWithCode(draft.quote.expected ?? draft.amount, locale: locale))
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, ChimpSpacing.l)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
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

    /// Retirer : le minimum reçu, exact (7 décimales) : c'est ce que la carte signe.
    private func minimumCard(_ minimum: Decimal, asset: SendAsset, lending: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text(lending ? "Comes back" : "Minimum received").textCase(.uppercase).chimpFont(.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: SwapReviewView.exact(minimum, locale: locale))
                    .chimpFont(.monoAmount)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: asset.code).chimpFont(.monoValue)
            }
            Text(lending ? "This is what your card signs. If XOXNO can't pay it right now, nothing moves." : "This is what your card signs. If the vault would pay less, nothing moves.")
                .chimpFont(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(.chimpOnAccent))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, ChimpSpacing.l)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.chimpCard), fill: Color(.chimpAccent), shadow: .card)
        .accessibilityElement(children: .combine)
    }

    /// Vault, protocoles, (retirer : où ça revient), frais.
    private func details(_ draft: VaultDraft) -> some View {
        VStack(spacing: 0) {
            if draft.vault.kind == .lending {
                detail("Market", Text(verbatim: draft.vault.name))
            } else {
                detail("Vault", Text(verbatim: "\(draft.vault.name) vault"))
            }
            detail("Protocols", Text(verbatim: draft.vault.protocolChain))
            if draft.action == .withdraw {
                detail("Lands in", Text(verbatim: GrowView.shortTitle(draft.drawer)))
            }
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
            value.fontWeight(.bold).foregroundStyle(.chimpTextPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .chimpFont(.mono)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func signerBanner(_ draft: VaultDraft) -> some View {
        let what: LocalizedStringKey = draft.action == .deposit ? "The \(draft.vault.asset.code)" : "The position"
        switch draft.drawer.kind {
        case let .card(name, color):
            ChimpNoticeBanner(text: "Only your \(name) card can sign. \(Text(what)) is in its own wallet.", marker: .card(color))
        case .main:
            ChimpNoticeBanner(text: "Any of your cards can sign. \(Text(what)) is in Main.", marker: .card(.banana))
        }
    }

    static func message(for issue: VaultFlowModel.PreparationIssue, draft: VaultDraft, locale: Locale) -> LocalizedStringKey {
        let asset = draft.vault.asset
        switch issue {
        case .insufficientBalance: return "Not enough \(asset.code) in \(draft.drawer.title). Nothing was signed."
        case .notEnoughShares: return "The position doesn't hold that much anymore. Nothing was signed."
        case .notEnoughLiquidity where draft.vault.kind == .lending:
            return "XOXNO can't pay that much back right now: it's lent out. Nothing was signed."
        case .notEnoughLiquidity:
            return "The vault can give back \(asset.displayedWithCode(draft.vault.availableNow, locale: locale)) right now. The rest is lent on Blend and comes back as borrowers repay."
        case .vaultUnavailable where draft.vault.kind == .lending:
            return "XOXNO is paused or unavailable right now. Nothing moved. Try again later."
        case .vaultUnavailable: return "The vault is unavailable right now. Nothing moved. Try again in a minute."
        case .capReached: return "XOXNO isn't taking more deposits in this market right now. Nothing was signed."
        case .implausible: return "The vault's numbers don't look right, so I won't sign. Nothing was signed."
        case .priceMoved: return "The vault moved. Nothing was signed."
        case .other: return "Couldn't get ready. Nothing was signed. Check your connection and try again."
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

    /// « Putting 50 XLM in the DeFindex vault », « Taking about 50.12 XLM out of the DeFindex vault » (F4k, F7k).
    private func whatIsSigned(_ draft: VaultDraft) -> LocalizedStringKey {
        let asset = draft.vault.asset
        let runner = draft.vault.protocols.first ?? "DeFindex"
        if draft.vault.kind == .lending {
            return draft.action == .deposit
                ? "Putting \(asset.formattedWithCode(draft.amount, locale: locale)) in \(runner)"
                : "Taking \(asset.displayedWithCode(draft.quote.expected ?? draft.amount, locale: locale)) out of \(runner)"
        }
        if draft.action == .deposit {
            return "Putting \(asset.formattedWithCode(draft.amount, locale: locale)) in the \(runner) vault"
        }
        return "Taking about \(asset.displayedWithCode(draft.quote.expected ?? draft.amount, locale: locale)) out of the \(runner) vault"
    }

    private func stepLabel(for step: SigningStep) -> LocalizedStringKey {
        let steps = model.signingSteps
        let isPin = step == .pin
        guard steps.count > 1, let index = steps.firstIndex(of: step) else {
            return isPin ? "Last step · PIN" : "Last step · Tap"
        }
        return isPin ? "Step \(index + 1) of \(steps.count) · PIN" : "Step \(index + 1) of \(steps.count) · Tap"
    }

    private func pinTitle(_ draft: VaultDraft) -> LocalizedStringKey {
        if let check = model.cardCheck { return "\(check.cardName)'s PIN" }
        switch draft.drawer.kind {
        case .card(let name, _): return "\(name)'s PIN"
        case .main: return "PIN of the card you'll tap"
        }
    }

    private func tapCard(_ draft: VaultDraft) -> (name: String, color: ChimpCardColor?) {
        if let check = model.cardCheck { return (check.cardName, check.cardColor) }
        switch draft.drawer.kind {
        case let .card(name, color): return (name, color)
        case .main: return ("", nil)
        }
    }

    private func tapTitle(_ draft: VaultDraft, step: SigningStep) -> LocalizedStringKey? {
        if step == .tapToSign, let check = model.cardCheck { return "Tap your \(check.cardName) card again" }
        if case .main = draft.drawer.kind { return "Tap any of your cards" }
        return nil
    }

    private func pinStatus(for step: SigningStep) -> CardTapPinStatus {
        if step == .tapToRead { return .afterTap }
        return model.signingSteps.contains(.pin) ? .ready : .notNeeded
    }
}

/// Le montant a bougé (comme E4p, décision de Barth du 2026-10-15) : rien n'a été signé, l'ancien barré, le nouveau, puis
/// « See new amount » (retour à la vérification complète).
struct VaultAmountMovedView: View {
    @Bindable var model: VaultFlowModel
    let moved: VaultFlowModel.AmountMoved

    @Environment(\.locale) private var locale

    private var isWithdraw: Bool { model.draft?.action == .withdraw }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                Image(.chimpySniff).resizable().scaledToFit().frame(height: 220).accessibilityHidden(true)
                Text("The vault moved")
                    .chimpFont(.displayL)
                    .foregroundStyle(Color(.chimpOnHeaderPrimary))
                    .accessibilityAddTraits(.isHeader)
                if let draft = model.draft {
                    Text("Nothing was signed, and your \(draft.vault.asset.code) is still where it was. Here are the new numbers.")
                        .chimpFont(.bodyL)
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    amounts(draft.vault.asset)
                }
                if moved.failed {
                    Text("I couldn't get the new numbers. Check your connection and try again.")
                        .chimpFont(.caption)
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            Group {
                if moved.failed {
                    ChimpButton("Try again") { Task { await model.fetchNewAmount() } }
                } else {
                    ChimpButton("See new amount", isLoading: moved.newDraft == nil) { model.acceptNewAmount() }
                        .disabled(moved.newDraft == nil)
                }
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }

    /// Retirer : « MINIMUM RECEIVED · 49.87 XLM → 49.80 XLM ». Mettre : la quantité mise ne change pas, seul le prix de la
    /// part bouge : le même montant, réaffirmé.
    private func amounts(_ asset: SendAsset) -> some View {
        VStack(spacing: ChimpSpacing.xxs) {
            Text(isWithdraw ? "Minimum received" : "You put in")
                .textCase(.uppercase)
                .chimpFont(.label)
                .foregroundStyle(Color(.chimpOnHeaderSecondary))
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.m) {
                if isWithdraw {
                    Text(verbatim: asset.displayedWithCode(moved.old, locale: locale))
                        .chimpFont(.greeting)
                        .strikethrough()
                        .foregroundStyle(Color(.chimpOnHeaderSecondary))
                        .accessibilityLabel(Text("Before: \(asset.displayedWithCode(moved.old, locale: locale))"))
                    Text(verbatim: "→").chimpFont(.greeting).foregroundStyle(Color(.chimpOnHeaderPrimary)).accessibilityHidden(true)
                }
                if let newDraft = moved.newDraft {
                    let now = isWithdraw ? (newDraft.quote.minimum ?? newDraft.amount) : newDraft.amount
                    Text(verbatim: asset.displayedWithCode(now, locale: locale))
                        .chimpFont(.amountM)
                        .foregroundStyle(Color(.chimpOnHeaderAccent))
                        .accessibilityLabel(Text("Now: \(asset.displayedWithCode(now, locale: locale))"))
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
