import SwiftUI

/// A6 · Pick a PIN (étape 3 sur 3), puis « Hold your Jungle card to finish ».
/// - Infineon sans PIN : saisie, puis confirmation (PIN obligatoire, décision du 2026-09-29).
/// - Infineon qui a déjà un PIN : une saisie, vérifiée par la carte au tap.
/// - DUOX : pas de PIN, seulement le tap.
/// La feuille « Chimp Sign » montre ce que la carte va signer avant d'ouvrir la session NFC (règle 8).
struct PickPINView: View {
    @Bindable var model: AccountSetupModel
    let onBack: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, step: 3, steps: 3, onBack: backAction)
            entry
            finishButtons
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(model.isBusy)
        .chimpSheet(isPresented: $model.isShowingTapSheet, height: ChimpSize.cardTapSheetHeight, isDismissDisabled: model.isBusy) {
            tapSheet
        }
    }

    private var backAction: (() -> Void)? {
        model.isBusy ? nil : onBack
    }

    @ViewBuilder
    private var entry: some View {
        if model.pinMode == .none {
            VStack(spacing: ChimpSpacing.l) {
                Spacer()
                ChimpCardThumbnail(color: model.cardColor)
                middle
                Spacer()
            }
            .padding(.horizontal, ChimpSpacing.xxl)
        } else {
            ChimpPinPad(pin: $model.pinEntry, length: AccountSetupModel.pinLength, state: $model.pinState, onComplete: { model.pinCompleted($0) }) {
                middle.padding(.top, ChimpSpacing.xl)
            }
            .disabled(model.pinStep == .done || model.isBusy)
            .padding(.horizontal, ChimpSpacing.lg)
        }
    }

    private var finishButtons: some View {
        VStack(spacing: ChimpSpacing.xs) {
            ChimpButton("Hold your \(model.displayCardName) card to finish", isLoading: model.isBusy) { model.openTapSheet() }
                .disabled(!model.canFinish)
            if model.pinStep == .done, model.pinMode != .none {
                ChimpButton("Change the PIN", kind: .link) { model.restartPIN() }
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.top, ChimpSpacing.l)
        .padding(.bottom, ChimpSpacing.l)
    }

    private var tapSheet: some View {
        let who: LocalizedStringKey? = model.isRehearsal ? "Practice run: nothing is sent, and the PIN isn't set on the card yet." : nil
        let cancel: (() -> Void)? = model.isBusy ? nil : { model.cancelTapSheet() }
        return CardTapSheet(
            cardName: model.displayCardName,
            cardColor: model.cardColor,
            stepLabel: "Last step",
            what: "Your card signs two things: a check that it's really yours, and the link to your new Main account.",
            who: who,
            pinStatus: model.pinMode == .none ? .notNeeded : .ready,
            isScanning: model.isBusy,
            onScan: onScan,
            onCancel: cancel
        )
    }

    private var title: LocalizedStringKey {
        switch (model.pinMode, model.pinStep) {
        case (.none, _): "Last step"
        case (.existing, .done), (.choose, .done): "PIN ready"
        case (.existing, _): "Your card's PIN"
        case (.choose, .confirm): "Type it again"
        case (.choose, .first): "Pick a 4-digit PIN"
        }
    }

    @ViewBuilder
    private var middle: some View {
        if let problem = model.tapProblem {
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                ChimpySays(text: CardReadingView.message(for: problem.kind), pose: .head)
                ChimpTechnicalDetails(details: problem.technicalDetails)
            }
        } else {
            ChimpySays(text: chimpy, pose: .banana)
        }
    }

    private var chimpy: LocalizedStringKey {
        switch (model.pinMode, model.pinStep) {
        case (.none, _): "This card has no PIN: a tap is all it takes."
        case (_, .done): "All set. Now the card."
        case (.existing, _): "This card already has a PIN. Type it; the card checks it when you tap."
        case (.choose, .confirm): "Once more, to be sure."
        case (.choose, .first): "You'll type it each time the card signs. I don't keep a copy, so pick one you won't forget."
        }
    }
}

