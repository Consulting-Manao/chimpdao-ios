import SwiftUI

/// Après le tap : envoi en cours, puis l'issue (textes validés le 2026-09-29, DESIGN_NOTES §12, états absents de la
/// maquette sauf C9). Rien ne peut interrompre ces écrans : pas de retour, ni par bouton ni par glissement ; on n'en
/// sort que par leurs boutons.
///
/// - « Sending… » : les étapes (signé par la carte, vérification, envoi, confirmation).
/// - C9 « Swoosh! » : confirmé.
/// - « Not confirmed yet » : envoyé, pas encore confirmé → « Check again », jamais « Send again ».
/// - « Not sent » : l'autorisation signée peut encore servir → attendre l'heure dite, compte à rebours, aucun bouton
///   pour renvoyer ; l'app revérifie toute seule à la fin.
/// - « Nothing was sent » : certain → « Try again ».
/// - « Can't tell yet » : impossible de trancher → « Check again », Stellar Expert.
struct SendStatusView: View {
    @Bindable var model: SendFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    /// L'historique de l'app (onglet Activity) : « See the receipt » ouvre le même reçu imprimé (I1.1d).
    @Environment(ActivityViewModel.self) private var appActivity: ActivityViewModel?
    /// Catalogue et aperçus, sans historique de l'app : l'historique factice, aux mêmes adresses que l'envoi factice.
    @State private var mockActivity = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
    @State private var seed = ChimpyLines.seed()

    var body: some View {
        Group {
            if case .finished(.sent(let receipt)) = model.signingStage {
                SendSentView(receipt: receipt, onDone: model.finish, onReceipt: { model.isReceiptPresented = true })
                    .chimpSheet(isPresented: $model.isReceiptPresented, height: ChimpSize.cardTapSheetHeight, fitsContent: true) {
                        if let printed = activity.receipt(forSent: receipt.activityRecord, locale: locale) {
                            // « Pay again » (envoi seulement, comme dans l'Activity) : un parcours neuf, prérempli.
                            ActivityReceiptSheet(receipt: printed, model: activity) { _ in model.sendAgain() }
                        }
                    }
            } else {
                statusScreen
            }
        }
        .blocksSwipeBack(true)
    }

    private var activity: ActivityViewModel { appActivity ?? mockActivity }

    // MARK: Écran d'état

    private var statusScreen: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    content
                    if model.pendingSaveFailed {
                        ChimpNoticeBanner(text: "This phone couldn't save this payment. Don't send it again before you've checked it.", marker: .error)
                    }
                    if let summary = model.summary {
                        ChimpDetailList(items: details(summary))
                    }
                    if let details = model.technicalDetails, showsTechnicalDetails {
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
        switch model.signingStage {
        case .finished(.notConfirmed): "Not confirmed yet"
        case .finished(.waiting): "Not sent"
        case .finished(.nothingSent): "Nothing was sent"
        case .finished(.undetermined): "Can't tell yet"
        case .checking: "Checking with Stellar"
        default: "Sending…"
        }
    }

    private var subtitle: LocalizedStringKey? {
        switch model.signingStage {
        case .sending, .checking: "Keep the app open"
        default: nil
        }
    }

