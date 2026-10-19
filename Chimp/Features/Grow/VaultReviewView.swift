import SwiftUI

/// G3r · « Check it over » (maquette « Chimp Grow Final », 2026-10-18) : le ticket (trajet, montant, ce qui reste ou ce
/// qui revient, frais), qui peut signer dit par Chimpy, « Tap your card ». Retirer : le minimum exact (c'est ce que la
/// carte signe), ou « Expected back » pour le prêt. Ni risques ni protocoles sous-jacents (décision de Barth du 2026-10-18).
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

    private var mark: ChimpPotProtocol { model.isLending ? .xoxno : .defindex }

    private var review: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: "Check it over", step: 2, steps: 2,
                onBack: model.isSigningLocked ? nil : { model.isReviewPresented = false }
            )
            if let draft = model.draft {
                ScrollView {
                    content(draft)
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
                .disabled(model.stage != .idle && model.stage != .preparing)
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

    // MARK: G3r · le ticket

    /// Ce que la carte va signer, dit avant la session NFC : le trajet, le montant, ce qui reste ou ce qui revient, le
    /// minimum signé (vault) ou ce qui devrait revenir (prêt), les frais.
    private func content(_ draft: VaultDraft) -> some View {
        let asset = draft.vault.asset
        let isDeposit = draft.action == .deposit
        let drawerName = GrowView.shortTitle(draft.drawer)
        return VStack(alignment: .leading, spacing: 0) {
            ChimpPaperReceipt(padding: EdgeInsets(top: 26, leading: 20, bottom: 18, trailing: 20)) {
                VStack(spacing: 0) {
                    route(draft)
                    ChimpReceiptRule().padding(.vertical, 18)
                    Text(isDeposit ? "You plant" : "You take out")
                        .textCase(.uppercase)
                        .chimpFont(.label)
                        .foregroundStyle(Color(.chimpTicketMuted))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !isDeposit, draft.vault.kind != .lending || draft.quote.all {
                            Text("about").chimpFont(.rowTitle).foregroundStyle(Color(.chimpTicketMuted))
                        }
                        Text(verbatim: isDeposit ? asset.formatted(draft.amount, locale: locale) : asset.displayed(draft.quote.expected ?? draft.amount, locale: locale))
                            .chimpFont(.plantAmount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        Text(verbatim: asset.code).chimpFont(.plantUnit).foregroundStyle(Color(.chimpTicketMuted))
                    }
                    .padding(.top, 4)
                    ChimpReceiptRule().padding(.vertical, 18)
                    VStack(spacing: 0) {
                        if isDeposit {
                            ChimpReceiptRow(
                                label: "\(drawerName) after",
                                value: asset.displayedWithCode(max(0, draft.drawer.balance(of: asset) - draft.amount), locale: locale)
                            )
                            ChimpReceiptRow(label: "Grows", value: String(localized: "\(asset.code), in \(mark.name)"))
                        } else {
                            ChimpReceiptRow(label: "Lands in", value: drawerName)
                            if let minimum = draft.quote.minimum {
                                ChimpReceiptRow(
                                    label: Self.minimumLabel(lending: draft.vault.kind == .lending),
                                    value: draft.vault.kind == .lending
                                        ? asset.displayedWithCode(minimum, locale: locale)
                                        : SwapReviewView.exact(minimum, locale: locale) + " " + asset.code
                                )
                            }
                        }
                        ChimpReceiptRow(label: "Fees", value: asset.formattedWithCode(0, locale: locale), tone: .positive)
                    }
                    if !isDeposit, draft.quote.minimum != nil {
                        Text(Self.minimumNote(lending: draft.vault.kind == .lending))
                            .chimpFont(.caption)
                            .foregroundStyle(Color(.chimpTicketMuted))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ChimpySays(text: "\(Self.chimpyLine(draft))", pose: .plant)
                .padding(.top, 18)
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
                .padding(.top, ChimpSpacing.m)
            }
        }
    }

    /// Le trajet : le tiroir → le protocole (mettre), le protocole → le tiroir (retirer), une graine verte au milieu.
    private func route(_ draft: VaultDraft) -> some View {
        let isDeposit = draft.action == .deposit
        let drawerTile = drawerTile(draft.drawer).rotationEffect(.degrees(4))
        let protocolTile = ChimpProtocolLogo(mark: mark, size: 66)
            .background { RoundedRectangle(cornerRadius: 15).fill(Color(.chimpTicketInk)).offset(x: 3, y: 4) }
            .rotationEffect(.degrees(-6))
        let drawerLabel = GrowView.shortTitle(draft.drawer).uppercased()
        let protocolLabel = mark.name.uppercased()
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                if isDeposit { AnyView(drawerTile) } else { AnyView(protocolTile) }
                RouteLine().frame(height: 28)
                if isDeposit { AnyView(protocolTile) } else { AnyView(drawerTile) }
            }
            HStack {
                Text(verbatim: isDeposit ? drawerLabel : protocolLabel)
                Spacer()
                Text(verbatim: isDeposit ? protocolLabel : drawerLabel)
            }
            .chimpFont(.curveLabel)
            .foregroundStyle(Color(.chimpTicketMuted))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isDeposit ? "From \(drawerLabel) to \(mark.name)" : "From \(mark.name) to \(drawerLabel)"))
    }

    /// La tuile du tiroir : le logo sur jaune (Main) ou sur la couleur de la carte.
    private func drawerTile(_ drawer: SendDrawer) -> some View {
        let fill: Color = if case .card(_, let color) = drawer.kind { color.fill } else { Color(.chimpAccent) }
        return Image(.tileLogo)
            .resizable()
            .scaledToFit()
            .padding(4)
            .frame(width: 66, height: 66)
            .background(RoundedRectangle(cornerRadius: 15).fill(fill))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
            .background { RoundedRectangle(cornerRadius: 15).fill(Color(.chimpTicketInk)).offset(x: 3, y: 4) }
    }

    /// Ligne pointillée, flèche au bout, graine verte au milieu.
    private struct RouteLine: View {
        var body: some View {
            GeometryReader { proxy in
                let midY = proxy.size.height / 2
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: proxy.size.width - 8, y: midY))
                    }
                    .stroke(Color(.chimpTicketInk), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width + 4, y: midY))
                        path.addLine(to: CGPoint(x: proxy.size.width - 9, y: midY - 9))
                        path.addLine(to: CGPoint(x: proxy.size.width - 9, y: midY + 9))
                        path.closeSubpath()
                    }
                    .fill(Color(.chimpTicketInk))
                    Circle()
                        .fill(Color(.chimpCardLeaf))
                        .overlay { Circle().strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
                        .frame(width: 22, height: 22)
                        .position(x: proxy.size.width / 2, y: midY)
                }
            }
        }
    }

    /// La ligne de Chimpy sous le ticket : qui peut signer (Main : n'importe quelle carte ; une carte : elle seule).
    static func chimpyLine(_ draft: VaultDraft) -> String {
        let isDeposit = draft.action == .deposit
        switch draft.drawer.kind {
        case .main:
            return isDeposit
                ? String(localized: "Tap any of your cards, then your PIN. And we plant!")
                : String(localized: "Tap any of your cards, then your PIN. And it comes home!")
        case .card(let name, _):
            return isDeposit
                ? String(localized: "Only your \(name) card can sign: it's in its own wallet. Tap it, and we plant!")
                : String(localized: "Only your \(name) card can sign: it's in its own wallet. Tap it, and it comes home!")
        }
    }

    /// Le titre de la ligne du retrait : le minimum signé (vault), ce qui devrait revenir (prêt). Revue de sécurité F5 :
    /// le contrat XOXNO ne garantit aucun minimum (un retrait est ramené à la position, qui peut baisser si un emprunteur
    /// ne rembourse pas) ; l'écran ne le présente donc pas comme garanti.
    static func minimumLabel(lending: Bool) -> LocalizedStringKey {
        lending ? "Expected back" : "At least"
    }

    static func minimumNote(lending: Bool) -> LocalizedStringKey {
        lending ? "The contract doesn't guarantee a minimum. If XOXNO can't pay it right now, nothing moves." : "This is what your card signs. If the vault would pay less, nothing moves."
    }

    static func message(for issue: VaultFlowModel.PreparationIssue, draft: VaultDraft, locale: Locale) -> LocalizedStringKey {
        let asset = draft.vault.asset
        switch issue {
        case .insufficientBalance: return "Not enough \(asset.code) in \(draft.drawer.title). Nothing was signed."
        case .notEnoughShares: return "The position doesn't hold that much anymore. Nothing was signed."
        case .notEnoughLiquidity where draft.vault.kind == .lending:
            return "XOXNO can't pay that much back right now: it's lent out. Nothing was signed."
        case .notEnoughLiquidity:
            return "The vault can give back \(asset.displayedWithCode(draft.vault.availableNow, locale: locale)) right now. The rest comes back as borrowers repay."
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
