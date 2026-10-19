import SwiftUI

/// Après le tap (maquettes E5 et E6 du 2026-10-14 ; les autres issues reprennent les écrans d'Envoyer avec des textes
/// adaptés, décision de Barth du 2026-10-14). Rien ne peut interrompre ces écrans : on n'en sort que par leurs boutons.
///
/// - « Swapping… » : les étapes (signé par la carte, vérification, envoi, confirmation).
/// - E5 « Swapped! » : ce qui est parti, ce qui est réellement arrivé.
/// - E6 « Not sure yet » : pas confirmé, ou impossible de trancher → « Check again », jamais « Swap again ».
/// - « Not swapped » : l'autorisation signée peut encore servir → attendre l'heure dite, aucun bouton pour refaire.
/// - « Nothing was swapped » : certain → « Try again ».
struct SwapStatusView: View {
    @Bindable var model: SwapFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(ActivityViewModel.self) private var appActivity: ActivityViewModel?
    #if DESIGN_CATALOG
    /// Catalogue et aperçus, sans historique de l'app : l'historique factice, aux mêmes adresses que le parcours factice.
    @State private var mockActivity = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
    #endif
    @State private var isReceiptPresented = false
    @State private var seed = ChimpyLines.seed()

    var body: some View {
        Group {
            switch model.stage {
            case .finished(.sent(let receipt)):
                SwapSentView(receipt: receipt, onDone: model.finish, onReceipt: { isReceiptPresented = true })
                    .chimpSheet(isPresented: $isReceiptPresented, height: ChimpSize.cardTapSheetHeight, fitsContent: true) {
                        if let activity, let printed = activity.receipt(forSent: receipt.activityRecord(venue: ""), locale: locale) {
                            ActivityReceiptSheet(receipt: printed, model: activity) { again in
                                isReceiptPresented = false
                                model.receiptAgain(again)
                            }
                        } else {
                            ReceiptUnavailableNote()
                        }
                    }
            case .finished(.notConfirmed), .finished(.undetermined):
                notSureYet
            default:
                statusScreen
            }
        }
        .blocksSwipeBack(true)
    }

    /// L'historique de l'app ; sans lui (hors des onglets), aucun reçu, jamais un faux (Release). Le catalogue prend
    /// l'historique factice.
    private var activity: ActivityViewModel? {
        #if DESIGN_CATALOG
        appActivity ?? mockActivity
        #else
        appActivity
        #endif
    }

    // MARK: E6 · Not sure yet