    /// Détails techniques (pour le support) sur toutes les issues, pas pendant l'envoi.
    private var showsTechnicalDetails: Bool {
        if case .finished = model.signingStage { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.signingStage {
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
        case .finished(.notConfirmed):
            ChimpySays(text: "It was sent, but Stellar hasn't confirmed it yet. Check again in a moment. Don't worry, nothing is sent twice.", pose: .head)
        case .finished(.waiting(let until)):
            waiting(until: until)
            failureReasonLine
        case .finished(.nothingSent):
            ChimpySays(text: "Your money didn't move. You can try again.", pose: .peel)
        case .finished(.undetermined):
            ChimpySays(text: "I can't tell yet if it went through. Don't send it again — tap Check again in a moment.", pose: .head)
            failureReasonLine
        default:
            EmptyView()
        }
    }

    /// Pourquoi l'envoi n'est pas passé (après la signature), en une ligne sous le message principal.
    @ViewBuilder
    private var failureReasonLine: some View {
        if let reason = model.failureReason {
            ChimpFieldMessage(text: Self.message(for: reason), kind: .info)
        }
    }

    static func message(for reason: SendFailureReason) -> LocalizedStringKey {
        switch reason {
        case .network: "Stellar couldn't be reached."
        case .feeHelperBusy: "ChimpDAO's fee helper was busy."
        case .feeHelperRefused: "ChimpDAO's fee helper said no."
        case .signatureRejected: "The card's signature didn't check out."
        case .refused: "Stellar refused it."
        }
    }

    /// « Signed by {carte} », « Checking with Stellar », « Sending », « Confirming ».
    private func sendingSteps(_ progress: PaymentProgress) -> [ChimpProgressStep] {
        let order: [PaymentProgress] = [.checking, .sending, .confirming]
        let reached = order.firstIndex(of: progress) ?? 0
        let labels = [Text("Checking with Stellar"), Text("Sending"), Text("Confirming")]
        var steps = [ChimpProgressStep(id: 0, label: Text("Signed by \(model.signed?.cardName ?? "")"), state: .done)]
        for (index, label) in labels.enumerated() {
            let state: ChimpProgressStep.State = index < reached ? .done : (index == reached ? .current : .todo)
            steps.append(ChimpProgressStep(id: index + 1, label: label, state: state))
        }
        return steps
    }

    /// « Not sent. Please wait until {heure} before trying again », avec un compte à rebours.
    private func waiting(until: Date) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text("Not sent. Please wait until \(until.formatted(date: .omitted, time: .shortened)) before trying again.")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, until.timeIntervalSince(context.date))
                Text(Duration.seconds(Int(seconds.rounded(.up))).formatted(.time(pattern: .minuteSecond)))
                    .chimpFont(.amountL)
                    .monospacedDigit()
                    .foregroundStyle(.chimpTextPrimary)
                    .accessibilityLabel(Text("Time left"))
                    .accessibilityValue(Text(Duration.seconds(Int(seconds.rounded(.up))).formatted(.units(allowed: [.minutes, .seconds]))))
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: ChimpSpacing.xs) {
            switch model.signingStage {
            case .finished(.notConfirmed), .finished(.undetermined):
                ChimpButton("Check again", action: model.checkAgain)
                explorerLink
                ChimpButton("Back to my wallet", kind: .link, action: model.finish)
            case .finished(.nothingSent):
                if model.canTryAgain {
                    ChimpButton("Try again", action: model.tryAgain)
                    ChimpButton("Back to my wallet", kind: .link, action: model.finish)
                } else {
                    ChimpButton("Back to my wallet", action: model.finish)
                }
            case .finished(.waiting):
                ChimpButton("Back to my wallet", kind: .secondary, action: model.finish)
            default:
                ChimpButton("Back to my wallet", isLoading: true) {}
                    .disabled(true)
            }
        }
    }

    @ViewBuilder
    private var explorerLink: some View {
        if let url = model.explorerURL {
            ChimpButton("View on Stellar Expert", kind: .link) { openURL(url) }
        }
    }

    private func details(_ summary: SendSummary) -> [ChimpDetailItem] {
        var items: [ChimpDetailItem] = []
        if let name = summary.recipientName {
            items.append(ChimpDetailItem(id: "name", label: "To", value: name))
        }
        items.append(ChimpDetailItem(
            id: "address", label: summary.recipientName == nil ? "To" : "Address",
            value: SendReviewView.grouped(summary.recipientAddress), isMonospaced: true
        ))
        items.append(ChimpDetailItem(id: "from", label: "From", value: summary.drawerTitle))
        items.append(ChimpDetailItem(id: "amount", label: "Amount", value: summary.asset.formattedWithCode(summary.amount, locale: locale)))
        return items
    }
}

/// C9 · « Swoosh! » (maquette) : fond Leaf et motif, Chimpy à la banane, phrase, pastille « From … · heure »,
/// « Back to my wallet » et « See the receipt ». Titre et phrase tirés au hasard (`ChimpyLines`), bananes volantes.
struct SendSentView: View {
    let receipt: SendReceipt
    let onDone: () -> Void
    let onReceipt: () -> Void

    @Environment(\.locale) private var locale
    /// Titre et phrase tirés au hasard (`ChimpyLines`) ; le montant et le destinataire restent exacts.
    @State private var seed = ChimpyLines.seed()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 0) {
                Image(.chimpyPlane)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 230)
                    .chimpBob(duration: 3.5)
                    .accessibilityHidden(true)
                Text(ChimpyLines.pick(ChimpyLines.sentTitles, seed: seed))
                    .chimpFont(.welcomeTitle)
                    .padding(.top, ChimpSpacing.l)
                    .accessibilityAddTraits(.isHeader)
                Text("\(receipt.summary.recipientLabel) has the \(receipt.summary.asset.formattedWithCode(receipt.summary.amount, locale: locale)). \(Text(ChimpyLines.pick(ChimpyLines.sentQuips, seed: seed / 7)))")
                    .chimpFont(.lead)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.s)
                Text("From \(receipt.summary.drawerTitle) · \(receipt.sentAt.formatted(date: .omitted, time: .shortened))")
                    .chimpFont(.captionStrong)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(.white.opacity(0.35)))
                    .overlay { Capsule().strokeBorder(ChimpCardColor.leaf.ink, lineWidth: 2) }
                    .padding(.top, ChimpSpacing.m)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(ChimpCardColor.leaf.ink)
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                ChimpButton("Back to my wallet", action: onDone)
                // Encre de la maquette (le lien habituel, brun, manque de contraste sur le vert Leaf).
                Button(action: onReceipt) {
                    Text("See the receipt")
                        .chimpFont(.link)
                        .foregroundStyle(ChimpCardColor.leaf.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .background {
            ChimpCardColor.leaf.fill
                .overlay { ChimpPattern(opacity: 0.14) }
                // Des bananes traversent l'écran, une fois, derrière le texte (rien avec « Réduire les animations »).
                .overlay { ChimpBananaBurst() }
                .ignoresSafeArea()
        }
    }
}
