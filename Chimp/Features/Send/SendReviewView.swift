import SwiftUI

/// C4 · « Here's what happens » : un seul résumé de **exactement** ce que la carte signera (montant exact, destinataire
/// complet, memo ID, tiroir source, réseau, frais offerts), avant toute session NFC (règle 8).
/// « Looks good » prépare l'envoi (réseau, règle 9), puis ouvre les feuilles de signature (C5, C6) dans
/// l'ordre choisi (`SigningOrder`).
///
/// Pendant la préparation, le scan et après la signature : pas de bouton retour, pas de retour par glissement,
/// feuille impossible à fermer, bouton désactivé.
struct SendReviewView: View {
    @Bindable var model: SendFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        Group {
            if model.showsStatus {
                SendStatusView(model: model)
                    .toolbar(.hidden, for: .navigationBar)
            } else if case .wrongCard(let wrongCard, _) = model.signingStage {
                WrongCardView(wrongCard: wrongCard, onRetry: model.retryAfterWrongCard, onCancel: model.cancelSigning)
                    .toolbar(.hidden, for: .navigationBar)
                    .blocksSwipeBack(true)
            } else {
                review
            }
        }
        // Sons : la carte a signé, l'argent est arrivé, ou ça n'a pas marché (tap raté, préparation ratée).
        .onChange(of: model.signingStage) { old, new in
            if let sound = new.sound, old.sound != sound { ChimpSoundPlayer.shared.play(sound) }
        }
        .chimpSound(.error, trigger: model.tapProblem) { _, new in new != nil }
        .chimpSound(.error, trigger: model.signingErrorMessage) { _, new in new != nil }
    }

    private var review: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: "Here's what happens",
                step: model.isMove ? 0 : 3,
                steps: model.isMove ? 0 : 3,
                onBack: model.isSigningLocked ? nil : { model.isReviewPresented = false }
            )
            if let draft = model.draft {
                ScrollView {
                    content(draft)
                        .padding(.horizontal, ChimpSpacing.xxl)
                        .padding(.vertical, ChimpSpacing.xl)
                }
            }
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // L'avertissement reste visible au-dessus du bouton, même si le reste défile.
            VStack(spacing: ChimpSpacing.sm) {
                Text(model.isMove ? "Moves can't be undone once signed. You can always move it back." : "Payments can't be undone once signed.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChimpButton("Looks good", isLoading: model.signingStage == .preparing) { model.confirmReview() }
                    .disabled(model.signingStage != .idle && model.signingStage != .preparing)
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

    /// Un seul résumé (retour du call avec Pamphile, 2026-10-01 : la même information apparaissait trois fois) :
    /// le montant exact, puis la liste de ce que la carte signe (destinataire complet, memo ID, tiroir source, réseau,
    /// frais offerts), puis qui peut signer. Move garde ses étapes : elles disent que rien ne quitte le compte.
    private func content(_ draft: SendDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if draft.isMove {
                ChimpReviewSteps(steps: [
                    Text("\(amountText(draft)) leaves \(draft.drawer.title)"),
                    Text("\(recipientLabel(draft)) gets it in about 5 seconds. Nothing leaves your account."),
                    Text("Network fees paid by ChimpDAO"),
                ])
                signerBanner(draft)
                    .padding(.top, ChimpSpacing.l)
            } else {
                amountHeader(draft)
                ChimpDetailList(items: details(draft))
                    .padding(.top, ChimpSpacing.l)
                signerBanner(draft)
                    .padding(.top, ChimpSpacing.m)
            }

            if let message = model.signingErrorMessage {
                VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                    ChimpFieldMessage(text: "\(message)", kind: .error)
                    if let details = model.technicalDetails {
                        ChimpTechnicalDetails(details: details)
                    }
                }
                .padding(.top, ChimpSpacing.m)
            }
        }
    }

    /// « YOU SEND · 25.5 XLM · ≈ $6.37 » : le montant exact signé, en grand.
    private func amountHeader(_ draft: SendDraft) -> some View {
        VStack(spacing: ChimpSpacing.xxs) {
            Text("You send")
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            Text(verbatim: draft.asset.formattedWithCode(draft.amount, locale: locale))
                .chimpFont(.amountL)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let usd = model.usdEquivalent(of: draft) {
                Text("≈ \(usd)")
                    .chimpFont(.captionStrong)
                    .foregroundStyle(.chimpTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Montant exact et son code (« 25.5 XLM »), plus l'équivalent en dollars pour un actif à prix variable.
    private func amountText(_ draft: SendDraft) -> String {
        let amount = draft.asset.formattedWithCode(draft.amount, locale: locale)
        guard let usd = model.usdEquivalent(of: draft) else { return amount }
        return "\(amount) (≈ \(usd))"
    }

    private func recipientLabel(_ draft: SendDraft) -> String {
        draft.recipientName ?? StellarAddressParser.short(draft.recipient.address)
    }

    private func details(_ draft: SendDraft) -> [ChimpDetailItem] {
        var items: [ChimpDetailItem] = []
        if let name = draft.recipientName {
            items.append(ChimpDetailItem(id: "name", label: "To", value: name))
        }
        items.append(ChimpDetailItem(
            id: "address",
            label: draft.recipientName == nil ? "To" : "Address",
            value: Self.grouped(draft.recipient.address),
            isMonospaced: true
        ))
        if let memoID = draft.recipient.memoID {
            items.append(ChimpDetailItem(id: "memo", label: "Memo ID", value: String(memoID), isMonospaced: true))
        }
        items.append(ChimpDetailItem(id: "from", label: "From", value: draft.drawer.title))
        items.append(ChimpDetailItem(id: "network", label: "Network", value: draft.network.displayName))
        items.append(ChimpDetailItem(id: "fees", label: "Fees", value: String(localized: "Paid by ChimpDAO")))
        return items
    }

    /// Adresse complète par groupes de 4 caractères, plus facile à comparer avec l'originale.
    static func grouped(_ address: String) -> String {
        stride(from: 0, to: address.count, by: 4).map { offset in
            let start = address.index(address.startIndex, offsetBy: offset)
            let end = address.index(start, offsetBy: 4, limitedBy: address.endIndex) ?? address.endIndex
            return String(address[start..<end])
        }
        .joined(separator: " ")
    }

    @ViewBuilder
    private func signerBanner(_ draft: SendDraft) -> some View {
        switch draft.drawer.kind {
        case let .card(name, color):
            ChimpNoticeBanner(text: "Grab your \(name) card. The money is in its own wallet, so no other card can sign.", marker: .card(color))
        case .main:
            ChimpNoticeBanner(text: "Grab any of your cards. The money is in Main, so any of them can sign.")
        }
    }

    // MARK: Feuilles de signature (C5, C6)

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
                    problem: model.tapProblem.map(Self.message(for:)),
                    problemDetails: model.tapProblem == nil ? nil : model.technicalDetails,
                    onScan: model.scanCard,
                    onCancel: model.isSigningLocked ? nil : { model.cancelSigning() }
                )
            }
        }
    }

    /// Rappel de ce qui est signé, dans la feuille du PIN et celle du tap (règle 8) : « Paying 25 USDC to Maya », ou pour un
    /// Move « Moving 50 USDC from Main account to Jungle's wallet » (maquette E2).
    private func whatIsSigned(_ draft: SendDraft) -> LocalizedStringKey {
        let amount = draft.asset.formattedWithCode(draft.amount, locale: locale)
        if draft.isMove {
            return "Moving \(amount) from \(draft.drawer.title) to \(recipientLabel(draft))"
        }
        return "Paying \(amount) to \(recipientLabel(draft))"
    }

    /// « Step 1 of 2 · PIN », « Step 3 of 3 · Tap », ou « Last step · Tap » s'il n'y a qu'une étape.
    private func stepLabel(for step: SigningStep) -> LocalizedStringKey {
        let steps = model.signingSteps
        let isPin = step == .pin
        guard steps.count > 1, let index = steps.firstIndex(of: step) else {
            return isPin ? "Last step · PIN" : "Last step · Tap"
        }
        return isPin ? "Step \(index + 1) of \(steps.count) · PIN" : "Step \(index + 1) of \(steps.count) · Tap"
    }

    private func pinTitle(_ draft: SendDraft) -> LocalizedStringKey {
        if let check = model.cardCheck { return "\(check.cardName)'s PIN" }
        switch draft.drawer.kind {
        case .card(let name, _): return "\(name)'s PIN"
        // Depuis Main, n'importe quelle carte signe : le PIN est celui de la carte qu'on va poser.
        case .main: return "PIN of the card you'll tap"
        }
    }

    /// Carte dessinée au centre des anneaux : celle du tiroir, celle lue au premier tap, ou « n'importe laquelle ».
    private func tapCard(_ draft: SendDraft) -> (name: String, color: ChimpCardColor?) {
        if let check = model.cardCheck { return (check.cardName, check.cardColor) }
        switch draft.drawer.kind {
        case let .card(name, color): return (name, color)
        // N'importe quelle carte du compte : vignette grise.
        case .main: return ("", nil)
        }
    }

    private func tapTitle(_ draft: SendDraft, step: SigningStep) -> LocalizedStringKey? {
        if step == .tapToSign, let check = model.cardCheck {
            return "Tap your \(check.cardName) card again"
        }
        if case .main = draft.drawer.kind {
            return "Tap any of your cards"
        }
        return nil
    }

    /// Tap raté, avant toute signature (textes validés ; NFC : messages de Chimpy de l'onboarding).
    static func message(for problem: TapProblem) -> LocalizedStringKey {
        switch problem {
        case .card(let kind): CardReadingView.message(for: kind)
        case .network: "Couldn't get ready to send. Nothing was sent. Check your connection and try again."
        }
    }

    private func pinStatus(for step: SigningStep) -> CardTapPinStatus {
        if step == .tapToRead { return .afterTap }
        return model.signingSteps.contains(.pin) ? .ready : .notNeeded
    }
}
