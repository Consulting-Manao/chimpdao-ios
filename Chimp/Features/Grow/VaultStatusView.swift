import SwiftUI

/// Après le tap (maquettes F5, F7s, F8a à F8c du 2026-10-15 ; l'attente reprend Envoyer avec des textes adaptés,
/// décision de Barth du 2026-10-15). Rien ne peut interrompre ces écrans : on n'en sort que par leurs boutons.
///
/// - « Putting it in… » / « Taking it out… » : les étapes (signé par la carte, vérification, envoi, confirmation).
/// - F5 « Planted! » : ce qui est entré ; « See my position ».
/// - F7s « Back home! » : ce qui est revenu.
/// - F8a, F8b « Not sure yet » : pas confirmé, ou impossible de trancher → « Check again », jamais un nouveau dépôt.
/// - « Not moved » : l'autorisation signée peut encore servir → attendre l'heure dite.
/// - F8c « Nothing was moved » : certain → « Try again ».
///
/// Les parts ne s'affichent que sur les reçus (décision de Barth du 2026-10-15) : F5 et F7s n'en parlent pas.
struct VaultStatusView: View {
    @Bindable var model: VaultFlowModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var seed = ChimpyLines.seed()

    private var isDeposit: Bool { (model.summary?.action ?? model.action) == .deposit }
    private var assetCode: String { model.summary?.asset.code ?? "XLM" }

    var body: some View {
        Group {
            switch model.stage {
            case .finished(.sent(let receipt)):
                VaultSentView(receipt: receipt, protocols: model.protocols, onPosition: model.seePosition, onDone: model.finish)
            case .finished(.notConfirmed), .finished(.undetermined):
                notSureYet
            case .finished(.nothingSent):
                nothingMoved
            default:
                statusScreen
            }
        }
        .blocksSwipeBack(true)
    }

    // MARK: F8a, F8b · Not sure yet

    private var notSureYet: some View {
        fullScreen(pose: .chimpyTeacher, title: "Not sure yet", text: isDeposit
            ? "We couldn't confirm the deposit. Your \(assetCode) may already be in \(model.summary?.placeName ?? String(localized: "the vault")). Check again before trying anything else."
            : "We couldn't confirm the withdrawal. Your \(assetCode) may already be back in \(model.summary?.drawerShortTitle ?? "Main"). Check again before trying anything else."
        ) {
            ChimpButton("Check again", action: model.checkAgain)
            if let url = model.explorerURL {
                ChimpButton("View on Stellar Expert", kind: .linkOnHeader) { openURL(url) }
            }
            ChimpButton("Back to my wallet", kind: .linkOnHeader, action: model.finish)
        }
    }

    // MARK: F8c · Nothing was moved

    private var nothingMoved: some View {
        fullScreen(pose: .chimpyPeel, title: "Nothing was moved", text: nothingMovedText) {
            if model.canTryAgain {
                ChimpButton("Try again", action: model.tryAgain)
                ChimpButton("Back to my wallet", kind: .linkOnHeader, action: model.finish)
            } else {
                ChimpButton("Back to my wallet", action: model.finish)
            }
        }
    }

