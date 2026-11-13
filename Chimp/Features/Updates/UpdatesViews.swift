import SwiftUI

/// Réglages › Updates (sans maquette, composé avec les pièces des Réglages) : le Main account et le wallet de chaque
/// carte, et où ils en sont (`UpdatesList.tsx` du terminal). Une ligne « Update ready » ouvre la mise à jour.
struct UpdatesView: View {
    @Bindable var model: UpdatesModel
    /// Les cartes lues par le Wallet (leur wallet, leur numéro).
    let cards: [CardBalance]
    let onBack: () -> Void

    /// La ligne ouverte (adresse du contrat).
    @State private var openID: String?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Updates", subtitle: "The code behind your money", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ChimpDAO improves the code behind your account from time to time. An update takes one tap of a card, and no money moves.")
                        .chimpFont(.body)
                        .foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                        .padding(.top, ChimpSpacing.l)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh(cards: cards) }
        }
        .background(Color(.chimpBackground))
        .task { await model.refresh(cards: cards) }
        .navigationDestination(isPresented: Binding(get: { openID != nil }, set: { if !$0 { openID = nil } })) {
            if let row = model.rows.first(where: { $0.id == openID }), let target = row.target {
                UpdateFlowDestination(row: row, target: target, session: model.session, service: model.service) { updated in
                    openID = nil
                    if updated { Task { await model.refresh(cards: cards) } }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let details) = model.phase, model.rows.allSatisfy({ $0.status == nil }) {
            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                ChimpySays(text: "I can't reach the jungle right now. Check your connection.", pose: .crawl)
                ChimpTechnicalDetails(details: details)
                ChimpButton("Try again") { Task { await model.refresh(cards: cards) } }
            }
        } else if model.rows.isEmpty, model.phase != .loaded {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            ChimpGroupedBox {
                ForEach(model.rows) { row in
                    if row.target != nil {
                        ChimpSettingsRow(title: Self.title(row), value: Self.label(row.status)) { openID = row.id }
                            .accessibilityHint(Text("Opens the update"))
                    } else {
                        ChimpSettingsControlRow(title: Self.title(row)) {
                            if model.phase == .loading && row.status == nil {
                                ProgressView()
                            } else {
                                Text(Self.label(row.status))
                                    .chimpFont(.captionS)
                                    .foregroundStyle(.chimpTextSecondary)
                            }
                        }
                    }
                }
            }
            if model.readyCount > 0 {
                ChimpySays(text: "An update is ready. Your money stays put, it's just fresher code.", pose: .teacher)
                    .padding(.top, ChimpSpacing.l)
            }
        }
    }

    static func title(_ row: UpdatesModel.Row) -> LocalizedStringKey {
        switch row.subject {
        case .account: "Main account"
        case .card(_, let name, _, _, _): "\(name)'s wallet"
        }
    }

    /// Libellés du terminal (`statusLabel`).
    static func label(_ status: UpdateStatus?) -> String {
        switch status {
        case .available: String(localized: "Update ready")
        case .upToDate: String(localized: "Up to date")
        case .managed: String(localized: "Updates automatically")
        case .custom: String(localized: "Running its own code")
        case .unknown, nil: "—"
        }
    }
}

/// Une mise à jour : un ViewModel neuf à chaque ouverture.
private struct UpdateFlowDestination: View {
    @State private var model: UpdateFlowModel
    let onExit: (_ updated: Bool) -> Void

    init(row: UpdatesModel.Row, target: UpdateTarget, session: AppSession, service: UpdatesService, onExit: @escaping (Bool) -> Void) {
        _model = State(initialValue: UpdateFlowModel.live(row: row, target: target, session: session, service: service))
        self.onExit = onExit
    }

