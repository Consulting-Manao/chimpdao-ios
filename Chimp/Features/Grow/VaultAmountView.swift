import SwiftUI

/// G3 · « How much to plant? » et G5 · « How much to take out? » (maquette « Chimp Grow Final », 2026-10-18) : le tiroir
/// (« FROM Main ▾ », ou « TO Main » fixe pour un retrait : l'argent revient au tiroir qui détient la position) avec son
/// solde avant → après, le montant au centre, la pastille du protocole, les raccourcis (10 · 50 · 100 · Max ; retrait :
/// 10 · 50 · All, ou Max quand tout ne peut pas sortir), une note si tout ne peut pas sortir, le pavé, « Check it over ».
/// États gardés : pas assez, plus que la position, protocole indisponible, une autre opération attend son issue.
/// Ni risques ni protocoles sous-jacents (décision de Barth du 2026-10-18).
struct VaultAmountView: View {
    @Bindable var model: VaultFlowModel
    let onBack: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isDeposit: Bool { model.action == .deposit }
    private var asset: SendAsset { model.asset }
    private var mark: ChimpPotProtocol { model.isLending ? .xoxno : .defindex }
    private var drawerName: String { model.selectedDrawer.map { GrowView.shortTitle($0) } ?? String(localized: "Main") }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: isDeposit ? "How much to plant?" : "How much to take out?", step: 1, steps: 2, onBack: onBack)
            content
        }
        .background(Color(.chimpBackground))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: model.rejectedKeyCount)
        .chimpSheet(isPresented: $model.isDrawerSheetPresented, height: CGFloat(250 + 76 * model.drawers.count)) {
            drawerSheet
        }
        .navigationDestination(isPresented: $model.isReviewPresented) {
            VaultReviewView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            let isSmallScreen = proxy.size.height < ChimpSize.compactAmountScreenHeight
            VStack(spacing: 0) {
                drawerBar
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                ScrollView {
                    VStack(spacing: 0) {
                        amountBlock
                        quickPicks.padding(.top, 16)
                        notice
                            .padding(.top, 14)
                            .padding(.horizontal, 22)
                    }
                    .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - (isSmallScreen ? 260 : 330)))
                    .redacted(reason: model.loadPhase == .loading ? .placeholder : [])
                }
                .scrollBounceBehavior(.basedOnSize)
                if !dynamicTypeSize.isAccessibilitySize {
                    ChimpKeypad(mode: .amount, isCompact: isSmallScreen) { key in
                        ChimpSoundPlayer.shared.play(.tap)
                        model.press(key)
                    }
                    .padding(.horizontal, 18)
                    .disabled(model.loadPhase != .loaded)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            mainButton
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
    }

    // MARK: Tiroir

    /// « FROM Main · 800 → 750 XLM ▾ » (mettre) ; « TO Main · 800 → 830 XLM » (retirer, fixe).
    private var drawerBar: some View {
        let drawer = model.selectedDrawer
        return Button {
            model.showDrawerSheet()
        } label: {
            HStack(spacing: 10) {
                Text(isDeposit ? "From" : "To")
                    .textCase(.uppercase)
                    .chimpFont(.label)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpDrawerIconView(icon: drawer?.icon ?? .main, size: CGSize(width: 30, height: 20), border: 2.5, cornerRadius: 6)
                Text(verbatim: drawer?.title ?? drawerName)
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let drawer {
                    balanceChange(before: drawer.balance(of: asset), after: balanceAfter(drawer))
                }
                if isDeposit, model.canChooseDrawer {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .black)).foregroundStyle(.chimpTextPrimary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 13)
            .cartoonSurface(RoundedRectangle(cornerRadius: 16), fill: Color(.chimpSurfaceSecondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .disabled(!isDeposit || !model.canChooseDrawer)
        .accessibilityLabel(Text(isDeposit ? "From \(drawerName)" : "To \(drawerName)"))
    }

    /// Mettre : le solde moins le montant. Retirer : le solde plus ce qui est attendu.
    private func balanceAfter(_ drawer: SendDrawer) -> Decimal? {
        let before = drawer.balance(of: asset)
        if isDeposit {
            let value = model.withdrawAll ? model.available : model.amount.value
            return value > 0 && value <= before ? before - value : nil
        }
        return model.currentQuote?.expected.map { before + $0 }
    }

    private func balanceChange(before: Decimal, after: Decimal?) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: after == nil ? asset.displayedWithCode(before, locale: locale) : asset.displayed(before, locale: locale))
            if let after {
                Text(verbatim: "→").chimpFont(.pill)
                Text(verbatim: asset.displayedWithCode(after, locale: locale)).fontWeight(.black).foregroundStyle(.chimpTextPrimary)
            }
        }
        .chimpFont(.captionStrong)
        .foregroundStyle(.chimpTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Montant

    /// Le montant au centre (rouge s'il dépasse), puis « XLM into DeFindex » / « XLM out of DeFindex ».
    private var amountBlock: some View {
        let issue = model.amountIssue
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.s) {
                if !isDeposit, model.withdrawAll {
                    Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                }
                ChimpTabularText.text(model.amount.displayText(locale: locale), style: .amountEntry, dynamicTypeSize: dynamicTypeSize)
                    .chimpFont(.amountEntry)
                    .foregroundStyle(issue != nil ? Color(.chimpNegative) : (model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: model.amount)
                    .accessibilityLabel(Text(isDeposit ? "You plant" : "You take out"))
                    .accessibilityValue(Text(verbatim: "\(model.amount.displayText(locale: locale)) \(asset.code)"))
            }
            .padding(.horizontal, 22)
            HStack(spacing: 8) {
                ChimpProtocolLogo(mark: mark, size: 24, border: ChimpBorder.regular)
                Text(isDeposit ? "\(asset.code) into \(mark.name)" : "\(asset.code) out of \(mark.name)")
                    .chimpFont(.pill)
                    .foregroundStyle(.chimpTextPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .cartoonSurface(Capsule(), fill: Color(.chimpSurface))
            if let issue {
                Text(issueLine(issue))
                    .chimpFont(.captionStrong)
                    .foregroundStyle(Color(.chimpNegative))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }
        }
        .padding(.top, ChimpSpacing.l)
    }

    /// Mettre : 10 · 50 · 100 · Max. Retirer : 10 · ce qui peut sortir maintenant (s'il y a une limite) · All.
    private var quickPicks: some View {
        let picks = VaultAmountView.quickPicks(deposit: isDeposit, available: model.available, now: model.withdrawableNow)
        return HStack(spacing: 8) {
            ForEach(picks, id: \.self) { pick in
                ChimpQuickPick(title: asset.displayed(pick, locale: locale), isSelected: !model.withdrawAll && model.amount.value == pick) {
                    model.setAmount(pick)
                }
            }
            ChimpQuickPick(title: maxTitle, isSelected: model.withdrawAll || (isDeposit && model.available > 0 && model.amount.value == model.available)) {
                model.setMax()
            }
            .disabled(model.available <= 0)
        }
        .disabled(model.loadPhase != .loaded)
    }

    /// Les raccourcis chiffrés : ceux qui tiennent dans ce qu'on a (et, pour un retrait, dans ce qui peut sortir
    /// maintenant). « Max » met déjà ce qui peut sortir maintenant : pas de raccourci en double.
    static func quickPicks(deposit: Bool, available: Decimal, now: Decimal?) -> [Decimal] {
        if deposit { return [10, 50, 100].filter { $0 < available } }
        return [10, 50].filter { $0 < min(available, now ?? available) }
    }

    private var maxTitle: String {
        isDeposit || (model.withdrawableNow.map { $0 < model.available } ?? false) ? String(localized: "Max") : String(localized: "All")
    }

    private func issueLine(_ issue: VaultFlowModel.AmountIssue) -> LocalizedStringKey {
        switch issue {
        case let .insufficient(drawer, available, asset):
            "Only \(asset.displayedWithCode(available, locale: locale)) in \(drawer)"
        case let .moreThanPosition(available, asset):
            "Only \(asset.displayedWithCode(available, locale: locale)) in \(mark.name). Tap All to take everything."
        case let .moreThanAvailableNow(available, asset):
            "\(mark.name) can give back \(asset.displayedWithCode(available, locale: locale)) right now."
        }
    }

    // MARK: États

    @ViewBuilder
    private var notice: some View {
        if model.blockedByPendingPayment {
            ChimpNoticeBanner(text: "A payment is still being checked. Check it first.", marker: .error)
        } else if model.isBlockedByMarket {
            ChimpNoticeBanner(
                text: isDeposit ? "XOXNO isn't taking deposits right now." : "XOXNO has paused withdrawals right now. Your money is still there.",
                marker: .error
            )
        } else if model.isLending, !isDeposit, model.movablePositionCount > 1 {
            ChimpGrowNote(text: "\(drawerName) has \(model.movablePositionCount) positions. This takes money out of the biggest one (\(asset.displayedWithCode(model.available, locale: locale))); then you can take out the next.")
        } else if model.isLending, !isDeposit, let now = model.withdrawableNow, now < model.available {
            // G5 : une note dans l'écran, pas un écran d'erreur.
            ChimpGrowNote(text: "XOXNO can give back \(asset.displayedWithCode(now, locale: locale)) right now. The rest comes back as borrowers repay.")
        } else if model.loadPhase == .unavailable {
            problem(title: "The vault is unavailable right now", line: "Nothing moved. Try again in a minute.")
        } else if case .failed(let issue) = model.quoteState {
            switch issue {
            case .vaultUnavailable, .network:
                problem(title: "The vault is unavailable right now", line: "Nothing moved. Try again in a minute.")
            case .implausible:
                problem(title: "The vault's numbers don't look right", line: "I won't show them or sign anything. Nothing moved.")
            case .amountTooSmall:
                problem(title: "That's too little for the vault", line: "Try a bigger amount.")
            }
        }
    }

    private func problem(title: LocalizedStringKey, line: LocalizedStringKey) -> some View {
        HStack(spacing: ChimpSpacing.m) {
            Image(.tileHead).resizable().scaledToFit().frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).chimpFont(.buttonSecondary).foregroundStyle(.chimpTextPrimary)
                Text(line).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 13)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurfaceSecondary))
        .accessibilityElement(children: .combine)
    }

    // MARK: Bouton

    @ViewBuilder
    private var mainButton: some View {
        if model.blockedByPendingPayment {
            ChimpButton("Check again", isLoading: model.isCheckingPendingPayment) {
                Task { await model.checkPendingPayment() }
            }
        } else if model.loadPhase == .unavailable || model.loadPhase == .failed {
            ChimpButton("Try again") { Task { await model.load() } }
        } else if case .failed(let issue) = model.quoteState, issue != .amountTooSmall {
            ChimpButton("Try again") { Task { await model.refreshQuote() } }
        } else if model.quoteState == .loading {
            ChimpButton("Checking the vault…") {}
                .disabled(true)
        } else if model.amountIssue != nil {
            ChimpButton(isDeposit ? "Not enough \(asset.code)" : (model.amountIssue?.isAvailableNow == true ? "More than can come out now" : "More than you have")) {}
                .disabled(true)
        } else {
            ChimpButton("Check it over") { model.continueToReview() }
                .disabled(!model.canReview)
        }
    }

    // MARK: Feuille du tiroir (mettre)

    private var drawerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Put money in from where?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(model.drawers) { drawer in
                    ChimpDrawerOptionRow(
                        icon: drawer.icon, title: drawer.title,
                        subtitle: asset.displayedWithCode(drawer.balance(of: asset), locale: locale),
                        isSelected: drawer.id == model.selectedDrawer?.id
                    ) {
                        model.select(drawerID: drawer.id)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)
            ChimpySays(text: "The position stays with the drawer it came from. From a card's wallet, only that card can take it out.", pose: .unsure)
                .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }
}