    /// « The network said no. Your 50 XLM is still in Main, safe and sound. Probably a hiccup. » Retirer : la position.
    private var nothingMovedText: LocalizedStringKey {
        guard let summary = model.summary else { return "The network said no. Nothing moved. Probably a hiccup." }
        if summary.action == .deposit {
            return "The network said no. Your \(summary.asset.formattedWithCode(summary.amount, locale: locale)) is still in \(summary.drawerShortTitle), safe and sound. Probably a hiccup."
        }
        return "The network said no. Your \(summary.asset.code) is still in \(summary.placeName), safe and sound. Probably a hiccup."
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
                GrowPlaceNotice(lending: model.summary?.kind == .lending, asset: assetCode, protocols: model.protocols, ink: Color(.chimpOnHeaderPrimary))
                    .padding(.top, ChimpSpacing.xs)
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

    // MARK: Envoi en cours, attente (écrans d'Envoyer)

    private var statusScreen: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    content
                    if model.pendingSaveFailed {
                        ChimpNoticeBanner(text: "This phone couldn't save this operation. Don't try again before you've checked it.", marker: .error)
                    }
                    if let summary = model.summary {
                        ChimpDetailList(items: details(summary))
                    }
                    GrowPlaceNotice(lending: model.summary?.kind == .lending, asset: assetCode, protocols: model.protocols)
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
        case .finished(.waiting): "Not moved"
        case .checking: "Checking with Stellar"
        default: isDeposit ? "Putting it in…" : "Taking it out…"
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
        let labels = [Text("Checking with Stellar"), isDeposit ? Text("Putting it in") : Text("Taking it out"), Text("Confirming")]
        var steps = [ChimpProgressStep(id: 0, label: Text("Signed by \(model.signed?.cardName ?? "")"), state: .done)]
        for (index, label) in labels.enumerated() {
            let state: ChimpProgressStep.State = index < reached ? .done : (index == reached ? .current : .todo)
            steps.append(ChimpProgressStep(id: index + 1, label: label, state: state))
        }
        return steps
    }

    /// « Not moved. Please wait until {heure} before trying again », avec un compte à rebours.
    private func waiting(until: Date) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text("Not moved. Please wait until \(until.formatted(date: .omitted, time: .shortened)) before trying again.")
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
            switch model.stage {
            case .finished(.waiting):
                ChimpButton("Back to my wallet", kind: .secondary, action: model.finish)
            default:
                ChimpButton("Back to my wallet", isLoading: true) {}
                    .disabled(true)
            }
        }
    }

    /// Mettre : depuis, ce qui part. Retirer : vers, ce qui est attendu, le minimum signé.
    private func details(_ summary: VaultSummary) -> [ChimpDetailItem] {
        var items = summary.kind == .lending
            ? [ChimpDetailItem(id: "vault", label: "Market", value: summary.vaultName)]
            : [ChimpDetailItem(id: "vault", label: "Vault", value: "\(summary.vaultName) vault")]
        if summary.action == .deposit {
            items.append(ChimpDetailItem(id: "from", label: "From", value: summary.drawerTitle))
            items.append(ChimpDetailItem(id: "in", label: "You put in", value: summary.asset.formattedWithCode(summary.amount, locale: locale)))
        } else {
            items.append(ChimpDetailItem(id: "to", label: "Lands in", value: summary.drawerTitle))
            if let minimum = summary.minimumOut {
                items.append(ChimpDetailItem(id: "minimum", label: summary.kind == .lending ? "Comes back" : "At least", value: summary.asset.displayedWithCode(minimum, locale: locale)))
            }
        }
        return items
    }
}

/// F5 « Planted! » et F7s « Back home! » : fond Leaf et motif, Chimpy, ce qui est entré (−50 XLM) ou revenu
/// (+50.13 XLM), « From Main · date » / « In Main · date », l'avertissement, puis « See my position » (F5) ou
/// « Back to my wallet » (F7s).
struct VaultSentView: View {
    let receipt: VaultReceipt
    let protocols: [String]
    let onPosition: () -> Void
    let onDone: () -> Void

    @Environment(\.locale) private var locale