    var body: some View {
        UpdateFlowView(model: model, onExit: onExit)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Vérification, PIN et tap (feuilles d'Envoyer), envoi, fin. Le retour est bloqué pendant la signature et l'envoi.
struct UpdateFlowView: View {
    @Bindable var model: UpdateFlowModel
    let onExit: (_ updated: Bool) -> Void

    var body: some View {
        Group {
            switch model.screen {
            case .review:
                UpdateReviewView(model: model) { onExit(false) }
            case .updating:
                UpdatingView(model: model) { onExit(false) }
            case .done(let outcome):
                UpdateDoneView(model: model, outcome: outcome) { onExit(true) }
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
                    title: model.row.isAccount ? "PIN of the card you'll tap" : "\(Self.cardName(model.row))'s PIN",
                    subtitle: "Updating \(Self.subject(model.row))",
                    pin: $model.pin,
                    length: UpdateFlowModel.pinLength,
                    state: $model.pinState,
                    onCancel: { model.cancelSigning() },
                    onComplete: model.pinEntered
                )
            } else {
                CardTapSheet(
                    cardName: Self.cardName(model.row),
                    cardColor: Self.cardColor(model.row),
                    stepLabel: "Tap",
                    title: model.row.isAccount ? "Tap any of your cards" : "Tap your \(Self.cardName(model.row)) card",
                    what: "Updating \(Self.subject(model.row)) to ChimpDAO's latest code. No money moves.",
                    who: model.row.isAccount ? "Any card of your account can sign it." : "Only \(Self.cardName(model.row)) can sign it.",
                    pinStatus: model.usesPIN ? .ready : .notNeeded,
                    isScanning: model.isBusy,
                    isGettingReady: model.isGettingReady,
                    problem: model.problem.map { Self.message(for: $0.kind, row: model.row) },
                    problemDetails: model.problem?.technicalDetails,
                    onScan: { Task { await model.scan() } },
                    onCancel: model.isBusy ? nil : { model.cancelSigning() }
                )
            }
        }
    }

    static func cardName(_ row: UpdatesModel.Row) -> String {
        if case .card(_, let name, _, _, _) = row.subject { return name }
        return ""
    }

    static func cardColor(_ row: UpdatesModel.Row) -> ChimpCardColor? {
        if case .card(_, _, let color, _, _) = row.subject { return color }
        return nil
    }

    /// « your Main account », « Banana's wallet ».
    static func subject(_ row: UpdatesModel.Row) -> String {
        switch row.subject {
        case .account: String(localized: "your Main account")
        case .card(_, let name, _, _, _): String(localized: "\(name)'s wallet")
        }
    }

    /// Textes proposés (pas de maquette), DESIGN_NOTES §15.
    static func message(for kind: UpdateProblem.Kind, row: UpdatesModel.Row) -> LocalizedStringKey {
        switch kind {
        case .card(let kind): CardReadingView.message(for: kind)
        case .cardNotAccepted:
            row.isAccount
                ? "That card isn't one of your account's. Tap one of yours. Nothing was sent."
                : "That's not \(cardName(row)). Only \(cardName(row)) can update its wallet. Nothing was sent."
        case .network: "I couldn't reach Stellar. Check your connection and try again. Nothing was sent."
        case .pendingPayment: "A payment is still being checked. Open Send to see how it ended, then try again."
        case .refused(let error): LocalizedStringKey(error.localizedDescription)
        }
    }
}

/// Ce qui sera signé (règle 8) : quoi, depuis quelle version vers laquelle, d'où viendront les prochaines mises à jour
/// (le factory, en entier), qui signe, et qu'aucun argent ne bouge.
struct UpdateReviewView: View {
    let model: UpdateFlowModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: model.row.isAccount ? "Update your account" : "Update \(UpdateFlowView.cardName(model.row))'s wallet",
                        subtitle: "Fresher code, same money", onBack: model.isBusy ? nil : onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What happens")
                        .chimpFont(.displayS)
                        .foregroundStyle(.chimpTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ChimpReviewSteps(steps: [
                        Text("\(UpdateFlowView.subject(model.row).capitalizedFirst) switches to ChimpDAO's latest code"),
                        Text("No money moves: your balances stay exactly where they are"),
                        model.row.isAccount
                            ? Text("Next updates can only come from ChimpDAO's code registry")
                            : Text("Only this card can ever change its wallet's code"),
                    ])
                    .padding(.top, ChimpSpacing.sm)

                    VStack(alignment: .leading, spacing: ChimpSpacing.sm) {
                        detail("From version", value: Self.short(fromHash))
                        detail("To version", value: Self.short(model.target.wasmHash))
                        if model.row.isAccount {
                            detail("Code registry", value: model.factory)
                        }
                        detail("Signed by", value: model.row.isAccount
                            ? String(localized: "Any of your cards")
                            : String(localized: "Your \(UpdateFlowView.cardName(model.row)) card"))
                        detail("Fees", value: String(localized: "Paid by ChimpDAO"))
                    }
                    .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
                    .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
                    .padding(.top, ChimpSpacing.xl)

                    if let problem = model.problem, !model.isShowingTapSheet {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                            ChimpFieldMessage(text: UpdateFlowView.message(for: problem.kind, row: model.row), kind: .error)
                            ChimpTechnicalDetails(details: problem.technicalDetails)
                        }
                        .padding(.top, ChimpSpacing.m)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.m) {
                ChimpySays(text: "One tap and you're on the newest code. Nothing else changes.", pose: .teacher)
                ChimpButton("Update", isLoading: model.isBusy) { Task { await model.start() } }
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.ml)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var fromHash: String {
        if case .available(let from, _) = model.row.status { return from }
        return "—"
    }

    /// Une version : les 8 premiers caractères de son hash (« 044275ac »).
    static func short(_ hash: String) -> String {
        String(ContractUpdates.normHash(hash).prefix(8))
    }

    private func detail(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .chimpFont(.labelS)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            Text(verbatim: value)
                .chimpFont(.rowTitle)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Envoi et relecture, ou ce qui n'a pas abouti (« Check again »).
struct UpdatingView: View {
    let model: UpdateFlowModel
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: model.isFailed ? "Not quite there" : "Updating", subtitle: model.isFailed ? "Your money is safe" : "Keep the app open")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    if case .failed(let message, let details) = model.phase {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                            ChimpySays(text: LocalizedStringKey(message), pose: .head)
                            ChimpTechnicalDetails(details: details)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                        ChimpySays(text: "Hang on, I'm installing the new code and checking it took. It takes a few seconds.", pose: .banana)
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            if model.isFailed {
                VStack(spacing: ChimpSpacing.m) {
                    ChimpButton("Check again") { Task { await model.checkAgain() } }
                    ChimpButton("Back to Updates", kind: .link, action: onLeave)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
        }
        .background(Color(.chimpBackground))
    }
}

/// C'est fait, ou c'était déjà fait (rien n'a été signé).
struct UpdateDoneView: View {
    let model: UpdateFlowModel
    let outcome: UpdateOutcome
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: ChimpSpacing.l) {
            Spacer()
            Image(outcome == .alreadyCurrent ? .chimpyStand : .chimpyHearts)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
                .chimpBob(duration: 4)
                .accessibilityHidden(true)
            Text(outcome == .alreadyCurrent ? "Already up to date" : "All fresh!")
                .chimpFont(.displayL)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(outcome == .alreadyCurrent
                 ? "\(UpdateFlowView.subject(model.row).capitalizedFirst) already runs the latest code. Nothing was signed."
                 : "\(UpdateFlowView.subject(model.row).capitalizedFirst) runs ChimpDAO's latest code. Your money didn't move.")
                .chimpFont(.bodyL)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            ChimpButton("Done", action: onDone)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.bottom, ChimpSpacing.l)
        .background(Color(.chimpBackground))
    }
}

private extension String {
    /// « your Main account » → « Your Main account ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// La pop-up du Wallet (demande de Barth du 2026-11-13) : une mise à jour est prête. Elle ne bloque jamais l'accès à
/// l'argent, ne revient qu'une fois par version de ChimpDAO (et une fois par lancement après « Later »), et se contente
/// d'ouvrir Réglages › Updates : rien n'est signé ici.
struct UpdateNoticeSheet: View {
    /// Combien de contrats ont une mise à jour prête.
    let count: Int
    let onUpdate: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(.chimpyTeacher)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .chimpBob(duration: 3.4)
                .accessibilityHidden(true)
            Text("An update is ready")
                .chimpFont(.sheetTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpTextPrimary)
                .padding(.top, ChimpSpacing.m)
                .accessibilityAddTraits(.isHeader)
            Text(count > 1
                 ? "ChimpDAO improved the code behind your account and your cards. It takes one tap of a card, and no money moves."
                 : "ChimpDAO improved the code behind your account. It takes one tap of a card, and no money moves.")
                .chimpFont(.bodyL)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ChimpSpacing.sm)
            VStack(spacing: 11) {
                ChimpButton("See the update", action: onUpdate)
                ChimpButton("Later", kind: .link, action: onLater)
            }
            .padding(.top, ChimpSpacing.xl)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }
}
