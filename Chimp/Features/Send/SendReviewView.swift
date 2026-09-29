import SwiftUI

/// C4 · « Here's what happens » : ce qui va se passer (maquette), puis **exactement** ce que la carte signera
/// (destinataire complet, memo ID, tiroir source, montant exact, réseau), avant toute session NFC (règle 8).
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
        if model.showsStatus {
            SendStatusView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        } else {
            review
        }
    }

    private var review: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: "Here's what happens",
                step: 3,
                steps: 3,
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
                Text("Payments can't be undone once signed.")
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

    private func content(_ draft: SendDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ChimpReviewSteps(steps: [
                Text("\(amountText(draft)) leaves \(draft.drawer.title)"),
                Text("\(recipientLabel(draft)) gets it in about 5 seconds"),
                Text("Network fees paid by ChimpDAO"),
            ])

            signerBanner(draft)
                .padding(.top, ChimpSpacing.l)

            Text("What your card signs")
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ChimpSpacing.sectionGap)
            ChimpDetailList(items: details(draft))
                .padding(.top, ChimpSpacing.sm)

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
        items.append(ChimpDetailItem(id: "amount", label: "Amount", value: draft.asset.formattedWithCode(draft.amount, locale: locale)))
        items.append(ChimpDetailItem(id: "network", label: "Network", value: draft.network.displayName))
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
                    subtitle: "Paying \(recipientLabel(draft)) \(draft.asset.formattedWithCode(draft.amount, locale: locale))",
                    pin: $model.pin,
                    length: model.pinLength,
                    state: $model.pinState,
                    saysNothingWasSent: true,
                    onComplete: model.pinEntered
                )
            case .tapToRead, .tapToSign:
                let card = tapCard(draft)
                CardTapSheet(
                    cardName: card.name,
                    cardColor: card.color,
                    stepLabel: stepLabel(for: step),
                    title: tapTitle(draft, step: step),
                    what: "Paying \(recipientLabel(draft)) \(draft.asset.formattedWithCode(draft.amount, locale: locale))",
                    who: tapWho(draft),
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
        case .main: return "Your card's PIN"
        }
    }

    /// Carte dessinée au centre des anneaux : celle du tiroir, celle lue au premier tap, ou « n'importe laquelle ».
    private func tapCard(_ draft: SendDraft) -> (name: String, color: ChimpCardColor) {
        if let check = model.cardCheck { return (check.cardName, check.cardColor) }
        switch draft.drawer.kind {
        case let .card(name, color): return (name, color)
        case .main: return ("", .banana)
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

    private func tapWho(_ draft: SendDraft) -> LocalizedStringKey {
        if let check = model.cardCheck {
            return "Use the same card: your PIN is for \(check.cardName)."
        }
        switch draft.drawer.kind {
        case .card:
            return "It's from \(draft.drawer.title), so only that card works."
        case .main:
            return "It's from Main, so any of your cards works."
        }
    }

    /// Tap raté, avant toute signature (textes validés ; NFC : messages de Chimpy de l'onboarding).
    static func message(for problem: TapProblem) -> LocalizedStringKey {
        switch problem {
        case .cardNotAccepted: "That card isn't one of yours. Nothing was sent."
        case .card(let kind): CardReadingView.message(for: kind)
        case .network: "Couldn't get ready to send. Nothing was sent. Check your connection and try again."
        }
    }

    private func pinStatus(for step: SigningStep) -> CardTapPinStatus {
        if step == .tapToRead { return .afterTap }
        return model.signingSteps.contains(.pin) ? .ready : .notNeeded
    }
}
