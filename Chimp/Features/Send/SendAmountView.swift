import SwiftUI

/// C2 · « How much for Maya? » : tiroir source (Main par défaut, solde avant → après), montant dans l'unité
/// de l'actif (« 25 » + « USDC ▾ »), équivalent en dollars pour XLM, pastilles rapides et « Max », pavé.
/// C3 : feuille « Where should it come from? ». Feuille de choix de l'actif (non dessinée).
///
/// Le montant est gardé comme des touches (`AmountEntry`) : sa valeur ne dépend jamais de la langue du téléphone.
struct SendAmountView: View {
    @Bindable var model: SendFlowModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, step: 2, steps: 3, onBack: { dismiss() })
            switch model.loadPhase {
            case .failed:
                failure
            case .loading, .loaded:
                content
            }
        }
        .background(Color(.chimpBackground))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: model.rejectedKeyCount)
        .chimpSheet(isPresented: $model.isDrawerSheetPresented, height: drawerSheetHeight) {
            drawerSheet
        }
        .chimpSheet(isPresented: $model.isAssetSheetPresented, height: assetSheetHeight) {
            assetSheet
        }
        .navigationDestination(isPresented: $model.isReviewPresented) {
            SendReviewPlaceholderView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var title: LocalizedStringKey {
        if let name = model.recipientName {
            "How much for \(name)?"
        } else {
            "How much to send?"
        }
    }

    // MARK: Contenu

    /// Comme dans la maquette : le sélecteur en haut, le montant au centre de l'espace libre, le pavé en bas,
    /// le bouton toujours visible. La zone du montant choisit la version qui tient (grande, compacte, serrée),
    /// et le pavé se resserre sur petit écran : sur iPhone SE, rien ne passe sous le bouton.
    /// Aux tailles de texte d'accessibilité seulement, tout défile d'un bloc (sauf le bouton).
    private var content: some View {
        GeometryReader { proxy in
            let isSmallScreen = proxy.size.height < ChimpSize.compactAmountScreenHeight
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: ChimpSpacing.l) {
                        pickerRow
                        amountBlock(.regular)
                            .padding(.horizontal, ChimpSpacing.xxl)
                        keypad(isCompact: false)
                    }
                    .padding(.vertical, ChimpSpacing.l)
                }
            } else {
                VStack(spacing: 0) {
                    pickerRow
                    ViewThatFits(in: .vertical) {
                        amountBlock(.regular)
                        amountBlock(.compact)
                        amountBlock(.tight)
                    }
                    .padding(.horizontal, ChimpSpacing.xxl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    keypad(isCompact: isSmallScreen)
                }
                .padding(.top, isSmallScreen ? ChimpSpacing.m : ChimpSpacing.l)
            }
        }
        // Le bouton reste toujours visible.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpButton("Check it over") { model.continueToReview() }
                .disabled(!model.canReview)
                .padding(.horizontal, ChimpSpacing.bottomBar.leading)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
    }

    private var pickerRow: some View {
        let isLoading = model.loadPhase == .loading
        return drawerPicker
            .redacted(reason: isLoading ? .placeholder : [])
            .disabled(isLoading)
            .padding(.horizontal, ChimpSpacing.xxl)
    }

    private func keypad(isCompact: Bool) -> some View {
        ChimpKeypad(mode: .amount, isCompact: isCompact) { model.press($0) }
            .padding(.horizontal, ChimpSpacing.lg)
    }

    private var drawerPicker: some View {
        let drawer = model.selectedDrawer
        let line = model.balanceLine
        return ChimpDrawerPicker(
            label: "From",
            icon: drawer?.icon ?? .main,
            title: drawer?.title ?? String(localized: "Main account"),
            balance: line.before,
            balanceAfter: line.after,
            accessibilityHint: "Choose where the money comes from",
            action: model.canChooseDrawer ? { model.showDrawerSheet() } : nil
        )
    }

    /// Versions de la zone du montant, de la plus grande à la plus serrée.
    private enum AmountLayout {
        /// Maquette : montant de 64 pt, pilule de l'actif, pastilles.
        case regular
        /// Montant de 44 pt, écarts réduits.
        case compact
        /// Montant et pilule de l'actif sur la même ligne (iPhone SE avec un message d'erreur).
        case tight
    }

    private func amountBlock(_ layout: AmountLayout) -> some View {
        let gap: CGFloat = layout == .regular ? ChimpSpacing.m : ChimpSpacing.s
        return VStack(spacing: 0) {
            if layout == .tight {
                HStack(alignment: .center, spacing: ChimpSpacing.m) {
                    amountText(style: .amountL)
                    assetPill
                }
            } else {
                amountText(style: layout == .regular ? .amountEntry : .amountL)
            }

            if let usd = model.usdEquivalent {
                Text("≈ \(usd)")
                    .chimpFont(.captionStrong)
                    .foregroundStyle(.chimpTextSecondary)
                    .padding(.top, ChimpSpacing.xxs)
            }

            if layout != .tight {
                assetPill
                    .padding(.top, gap)
            }

            quickAmounts
                .padding(.top, layout == .regular ? ChimpSpacing.l : gap)

            amountMessage
                .padding(.top, gap)
        }
        .padding(.vertical, gap)
    }

    private func amountText(style: ChimpTextStyle) -> some View {
        Text(verbatim: model.amount.displayText(locale: locale))
            .chimpFont(style)
            .foregroundStyle(model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.15), value: model.amount)
            .accessibilityLabel(Text("Amount"))
            .accessibilityValue(Text(verbatim: "\(model.amount.displayText(locale: locale)) \(model.asset.code)"))
    }

    private var assetPill: some View {
        ChimpAssetPill(glyph: model.asset.glyph, title: model.asset.code) {
            model.isAssetSheetPresented = true
        }
    }

    private var quickAmounts: some View {
        HStack(spacing: ChimpSpacing.s) {
            ForEach(model.asset.quickAmounts, id: \.self) { value in
                ChimpChoiceChip(verbatim: model.asset.formatted(value, locale: locale), isSelected: model.isQuickAmountSelected(value)) {
                    model.setAmount(value)
                }
                .disabled(value > model.available)
            }
            ChimpChoiceChip("Max", isSelected: model.isMaxSelected) {
                model.setMax()
            }
            .disabled(model.available <= 0)
            .accessibilityHint(Text("Sends everything in this drawer"))
        }
        .disabled(model.loadPhase != .loaded)
    }

    @ViewBuilder
    private var amountMessage: some View {
        if let issue = model.amountIssue {
            switch issue {
            case let .insufficient(drawer, available):
                ChimpFieldMessage(text: "Not enough in \(drawer). \(available) available.", kind: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.loadPhase == .loaded, model.available <= 0, let drawer = model.selectedDrawer {
            ChimpFieldMessage(text: "No \(model.asset.code) in \(drawer.title). Pick another drawer or asset.")
        }
    }

    // MARK: C3 · Feuille « From »

    private var drawerSheetHeight: CGFloat {
        // Poignée et titre, une ligne par tiroir, bulle de Chimpy (maquette C3 : 3 tiroirs).
        CGFloat(250 + 76 * model.drawers.count)
    }

    private var drawerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where should it come from?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(model.drawers) { drawer in
                    ChimpDrawerOptionRow(
                        icon: drawer.icon,
                        title: drawer.title,
                        subtitle: model.asset.formattedWithCode(drawer.balance(of: model.asset), locale: locale),
                        isSelected: drawer.id == model.selectedDrawer?.id
                    ) {
                        model.select(drawerID: drawer.id)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)

            ChimpySays(
                text: "Main is the easy pick. Paying from a card's wallet means that exact card has to be in your hand.",
                pose: .crawl
            )
            .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    // MARK: Feuille de l'actif

    private var assetSheetHeight: CGFloat {
        CGFloat(170 + 76 * SendAsset.allCases.count)
    }

    private var assetSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you want to send?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(SendAsset.allCases) { asset in
                    ChimpOptionRow(
                        title: asset.code,
                        subtitle: assetSubtitle(asset),
                        isSelected: asset == model.asset
                    ) {
                        model.select(asset: asset)
                    } icon: {
                        ChimpAssetIcon(glyph: asset.glyph, size: 38)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    private func assetSubtitle(_ asset: SendAsset) -> String? {
        guard let drawer = model.selectedDrawer else { return nil }
        let balance = asset.formattedWithCode(drawer.balance(of: asset), locale: locale)
        return String(localized: "\(balance) in \(drawer.title)")
    }

    // MARK: Erreur

    private var failure: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.xl) {
                ChimpySays(text: "I can't reach the jungle right now, so I can't see your balances. Check your connection.", pose: .crawl)
                ChimpButton("Try again") {
                    Task { await model.load() }
                }
            }
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.top, ChimpSpacing.xl)
        }
    }
}

#Preview("Maquette") {
    let model = SendFlowModel(service: MockSendService(delay: .zero))
    model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
    return NavigationStack {
        SendAmountView(model: model)
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.loadIfNeeded() }
    }
}
