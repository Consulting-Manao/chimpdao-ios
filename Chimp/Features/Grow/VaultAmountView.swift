import SwiftUI

/// F3 · « Put money in » et F7 · « Take money out » (maquettes du 2026-10-15) : tiroir (« FROM Main ▾ », ou « BACK TO
/// Main » fixe pour un retrait : l'argent revient au tiroir qui détient la position), montant, solde avant → après,
/// « Max » ou « All », l'avertissement du vault, pavé, « Check it over ».
/// États : pas assez (F3a ; retrait : plus que la position, avec « All »), vault indisponible (F3b), une autre opération
/// attend son issue (F3c). Les parts ne s'affichent que sur les reçus (décision de Barth du 2026-10-15).
struct VaultAmountView: View {
    @Bindable var model: VaultFlowModel
    let onBack: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isDeposit: Bool { model.action == .deposit }
    private var asset: SendAsset { model.asset }
    private var vaultName: String { model.context?.vault.name ?? "DeFindex XLM" }
    private var drawerName: String { model.selectedDrawer.map(GrowView.shortTitle) ?? String(localized: "Main") }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: isDeposit ? "Put money in" : "Take money out",
                subtitle: isDeposit ? "\(vaultName) vault" : "\(vaultName) vault · in \(drawerName)",
                onBack: onBack
            )
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
                ScrollView {
                    VStack(spacing: ChimpSpacing.sm) {
                        drawerBar
                        amountCard
                        notice
                        if let vault = model.context?.vault {
                            ChimpVaultNotice(asset: vault.asset.code, protocols: vault.protocols)
                                .padding(.top, ChimpSpacing.xs)
                        }
                    }
                    .padding(.horizontal, ChimpSpacing.xxl)
                    .padding(.top, ChimpSpacing.ml)
                    .padding(.bottom, ChimpSpacing.s)
                    .redacted(reason: model.loadPhase == .loading ? .placeholder : [])
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                if !dynamicTypeSize.isAccessibilitySize {
                    ChimpKeypad(mode: .amount, isCompact: isSmallScreen) { key in
                        ChimpSoundPlayer.shared.play(.tap)
                        model.press(key)
                    }
                    .padding(.horizontal, ChimpSpacing.lg)
                    .disabled(model.loadPhase != .loaded)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            mainButton
                .padding(.horizontal, ChimpSpacing.bottomBar.leading)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
    }

    // MARK: Tiroir

    /// « FROM Main ▾ » (mettre) ; « BACK TO Main · 800 → 850.12 » (retirer, fixe).
    private var drawerBar: some View {
        let drawer = model.selectedDrawer
        return Button {
            model.showDrawerSheet()
        } label: {
            HStack(spacing: ChimpSpacing.sm) {
                Text(isDeposit ? "From" : "Back to")
                    .textCase(.uppercase)
                    .chimpFont(.label)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpDrawerIconView(icon: drawer?.icon ?? .main, size: CGSize(width: 30, height: 20), border: 2.5, cornerRadius: 6)
                Text(verbatim: drawerName)
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                Spacer(minLength: 0)
                if !isDeposit, let drawer {
                    balanceChange(before: drawer.balance(of: asset), after: model.currentQuote?.expected.map { drawer.balance(of: asset) + $0 })
                } else if model.canChooseDrawer {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .black)).foregroundStyle(.chimpTextPrimary)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurfaceSecondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .disabled(!isDeposit || !model.canChooseDrawer)
        .accessibilityLabel(Text(isDeposit ? "From \(drawerName)" : "Back to \(drawerName)"))
    }

    private func balanceChange(before: Decimal, after: Decimal?) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: asset.displayed(before, locale: locale))
            if let after {
                Text(verbatim: "→")
                Text(verbatim: asset.displayed(after, locale: locale)).fontWeight(.black).foregroundStyle(Color(.chimpPositive))
            }
        }
        .chimpFont(.captionStrong)
        .foregroundStyle(.chimpTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Montant

    private var amountCard: some View {
        let issue = model.amountIssue
        return VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text(isDeposit ? "You put in" : "You take out")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.m) {
                if !isDeposit, model.withdrawAll {
                    Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                }
                ChimpTabularText.text(model.amount.displayText(locale: locale), style: .displayL, dynamicTypeSize: dynamicTypeSize)
                    .chimpFont(.displayL)
                    .foregroundStyle(issue != nil ? Color(.chimpNegative) : (model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: model.amount)
                    .accessibilityLabel(Text(isDeposit ? "You put in" : "You take out"))
                    .accessibilityValue(Text(verbatim: "\(model.amount.displayText(locale: locale)) \(asset.code)"))
                Spacer(minLength: ChimpSpacing.s)
                ChimpAssetPill(glyph: asset.glyph, title: asset.code, isChoosable: false) {}
                    .fixedSize()
                    .allowsHitTesting(false)
                maxButton(highlighted: issue != nil)
            }
            if let issue {
                Text(issueLine(issue))
                    .chimpFont(.captionStrong)
                    .foregroundStyle(Color(.chimpNegative))
            } else {
                balanceLine
            }
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    /// « 800 → 750 XLM in Main » (mettre) ; « 50.12 → 0 XLM in the vault » (retirer).
    private var balanceLine: some View {
        let value = model.withdrawAll ? model.available : model.amount.value
        let after: Decimal? = value > 0 && value <= model.available ? model.available - value : nil
        return HStack(spacing: 4) {
            Text(verbatim: asset.displayed(model.available, locale: locale))
            if let after {
                Text(verbatim: "→")
                Text(verbatim: asset.displayed(after, locale: locale)).fontWeight(.black).foregroundStyle(.chimpTextPrimary)
            }
            Text(isDeposit ? "\(asset.code) in \(drawerName)" : "\(asset.code) in the vault")
        }
        .chimpFont(.captionStrong)
        .foregroundStyle(.chimpTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func issueLine(_ issue: VaultFlowModel.AmountIssue) -> LocalizedStringKey {
        switch issue {
        case let .insufficient(drawer, available, asset):
            "Only \(asset.displayedWithCode(available, locale: locale)) in \(drawer)"
        case let .moreThanPosition(available, asset):
            "Only \(asset.displayedWithCode(available, locale: locale)) in the vault. Tap All to take everything."
        }
    }

    private func maxButton(highlighted: Bool) -> some View {
        Button(isDeposit ? "Max" : "All") { model.setMax() }
            .chimpFont(.buttonSmall)
            .foregroundStyle(Color(highlighted || model.withdrawAll ? .chimpOnAccent : .chimpTextPrimary))
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .cartoonSurface(Capsule(), fill: highlighted || model.withdrawAll ? Color(.chimpAccent) : Color(.chimpSurfaceSecondary), border: ChimpBorder.thin)
            .buttonStyle(ChimpPressableStyle())
            .fixedSize()
            .disabled(model.available <= 0)
            .accessibilityHint(Text(isDeposit ? "Puts everything in this drawer in the vault" : "Takes every share out of the vault"))
    }

    // MARK: États (F3b, F3c)

    @ViewBuilder
    private var notice: some View {
        if model.blockedByPendingPayment {
            ChimpNoticeBanner(text: "A payment is still being checked. Check it first.", marker: .error)
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
            ChimpButton(isDeposit ? "Not enough \(asset.code)" : "More than you have") {}
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