/// Code de déblocage (PUK) : la carte le donne **une seule fois** quand elle reçoit son PIN ; il débloque la carte
/// si le PIN est oublié. Comme l'étape « Unlock code » de `NewCardPin.tsx`, avec « I wrote it down ».
/// En répétition, aucun PIN n'est envoyé à la carte : il n'y a donc pas de code, seulement l'écran.
struct UnlockCodeView: View {
    /// Code de 8 octets en hexadécimal, `nil` en répétition.
    let code: String?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Your unlock code")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpySays(text: "If you ever forget your PIN, this code unlocks the card. It's shown only once: write it down.", pose: .stand)
                    Text(verbatim: code.map(Self.grouped) ?? "•••• •••• •••• ••••")
                        .chimpFont(.amountS)
                        .monospaced()
                        .textSelection(.disabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ChimpSpacing.xl + ChimpBorder.regular)
                        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
                        .accessibilityLabel(code == nil ? Text("No code in a practice run") : Text(verbatim: code.map(Self.spelled) ?? ""))
                    if code == nil {
                        ChimpNoticeBanner(text: "Practice run: the card creates this code during the real setup. Nothing was sent to it.")
                    } else {
                        ChimpNoticeBanner(text: "Keep it somewhere safe, away from the card. ChimpDAO can't show it again.")
                    }
                }
                .padding(.top, ChimpSpacing.xxl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpButton(code == nil ? "Continue" : "I wrote it down", action: onDone)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    /// « 0123 4567 89ab cdef » : plus facile à recopier.
    static func grouped(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { start in
            let from = code.index(code.startIndex, offsetBy: start)
            let to = code.index(from, offsetBy: min(4, code.count - start))
            return String(code[from..<to])
        }.joined(separator: " ")
    }

    /// Pour VoiceOver : un caractère à la fois.
    static func spelled(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}

/// Vérifications après le tap. Étape 3 : **répétition à blanc**, tout est simulé, rien n'est envoyé.
struct SetupCheckView: View {
    let model: AccountSetupModel
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Practice run", subtitle: "Nothing is sent")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpReviewSteps(steps: [
                        Text("Check that the card is really yours"),
                        Text("Your Main account (created at the real setup)"),
                        Text("Link \(model.displayCardName) to it"),
                    ])
                    switch model.phase {
                    case .checking, .signed:
                        HStack(spacing: ChimpSpacing.s) {
                            ProgressView()
                            Text("Checking everything on Stellar Testnet…").chimpFont(.body)
                        }
                        .foregroundStyle(.chimpTextSecondary)
                    case .succeeded(let report):
                        ChimpNoticeBanner(text: "All checks passed. Nothing was sent, nothing was created.", marker: .success)
                        ChimpDetailList(items: Self.items(report))
                        if !report.rejectionSamples.isEmpty {
                            ChimpTechnicalDetails(details: report.rejectionSamples.joined(separator: "\n"))
                        }
                    case .failed(let problem):
                        ChimpySays(text: CardReadingView.message(for: problem.kind), pose: .head)
                        ChimpTechnicalDetails(details: problem.technicalDetails)
                    default:
                        EmptyView()
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            Group {
                if case .failed = model.phase {
                    ChimpButton("Try again") { Task { await model.check() } }
                } else {
                    ChimpButton("Continue", isLoading: model.isBusy, action: onContinue)
                        .disabled(model.report == nil)
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.vertical, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(true)
        .task { await model.check() }
    }

    static func items(_ report: RehearsalReport) -> [ChimpDetailItem] {
        var items = [
            ChimpDetailItem(id: "account", label: "Main account address", value: report.account, isMonospaced: true),
            ChimpDetailItem(id: "deploy", label: "Creating it", value: report.accountAlreadyDeployed
                ? String(localized: "Already exists, nothing to create")
                : String(localized: "Would cost \(xlm(report.deploymentFee ?? 0)) XLM, paid by ChimpDAO")),
            ChimpDetailItem(id: "link", label: "Linking the card", value: String(localized: "Would cost \(xlm(report.setOwnerFee)) XLM, paid by ChimpDAO")),
        ]
        if let id = report.possessionRecoveryID {
            items.append(ChimpDetailItem(id: "possession", label: "Card check (recovery_id)", value: String(id), isMonospaced: true))
        }
        if let id = report.setOwnerRecoveryID {
            items.append(ChimpDetailItem(id: "setOwner", label: "Link signature (recovery_id)", value: String(id), isMonospaced: true))
        }
        return items
    }

    /// Stroops → XLM (7 décimales), sans passer par un `Double`.
    static func xlm(_ stroops: UInt32) -> String {
        (Decimal(stroops) / 10_000_000).formatted(.number.precision(.fractionLength(0...7)))
    }
}

/// A7 · How your Jungle works : récapitulatif avant le Wallet. En répétition, « Let's swing » ramène au début.
struct JungleWelcomeView: View {
    let cardName: String
    let cardColor: ChimpCardColor
    /// Carte sans PIN (DUOX) : la phrase sur le PIN est adaptée.
    let hasPIN: Bool
    let isRehearsal: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Welcome to the jungle!", subtitle: "Two things to know")
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.lg) {
                    if isRehearsal {
                        ChimpNoticeBanner(text: "Practice run: nothing was created. Let's swing takes you back to the start.")
                    }
                    drawers
                    VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                        numbered(1, "Main is shared by all your cards. Each card also has its own wallet that only it can spend.")
                        numbered(2, hasPIN
                            ? "Looking is free. Moving money always asks for a tap and your PIN."
                            : "Looking is free. Moving money always asks for a tap of your card.")
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: ChimpSpacing.ml) {
                ChimpySays(text: "Nothing moves between drawers on its own. You do it with Move.", pose: .crawl)
                ChimpButton("Let's swing", action: onFinish)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.ml)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(true)
    }

    private var drawers: some View {
        VStack(spacing: ChimpSpacing.s) {
            VStack(spacing: 2) {
                Text("Main account").chimpFont(.button)
                Text("shared · any of your cards can use it").chimpFont(.captionStrong)
            }
            .foregroundStyle(.chimpOnAccent)
            .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.ml)
            .frame(maxWidth: .infinity)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control - 2), fill: Color(.chimpAccent))
            HStack(spacing: ChimpSpacing.sm) {
                VStack(spacing: ChimpSpacing.s) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 16, weight: .black)).foregroundStyle(.chimpTextSecondary).accessibilityHidden(true)
                    drawer(Text(verbatim: cardName), color: cardColor)
                }
                VStack(spacing: ChimpSpacing.s) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 16, weight: .black)).foregroundStyle(.chimpTextSecondary).accessibilityHidden(true)
                    VStack(spacing: 2) {
                        Text("Next card").chimpFont(.cardName)
                        Text("own wallet").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                    }
                    .foregroundStyle(.chimpTextPrimary)
                    .padding(ChimpSpacing.sm + ChimpBorder.regular)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: ChimpRadius.tab).fill(Color(.chimpSurfaceSecondary)))
                    .overlay {
                        RoundedRectangle(cornerRadius: ChimpRadius.tab)
                            .strokeBorder(Color(.chimpOutline), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [6, 4]))
                    }
                }
            }
        }
        .padding(ChimpSpacing.l + ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
        .accessibilityElement(children: .combine)
    }

    private func drawer(_ name: Text, color: ChimpCardColor) -> some View {
        VStack(spacing: 2) {
            name.chimpFont(.cardName).lineLimit(1)
            Text("own wallet").chimpFont(.captionStrong)
        }
        .foregroundStyle(color.ink)
        .padding(ChimpSpacing.sm + ChimpBorder.regular)
        .frame(maxWidth: .infinity)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.tab), fill: color.fill)
    }

    private func numbered(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: ChimpSpacing.m) {
            Text(verbatim: "\(number)")
                .chimpFont(.buttonSmall)
                .foregroundStyle(.chimpOnAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(.chimpAccent)))
                .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.body)
                .lineSpacing(4)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}