    private var notSureYet: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                Image(.chimpyTeacher)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 230)
                    .accessibilityHidden(true)
                Text("Not sure yet")
                    .chimpFont(.displayL)
                    .foregroundStyle(Color(.chimpOnHeaderPrimary))
                    .accessibilityAddTraits(.isHeader)
                Text("We couldn't confirm the swap. Your \(model.summary?.given.code ?? "XLM") may already be swapped. Check again before trying anything else.")
                    .chimpFont(.bodyL)
                    .foregroundStyle(Color(.chimpOnHeaderSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let details = model.technicalDetails {
                    ChimpTechnicalDetails(details: details)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.xs) {
                ChimpButton("Check again", action: model.checkAgain)
                if let url = model.explorerURL {
                    ChimpButton("View on Stellar Expert", kind: .linkOnHeader) { openURL(url) }
                }
                ChimpButton("Back to my wallet", kind: .linkOnHeader, action: model.finish)
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }

    // MARK: Envoi en cours, attente, rien n'est parti (écrans d'Envoyer)

    private var statusScreen: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    content
                    if model.pendingSaveFailed {
                        ChimpNoticeBanner(text: "This phone couldn't save this swap. Don't swap again before you've checked it.", marker: .error)
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
        switch model.stage {
        case .finished(.waiting): "Not swapped"
        case .finished(.nothingSent): "Nothing was swapped"
        case .checking: "Checking with Stellar"
        default: "Swapping…"
        }
    }

    private var subtitle: LocalizedStringKey? {
        switch model.stage {
        case .sending, .checking: "Keep the app open"
        default: nil
        }
    }

    private var showsTechnicalDetails: Bool {
        if case .finished = model.stage { return true }
        return false
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
            waiting(until: until)
            if let frozen = model.frozenAtSend {
                ChimpFieldMessage(text: "\(frozen.issuerName ?? String(localized: "The issuer")) froze your \(frozen.code). Nothing moved.", kind: .error)
            } else if let reason = model.failureReason {
                ChimpFieldMessage(text: SendStatusView.message(for: reason), kind: .info)
            }
        case .finished(.nothingSent):
            if let frozen = model.frozenAtSend {
                ChimpySays(text: "\(frozen.issuerName ?? String(localized: "The issuer")) froze your \(frozen.code). Nothing moved.", pose: .peel)
            } else {
                ChimpySays(text: "Your \(model.summary?.given.code ?? "XLM") didn't move. You can try again.", pose: .peel)
            }
        default:
            EmptyView()
        }
    }

    private func sendingSteps(_ progress: PaymentProgress) -> [ChimpProgressStep] {
        let order: [PaymentProgress] = [.checking, .sending, .confirming]
        let reached = order.firstIndex(of: progress) ?? 0
        let labels = [Text("Checking with Stellar"), Text("Swapping"), Text("Confirming")]
        var steps = [ChimpProgressStep(id: 0, label: Text("Signed by \(model.signed?.cardName ?? "")"), state: .done)]
        for (index, label) in labels.enumerated() {
            let state: ChimpProgressStep.State = index < reached ? .done : (index == reached ? .current : .todo)
            steps.append(ChimpProgressStep(id: index + 1, label: label, state: state))
        }
        return steps
    }

    /// « Not swapped. Please wait until {heure} before trying again », avec un compte à rebours. Signature encore en
    /// mémoire (revue F3) : « Try again » la renvoie, sans nouveau tap, jusqu'à cette heure.
    private func waiting(until: Date) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text(model.canResend
                 ? "Not swapped yet. Your card's signature still works until \(until.formatted(date: .omitted, time: .shortened))."
                 : "Not swapped. Please wait until \(until.formatted(date: .omitted, time: .shortened)) before trying again.")
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
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: ChimpSpacing.xs) {
            switch model.stage {
            case .finished(.nothingSent):
                if model.canTryAgain {
                    ChimpButton("Try again", action: model.tryAgain)
                    ChimpButton("Back to my wallet", kind: .link, action: model.finish)
                } else {
                    ChimpButton("Back to my wallet", action: model.finish)
                }
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

    private func details(_ summary: SwapSummary) -> [ChimpDetailItem] {
        [
            ChimpDetailItem(id: "in", label: "In", value: summary.drawerTitle),
            ChimpDetailItem(id: "give", label: "You give", value: summary.given.formattedWithCode(summary.amountIn, locale: locale)),
            ChimpDetailItem(id: "minimum", label: "At least", value: summary.received.displayedWithCode(summary.minimumOut, locale: locale)),
            ChimpDetailItem(id: "protocol", label: "Protocol", value: summary.protocolName),
        ]
    }
}

/// E5 · « Swapped! » : fond Leaf et motif, Chimpy aux deux bananes, ce qui est parti (−400 XLM) et ce qui est réellement
/// arrivé (+99.71 USDC), « In Main · heure », « Back to my wallet » et « See the receipt ».
struct SwapSentView: View {
    let receipt: SwapReceipt
    let onDone: () -> Void
    let onReceipt: () -> Void

    @Environment(\.locale) private var locale

    private var summary: SwapSummary { receipt.summary }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 0) {
                Image(.chimpyUnsure)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .chimpBob(duration: 3.5)
                    .accessibilityHidden(true)
                Text("Swapped!")
                    .chimpFont(.welcomeTitle)
                    .padding(.top, ChimpSpacing.l)
                    .accessibilityAddTraits(.isHeader)
                Text("Fresh \(summary.received.code) in \(summary.drawerShortTitle). \(Text(quip))")
                    .chimpFont(.lead)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.s)
                VStack(spacing: ChimpSpacing.s) {
                    amountRow(label: "Went out", value: "\u{2212}\(summary.given.displayedWithCode(summary.amountIn, locale: locale))", color: Color(.chimpStampPaid))
                    amountRow(label: "Came in", value: cameIn, color: Color(.chimpStampReceived))
                }
                .padding(.top, ChimpSpacing.l)
                Text("In \(summary.drawerShortTitle) · \(receipt.sentAt.formatted(date: .omitted, time: .shortened))")
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
                .overlay { ChimpBananaBurst() }
                .ignoresSafeArea()
        }
    }

    /// Ce qui est réellement arrivé ; s'il n'a pas pu être lu, le minimum garanti.
    private var cameIn: String {
        if let received = receipt.receivedAmount {
            return "+\(summary.received.displayedWithCode(received, locale: locale))"
        }
        return String(localized: "at least \(summary.received.displayedWithCode(summary.minimumOut, locale: locale))")
    }

    /// Une petite phrase selon ce qui est arrivé par rapport au devis.
    private var quip: LocalizedStringKey {
        guard let received = receipt.receivedAmount else { return "At least what you agreed to." }
        if received > summary.expectedOut { return "A little more than the quote, lucky monkey." }
        if received == summary.expectedOut { return "Right on the quote." }
        return "A hair under the quote, still above your minimum."
    }

    private func amountRow(label: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            Text(label).chimpFont(.bodyS).fontWeight(.black)
            Spacer(minLength: ChimpSpacing.s)
            Text(verbatim: value)
                .chimpFont(.key)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .padding(.vertical, 10)
        .padding(.horizontal, ChimpSpacing.l)
        .background(RoundedRectangle(cornerRadius: ChimpRadius.key).fill(Color(.chimpTicketPaper)))
        .overlay { RoundedRectangle(cornerRadius: ChimpRadius.key).strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
        .background { RoundedRectangle(cornerRadius: ChimpRadius.key).fill(Color(.chimpTicketInk)).offset(x: 3, y: 3) }
        .accessibilityElement(children: .combine)
    }
}
