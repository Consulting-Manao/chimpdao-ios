import SwiftUI

/// E3 · Swap — « Same drawer, different coin » (maquette du 2026-10-14) : tiroir (« IN Main ▾ »), « You give » et
/// « You get » avec les soldes avant → après, ⇅, taux et puce « Slippage », pavé, « Check it over ».
/// États : devis en cours (E3a), pas de route (E3b), Soroswap indisponible (E3c), pas assez (E3d), impact au-delà de
/// 5 % (E3e, avertit sans bloquer), un envoi en attente (E3f). E3s : la feuille Slippage.
///
/// Uniquement des quantités d'actifs, jamais de dollars ; 2 décimales au plus, tronquées.
/// Retour par le drapeau du ViewModel, jamais par `@Environment(\.dismiss)` (même raison que `SendAmountView`).
struct SwapAmountView: View {
    @Bindable var model: SwapFlowModel
    let onBack: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Feuille du choix d'un actif : le côté « You give » ou « You get ».
    @State private var assetSheetSide: AssetSide?

    private enum AssetSide: Identifiable {
        case given, received
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Swap", subtitle: "Same drawer, different coin", onBack: onBack)
            switch model.loadPhase {
            case .failed: failure
            case .loading, .loaded: content
            }
        }
        .background(Color(.chimpBackground))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: model.rejectedKeyCount)
        .chimpSheet(isPresented: $model.isDrawerSheetPresented, height: CGFloat(250 + 76 * model.drawers.count)) {
            drawerSheet
        }
        .chimpSheet(isPresented: $model.isSlippageSheetPresented, height: 600, fitsContent: true) {
            slippageSheet
        }
        .chimpSheet(
            isPresented: Binding(get: { assetSheetSide != nil }, set: { if !$0 { assetSheetSide = nil } }),
            height: CGFloat(170 + 76 * SendAsset.allCases.count)
        ) {
            assetSheet
        }
        .navigationDestination(isPresented: $model.isReviewPresented) {
            SwapReviewView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Contenu

    private var content: some View {
        GeometryReader { proxy in
            let isSmallScreen = proxy.size.height < ChimpSize.compactAmountScreenHeight
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: ChimpSpacing.sm) {
                        drawerBar
                        giveCard
                        flipButton
                        getCard
                        rateLine
                        notice
                    }
                    .padding(.horizontal, ChimpSpacing.xxl)
                    .padding(.top, ChimpSpacing.ml)
                    .padding(.bottom, ChimpSpacing.s)
                    .redacted(reason: model.loadPhase == .loading ? .placeholder : [])
                }
                .scrollBounceBehavior(.basedOnSize)
                // Un avertissement qui apparaît (impact, pas de route…) reste entier au-dessus du pavé : le haut remonte.
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

    /// « IN Main ▾ » : le tiroir où le swap se fait (ce qui part et ce qui arrive y restent).
    private var drawerBar: some View {
        let drawer = model.selectedDrawer
        return Button {
            model.showDrawerSheet()
        } label: {
            HStack(spacing: ChimpSpacing.sm) {
                Text("In")
                    .textCase(.uppercase)
                    .chimpFont(.label)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpDrawerIconView(icon: drawer?.icon ?? .main, size: CGSize(width: 30, height: 20), border: 2.5, cornerRadius: 6)
                Text(verbatim: drawer.map(shortTitle) ?? String(localized: "Main"))
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                Spacer(minLength: 0)
                if model.canChooseDrawer {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.chimpTextPrimary)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurfaceSecondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .disabled(!model.canChooseDrawer)
        .accessibilityLabel(Text("In \(drawer?.title ?? String(localized: "Main account"))"))
        .accessibilityHint(Text("Choose the drawer for this swap"))
    }

    /// « Main » pour le Main account (maquette), le nom complet pour le wallet d'une carte.
    private func shortTitle(_ drawer: SendDrawer) -> String {
        if case .main = drawer.kind { return String(localized: "Main") }
        return drawer.title
    }

    private var drawerName: String {
        model.selectedDrawer.map(shortTitle) ?? String(localized: "Main")
    }

    // MARK: You give

    private var giveCard: some View {
        let isShort = model.amountIssue != nil
        return VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("You give")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
            HStack(spacing: ChimpSpacing.m) {
                ChimpTabularText.text(model.amount.displayText(locale: locale), style: .displayL, dynamicTypeSize: dynamicTypeSize)
                    .chimpFont(.displayL)
                    .foregroundStyle(isShort ? Color(.chimpNegative) : (model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: model.amount)
                    .accessibilityLabel(Text("You give"))
                    .accessibilityValue(Text(verbatim: "\(model.amount.displayText(locale: locale)) \(model.given.code)"))
                Spacer(minLength: ChimpSpacing.s)
                ChimpAssetPill(glyph: model.given.glyph, title: model.given.code) { assetSheetSide = .given }
                    .fixedSize()
                // « Max » à droite de l'actif (retour de Barth, 2026-10-14), plus sous la ligne du solde. La pastille et
                // « Max » gardent leur taille : c'est le montant qui rétrécit (`minimumScaleFactor`).
                Button("Max") { model.setMax() }
                    .chimpFont(.buttonSmall)
                    .foregroundStyle(Color(isShort ? .chimpOnAccent : .chimpTextPrimary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .cartoonSurface(Capsule(), fill: isShort ? Color(.chimpAccent) : Color(.chimpSurfaceSecondary), border: ChimpBorder.thin)
                    .buttonStyle(ChimpPressableStyle())
                    .fixedSize()
                    .disabled(model.available <= 0)
                    .accessibilityHint(Text("Swaps everything in this drawer"))
            }
            if isShort {
                Text("Only \(model.given.displayedWithCode(model.available, locale: locale)) in \(drawerName)")
                    .chimpFont(.captionStrong)
                    .foregroundStyle(Color(.chimpNegative))
            } else {
                balanceLine(before: model.givenBalanceLine.before, after: model.givenBalanceLine.after, asset: model.given, afterColor: .chimpTextPrimary)
            }
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    /// « 800 → 400 XLM in Main » (après en gras), ou le solde seul.
    private func balanceLine(before: Decimal, after: Decimal?, asset: SendAsset, afterColor: ColorResource) -> some View {
        Group {
            if let after {
                Text("\(asset.displayed(before, locale: locale)) \(Text(verbatim: "→").fontWeight(.black)) \(Text(verbatim: asset.displayed(after, locale: locale)).fontWeight(.black).foregroundStyle(Color(afterColor))) \(asset.code) in \(drawerName)")
            } else {
                Text("\(asset.displayedWithCode(before, locale: locale)) in \(drawerName)")
            }
        }
        .chimpFont(.captionStrong)
        .foregroundStyle(.chimpTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: ⇅

    private var flipButton: some View {
        Button {
            model.flipAssets()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color(.chimpOnAccent))
                .frame(width: 44, height: 44)
                .cartoonSurface(Circle(), fill: Color(.chimpAccent), shadow: ChimpShadow(x: 0, y: 3))
                .contentShape(Circle())
        }
        .buttonStyle(ChimpPressableStyle())
        // Retour de Barth (2026-10-14) : de l'air au-dessus et au-dessous de ⇅, plus collé aux deux cartes.
        .padding(.vertical, ChimpSpacing.xxs)
        .zIndex(1)
        .accessibilityLabel(Text("Swap the two coins"))
    }

    // MARK: You get

    private var getCard: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("You get")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
            HStack(spacing: ChimpSpacing.m) {
                receivedAmount
                Spacer(minLength: ChimpSpacing.s)
                ChimpAssetPill(glyph: model.received.glyph, title: model.received.code) { assetSheetSide = .received }
            }
            let line = model.receivedBalanceLine
            balanceLine(before: line.before, after: line.after, asset: model.received, afterColor: .chimpPositive)
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    /// « about 99.68 » (un devis), une barre pendant le devis, « — » sans route.
    @ViewBuilder
    private var receivedAmount: some View {
        switch model.quoteState {
        case .loading:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(.chimpSurfaceSecondary))
                    .frame(width: 96, height: 26)
                    .accessibilityLabel(Text("Getting a price"))
            }
        case .quoted:
            if let quote = model.currentQuote {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: SendAsset.displayed(quote.expectedOut, code: quote.received.code, locale: locale))
                        .chimpFont(.displayL)
                        .foregroundStyle(.chimpTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .accessibilityElement(children: .combine)
            } else {
                dash
            }
        case .idle, .failed:
            dash
        }
    }

    private var dash: some View {
        Text(verbatim: "—")
            .chimpFont(.displayL)
            .foregroundStyle(.chimpTextSecondary)
            .accessibilityLabel(Text("No amount yet"))
    }

    // MARK: Taux, slippage

    @ViewBuilder
    private var rateLine: some View {
        switch model.quoteState {
        case .loading:
            HStack {
                Text("Comparing Soroswap and Aquarius…")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                Spacer(minLength: ChimpSpacing.s)
                slippageChip
            }
        case .quoted where model.currentQuote != nil && !(model.currentQuote?.needsPriceImpactWarning ?? false):
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                HStack(spacing: ChimpSpacing.s) {
                    if let rate = model.rate, let quote = model.currentQuote {
                        Text("1 \(quote.given.code) ≈ \(rate.formatted(.number.locale(locale).precision(.fractionLength(0...4)))) \(quote.received.code) · via \(quote.protocolName)")
                            .chimpFont(.caption)
                            .foregroundStyle(.chimpTextPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: ChimpSpacing.s)
                    slippageChip
                }
                // Option A (Barth, 2026-10-14) : sous la rangée, sur toute la largeur.
                if let comparison = model.currentQuote?.comparison {
                    comparisonLine(comparison)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        default:
            EmptyView()
        }
    }

    /// Ligne discrète sous le taux : les protocoles comparés, ou celui qui ne répond pas.
    private func comparisonLine(_ comparison: SwapQuoteSummary.Comparison) -> some View {
        Group {
            switch comparison {
            case .best(let names):
                Text("Best price from \(names.formatted(.list(type: .and).locale(locale)))")
            case .fallback(let unavailable, let used):
                Text("\(unavailable.formatted(.list(type: .and).locale(locale))) \(unavailable.count > 1 ? "are" : "is") unavailable, using \(used)")
            }
        }
        .chimpFont(.caption)
        .foregroundStyle(.chimpTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var slippageChip: some View {
        Button {
            model.isSlippageSheetPresented = true
        } label: {
            HStack(spacing: 5) {
                Text("Slippage \(Self.percent(model.slippageBasisPoints, locale: locale))")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
            .chimpFont(.buttonSmall)
            .foregroundStyle(.chimpTextPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .cartoonSurface(Capsule(), fill: Color(.chimpSurface), border: ChimpBorder.thin)
            .fixedSize()
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityHint(Text("How much less than the quote you accept"))
    }

    /// « 0.5% », « 1% », « 3% ».
    static func percent(_ basisPoints: Int, locale: Locale) -> String {
        (Decimal(basisPoints) / 10_000).formatted(.percent.locale(locale).precision(.fractionLength(0...1)))
    }

    // MARK: États (E3b, E3c, E3e, E3f)

    @ViewBuilder
    private var notice: some View {
        if model.blockedByPendingPayment {
            // E3f : bandeau jaune, la vérification à la place du bouton.
            HStack(spacing: ChimpSpacing.m) {
                Circle().fill(Color(.chimpOnAccent)).frame(width: 14, height: 14)
                Text("A payment is still being checked. Check it first.")
                    .chimpFont(.bodyS)
                    .fontWeight(.black)
                    .foregroundStyle(Color(.chimpOnAccent))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpAccent), shadow: .tile)
            .accessibilityElement(children: .combine)
        } else if case .failed(let issue) = model.quoteState {
            quoteProblem(issue)
        } else if let quote = model.currentQuote, quote.needsPriceImpactWarning {
            impactWarning(quote)
        }
    }

    private func quoteProblem(_ issue: SwapFlowModel.QuoteIssue) -> some View {
        let (title, line): (LocalizedStringKey, LocalizedStringKey) = switch issue {
        case .noRoute: ("No route for this pair", "Try another coin.")
        case .protocolUnavailable(let names):
            ("\(names.formatted(.list(type: .and).locale(locale))) \(names.count > 1 ? "are" : "is") unavailable right now", "Nothing moved. Try again in a minute.")
        case .implausibleQuote: ("This price doesn't look right", "I won't show it or sign it. Nothing moved. Try again in a minute.")
        case .network: ("I can't reach the exchanges", "Check your connection. Nothing moved.")
        }
        return HStack(spacing: ChimpSpacing.m) {
            Image(.tileHead)
                .resizable()
                .scaledToFit()
                .frame(width: 30)
                .accessibilityHidden(true)
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

    /// E3e : avertissement rouge, sans bloquer (« Check it over » reste actif).
    private func impactWarning(_ quote: SwapQuoteSummary) -> some View {
        let impact = Self.percent(quote.priceImpactBasisPoints ?? 0, locale: locale)
        let rate = model.rate.map { $0.formatted(.number.locale(locale).precision(.fractionLength(0...4))) } ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            Text("Price impact \(impact) · 1 \(quote.given.code) ≈ \(rate) \(quote.received.code)")
                .chimpFont(.rowTitle)
            Text("Small pool: you get a lot less \(quote.received.code) per \(quote.given.code).")
                .chimpFont(.caption)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .padding(.horizontal, 13)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpNegative))
        .accessibilityElement(children: .combine)
    }

    // MARK: Bouton

    @ViewBuilder
    private var mainButton: some View {
        if model.blockedByPendingPayment {
            ChimpButton("Check again", isLoading: model.isCheckingPendingPayment) {
                Task { await model.checkPendingPayment() }
            }
        } else if case .failed(let issue) = model.quoteState, issue != .noRoute {
            ChimpButton("Try again") { Task { await model.refreshQuote() } }
        } else if model.quoteState == .loading {
            ChimpButton("Getting a price…") {}
                .disabled(true)
        } else if model.amountIssue != nil {
            ChimpButton("Not enough \(model.given.code)") {}
                .disabled(true)
        } else {
            ChimpButton("Check it over") { model.continueToReview() }
                .disabled(!model.canReview)
        }
    }

    // MARK: Feuilles

    private var drawerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where should it swap?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(model.drawers) { drawer in
                    ChimpDrawerOptionRow(
                        icon: drawer.icon, title: drawer.title,
                        subtitle: model.given.displayedWithCode(drawer.balance(of: model.given), locale: locale),
                        isSelected: drawer.id == model.selectedDrawer?.id
                    ) {
                        model.select(drawerID: drawer.id)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)
            ChimpySays(text: "The coins stay in the same drawer. Swapping in a card's wallet means that exact card has to be in your hand.", pose: .unsure)
                .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    /// Choix d'un actif ; choisir celui de l'autre côté échange les deux (jamais le même des deux côtés).
    private var assetSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(assetSheetSide == .received ? "What do you want to get?" : "What do you want to give?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(SendAsset.allCases) { asset in
                    let current = assetSheetSide == .received ? model.received : model.given
                    ChimpOptionRow(
                        title: asset.code,
                        subtitle: model.selectedDrawer.map { "\(asset.displayedWithCode($0.balance(of: asset), locale: locale)) in \(shortTitle($0))" },
                        isSelected: asset == current
                    ) {
                        if asset != current { model.flipAssets() }
                        assetSheetSide = nil
                    } icon: {
                        ChimpAssetIcon(glyph: asset.glyph, size: 38)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    /// E3s · Slippage : trois choix, une phrase simple, pas de saisie libre.
    private var slippageSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slippage")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Prices wiggle while your swap travels. Slippage is how much less than the quote you're OK getting. If it would slip more, the swap stops and your \(model.given.code) stays put.")
                .chimpFont(.bodyL)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ChimpSpacing.s)
            VStack(spacing: ChimpSpacing.sm) {
                ForEach(SwapFlowModel.slippageOptions, id: \.self) { option in
                    slippageOption(option)
                }
            }
            .padding(.top, ChimpSpacing.l)
            ChimpySays(text: "0.5% is right almost every time. Go higher only if swaps keep stopping.", pose: .teacher)
                .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    private func slippageOption(_ basisPoints: Int) -> some View {
        let isSelected = basisPoints == model.slippageBasisPoints
        let (title, ink): (LocalizedStringKey, Color) = switch basisPoints {
        case 50: ("Default", Color(.chimpOnAccent))
        case 100: ("A bit more room", Color(.chimpTextPrimary))
        default: ("Lots of room", Color(.chimpTextPrimary))
        }
        return Button {
            model.setSlippage(basisPoints)
        } label: {
            HStack(spacing: ChimpSpacing.m) {
                Text(verbatim: Self.percent(basisPoints, locale: locale))
                    .chimpFont(.greeting)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).chimpFont(.rowTitle)
                    if let minimum = model.minimum(atSlippage: basisPoints) {
                        Text("You get at least \(model.received.displayedWithCode(minimum, locale: locale))")
                            .chimpFont(.captionStrong)
                            .opacity(isSelected ? 1 : 0.75)
                    }
                }
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular)
                    .background { if isSelected { Circle().fill(Color(.chimpOutline)).padding(5) } }
                    .frame(width: 24, height: 24)
            }
            .foregroundStyle(isSelected ? Color(.chimpOnAccent) : ink)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .cartoonSurface(
                RoundedRectangle(cornerRadius: ChimpRadius.control),
                fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface),
                shadow: isSelected ? .tile : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Erreur

    private var failure: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.xl) {
                ChimpySays(text: "I can't reach the jungle right now, so I can't see your balances. Check your connection.", pose: .crawl)
                ChimpButton("Try again") { Task { await model.load() } }
            }
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.top, ChimpSpacing.xl)
        }
    }
}
