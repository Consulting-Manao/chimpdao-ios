import SwiftUI

/// « Add money » (tranche 2, D4 ; construit sans maquette avec le design system, décision de Barth du 2026-10-15) : pour
/// l'instant une seule voie, « From another chain » (devis NEAR Intents, N1). Ouvert depuis le Wallet et depuis Recevoir.
struct AddMoneyView: View {
    let onBack: () -> Void
    let onCrossChain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Add money", subtitle: "Into your wallet", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpNavigationRow(title: "From another chain", subtitle: "See a live price from NEAR Intents", action: onCrossChain)
                    ChimpySays(text: "To get money from someone on Stellar, share your address from Receive.", pose: .teacher)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.chimpBackground))
    }
}

/// N1 · « From another chain » : chaîne et jeton d'origine, montant, devis à blanc de NEAR Intents, la limite (texte validé
/// par Barth le 2026-10-15), aucun bouton d'envoi. Quantités seulement, jamais de dollars.
struct CrossChainQuoteView: View {
    @Bindable var model: CrossChainQuoteModel
    let onBack: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isSmallScreen: Bool { screenInsets.top < 30 }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "From another chain", subtitle: "Live price from NEAR Intents", onBack: onBack)
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                failure
            case .loaded:
                content
            }
        }
        .background(Color(.chimpBackground))
        .task { if model.tokens.isEmpty { await model.load() } }
        .sensoryFeedback(.error, trigger: model.rejectedKeyCount)
        .chimpSheet(isPresented: $model.isChainSheetPresented, height: 640) { chainSheet }
        .chimpSheet(isPresented: $model.isTokenSheetPresented, height: CGFloat(170 + 76 * max(1, model.tokens(on: model.chain).count))) { tokenSheet }
    }

    // MARK: Contenu

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                    limit
                    chainBar
                    sendCard
                    getCard
                    quoteDetails
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            if !dynamicTypeSize.isAccessibilitySize {
                ChimpKeypad(mode: .amount, isCompact: isSmallScreen) { key in
                    ChimpSoundPlayer.shared.play(.tap)
                    model.press(key)
                }
                .padding(.horizontal, ChimpSpacing.lg)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
            }
        }
    }

    /// La limite, en clair, en haut de l'écran : rien ne peut partir vers une carte.
    private var limit: some View {
        ChimpNoticeBanner(
            text: "Card addresses aren't accepted by NEAR Intents yet, and it has no testnet. This shows a live price only; nothing can be sent to your card this way.",
            marker: .error
        )
    }

    /// « FROM Ethereum ▾ ».
    private var chainBar: some View {
        Button { model.isChainSheetPresented = true } label: {
            HStack(spacing: ChimpSpacing.sm) {
                Text("From").textCase(.uppercase).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
                Text(verbatim: CrossChainQuoteModel.chainName(model.chain)).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .black)).foregroundStyle(.chimpTextPrimary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, ChimpSpacing.l)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurfaceSecondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityLabel(Text("From \(CrossChainQuoteModel.chainName(model.chain))"))
        .accessibilityHint(Text("Choose the chain"))
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("You'd send").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            HStack(spacing: ChimpSpacing.m) {
                ChimpTabularText.text(model.amount.displayText(locale: locale), style: .displayL, dynamicTypeSize: dynamicTypeSize)
                    .chimpFont(.displayL)
                    .foregroundStyle(model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(Text("You'd send"))
                    .accessibilityValue(Text(verbatim: "\(model.amount.displayText(locale: locale)) \(model.origin?.symbol ?? "")"))
                Spacer(minLength: ChimpSpacing.s)
                tokenPill(model.origin?.symbol ?? "—") { model.isTokenSheetPresented = true }
            }
            Text("on \(CrossChainQuoteModel.chainName(model.chain))").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    /// « On Stellar you'd get about 54.11 XLM » ; XLM ou USDC à l'arrivée.
    private var getCard: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("On Stellar you'd get").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            HStack(spacing: ChimpSpacing.m) {
                Group {
                    switch model.quoteState {
                    case .quoted(let quote):
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("about").chimpFont(.rowTitle).foregroundStyle(.chimpTextSecondary)
                            Text(verbatim: model.destination.displayed(quote.amountOut, locale: locale)).chimpFont(.displayL)
                        }
                    case .loading:
                        ProgressView()
                    default:
                        Text(verbatim: "—").chimpFont(.displayL).foregroundStyle(.chimpTextSecondary)
                    }
                }
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                Spacer(minLength: ChimpSpacing.s)
                HStack(spacing: 6) {
                    ForEach([SendAsset.xlm, .usdc]) { asset in
                        ChimpChoiceChip(verbatim: asset.code, isSelected: model.destination == asset) {
                            model.selectDestination(asset)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var quoteDetails: some View {
        switch model.quoteState {
        case .quoted(let quote):
            VStack(alignment: .leading, spacing: 4) {
                Text("At least \(model.destination.displayedWithCode(quote.minimumOut, locale: locale)) · takes about \(Self.duration(quote.timeEstimate))")
                    .chimpFont(.captionStrong)
                    .foregroundStyle(.chimpTextPrimary)
                Text("Price from NEAR Intents, \(SavingsText.age(of: quote.quotedAt)) · fees included · mainnet")
                    .chimpFont(.mono)
                    .foregroundStyle(.chimpTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .failed(let issue):
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                ChimpFieldMessage(text: Self.message(for: issue), kind: .error)
                if issue == .unavailable {
                    ChimpPillButton("Retry") { Task { await model.refreshQuote() } }
                }
                if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
            }
        case .idle:
            Text("Type an amount to see a price.").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
        case .loading:
            EmptyView()
        }
    }

    /// Le refus « pas de prix » vient de NEAR Intents pour toutes les paires vers Stellar (constaté le 2026-10-16) : on ne
    /// suggère donc pas d'essayer une autre chaîne.
    static func message(for issue: CrossChainQuoteModel.QuoteIssue) -> LocalizedStringKey {
        switch issue {
        case .pairUnavailable: "NEAR Intents has no price to Stellar right now. Try again later."
        case .amountTooLow: "That's too little for NEAR Intents to price. Try a bigger amount."
        case .unavailable: "NEAR Intents isn't answering right now."
        }
    }

    /// « 50 s », « 3 min ».
    static func duration(_ seconds: Int) -> String {
        seconds < 90 ? String(localized: "\(seconds) s") : String(localized: "\(Int((Double(seconds) / 60).rounded())) min")
    }

    private func tokenPill(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.s) {
                Text(verbatim: String(symbol.prefix(1)))
                    .chimpFont(.rowTitle)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(.chimpSurfaceSecondary)))
                    .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                Text(verbatim: symbol).chimpFont(.pill)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .black)).accessibilityHidden(true)
            }
            .foregroundStyle(.chimpTextPrimary)
            .padding(.vertical, ChimpSpacing.xs + ChimpBorder.regular)
            .padding(.horizontal, 13 + ChimpBorder.regular)
            .cartoonSurface(Capsule(), fill: Color(.chimpSurface))
            .contentShape(Rectangle().inset(by: -ChimpSpacing.xs))
        }
        .buttonStyle(ChimpPressableStyle())
        .fixedSize()
        .accessibilityHint(Text("Choose the coin"))
    }

    // MARK: Erreur

    private var failure: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.l) {
            limit
            ChimpySays(text: "I can't reach NEAR Intents right now. Check your connection.", pose: .crawl)
            ChimpButton("Try again") { Task { await model.load() } }
            if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
            Spacer()
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.top, ChimpSpacing.l)
    }

    // MARK: Feuilles

    private var chainSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Which chain is it on?").chimpFont(.sheetTitle).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: ChimpSpacing.listGap) {
                    ForEach(model.chains, id: \.self) { chain in
                        ChimpOptionRow(title: CrossChainQuoteModel.chainName(chain), subtitle: nil, isSelected: chain == model.chain) {
                            model.selectChain(chain)
                        } icon: {
                            EmptyView()
                        }
                    }
                }
                .padding(.vertical, ChimpSpacing.l)
            }
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    private var tokenSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Which coin?").chimpFont(.sheetTitle).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: ChimpSpacing.listGap) {
                    ForEach(model.tokens(on: model.chain)) { token in
                        ChimpOptionRow(
                            title: token.symbol, subtitle: String(localized: "on \(CrossChainQuoteModel.chainName(token.blockchain))"),
                            isSelected: token == model.origin
                        ) {
                            model.selectOrigin(token)
                        } icon: {
                            EmptyView()
                        }
                    }
                }
                .padding(.vertical, ChimpSpacing.l)
            }
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }
}