    private var summary: VaultSummary { receipt.summary }
    private var isDeposit: Bool { summary.action == .deposit }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 0) {
                Image(isDeposit ? .chimpyPlant : .chimpyUnsure)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 190)
                    .chimpBob(duration: 3.5)
                    .accessibilityHidden(true)
                Text(isDeposit ? "Planted!" : "Back home!")
                    .chimpFont(.welcomeTitle)
                    .padding(.top, ChimpSpacing.l)
                    .accessibilityAddTraits(.isHeader)
                Text(lead)
                    .chimpFont(.lead)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.s)
                amountRow
                    .padding(.top, ChimpSpacing.l)
                Text(place)
                    .chimpFont(.captionStrong)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(.white.opacity(0.35)))
                    .overlay { Capsule().strokeBorder(ChimpCardColor.leaf.ink, lineWidth: 2) }
                    .padding(.top, ChimpSpacing.m)
                GrowPlaceNotice(lending: summary.kind == .lending, asset: summary.asset.code, protocols: protocols, ink: ChimpCardColor.leaf.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.top, ChimpSpacing.l)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(ChimpCardColor.leaf.ink)
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.m) {
                if isDeposit {
                    ChimpButton("See my position", action: onPosition)
                    link("Back to my wallet", action: onDone)
                } else {
                    ChimpButton("Back to my wallet", action: onDone)
                }
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .background {
            ChimpCardColor.leaf.fill
                .overlay { ChimpPattern(opacity: 0.14) }
                .ignoresSafeArea()
        }
    }

    /// « 50 XLM is in the DeFindex vault. From now on I'll show you what it really does. » / « Your XLM is back in
    /// Main, ready to use. »
    private var lead: LocalizedStringKey {
        let runner = protocols.first ?? "DeFindex"
        if isDeposit, summary.kind == .lending {
            return "\(summary.asset.formattedWithCode(summary.amount, locale: locale)) is lent through \(runner). From now on I'll show you what it really does."
        }
        if isDeposit {
            return "\(summary.asset.formattedWithCode(summary.amount, locale: locale)) is in the \(runner) vault. From now on I'll show you what it really does."
        }
        return "Your \(summary.asset.code) is back in \(summary.drawerShortTitle), ready to use."
    }

    private var place: LocalizedStringKey {
        let when = receipt.sentAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return isDeposit ? "From \(summary.drawerShortTitle) · \(when)" : "In \(summary.drawerShortTitle) · \(when)"
    }

    /// Mettre : « Went in −50 XLM ». Retirer : « Came in +50.13 XLM », ou le minimum signé s'il n'a pas pu être lu.
    private var amountRow: some View {
        let (label, value, color): (LocalizedStringKey, String, Color) = if isDeposit {
            ("Went in", "\u{2212}\(summary.asset.formattedWithCode(summary.amount, locale: locale))", Color(.chimpStampPaid))
        } else if let received = receipt.received {
            ("Came in", "+\(summary.asset.displayedWithCode(received, locale: locale))", Color(.chimpStampReceived))
        } else {
            ("Came in", String(localized: "at least \(summary.asset.displayedWithCode(summary.minimumOut ?? summary.amount, locale: locale))"), Color(.chimpStampReceived))
        }
        return HStack {
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

    private func link(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chimpFont(.link)
                .foregroundStyle(ChimpCardColor.leaf.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Entrée d'un parcours du vault (F3 ou F7), poussée dans la pile de Grow ou d'un tiroir. Un ViewModel neuf à chaque
/// ouverture ; la vérification est poussée par le ViewModel (`navigationDestination(isPresented:)`), comme Envoyer.
struct VaultFlowRoot: View {
    @State private var model: VaultFlowModel

    init(
        service: VaultService,
        action: VaultAction,
        signingOrder: SigningOrder = SendMockSettings.signingOrder,
        drawerID: String? = nil,
        onSeePosition: @escaping (String) -> Void,
        onExit: @escaping () -> Void
    ) {
        let model = VaultFlowModel(service: service, action: action, signingOrder: signingOrder, initialDrawerID: drawerID)
        model.onExit = onExit
        model.onSeePosition = onSeePosition
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.resumedPending {
                // Une opération signée attend encore son issue : son état, jamais une nouvelle.
                VaultStatusView(model: model)
            } else {
                VaultAmountView(model: model, onBack: { model.finish() })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadIfNeeded() }
    }
}
