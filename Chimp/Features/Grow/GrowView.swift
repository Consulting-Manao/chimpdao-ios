import SwiftUI

/// Où l'onglet Grow emmène.
enum GrowRoute: Hashable {
    /// F3 · mettre, depuis un tiroir (ou le premier).
    case deposit(drawerID: String?)
    /// F7 · retirer, vers le tiroir qui détient la position.
    case withdraw(drawerID: String)
    /// Swap prérempli depuis G1 ou G2 (« Get some », « Get more », « Swap back ») : la paire seule, montant vide.
    case swap(SwapPrefill)
    /// G2 · la page d'un pot (protocole, adresse du tiroir).
    case pot(ChimpPotProtocol, drawerAddress: String)
    /// Prêt XOXNO (phase 7) : mettre, retirer.
    case lendingDeposit(drawerID: String?)
    case lendingWithdraw(drawerID: String)
    /// Vault Sentora (2026-11-05) : mettre, retirer.
    case sentoraDeposit(drawerID: String?)
    case sentoraWithdraw(drawerID: String)
    /// Vault xSolvBTC de Solv (2026-11-05) : mettre (on sort par un swap).
    case solvDeposit(drawerID: String?)
}

/// G1 · Grow (maquette « Chimp Grow Final », Claude Design, 2026-10-18) : en-tête vert « Grow », ce qui a poussé en tout
/// (en dollars, jamais partiel), Chimpy qui jardine ; pastilles des tiroirs ; une carte par pot ; « Plant something else »
/// pour les protocoles pas encore plantés dans ce tiroir. Seule la croissance réelle est montrée, jamais un taux.
struct GrowView: View {
    let model: GrowModel
    /// L'œil (le même que celui du Wallet) : affiché dans l'en-tête seulement si une action est fournie.
    var onToggleAmounts: (() -> Void)? = nil
    let onOpen: (GrowRoute) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpHidesAmounts) private var hidesAmounts
    @Environment(\.chimpScreenInsets) private var screenInsets
    /// Le tiroir choisi ; `nil` = « All drawers ».
    @State private var selectedDrawerID: String?
    @State private var plantChoice: PlantChoice?

    /// Les protocoles à proposer dans un tiroir (feuille « Plant something else »).
    struct PlantChoice: Identifiable {
        let drawer: SendDrawer?
        let marks: [ChimpPotProtocol]
        var id: String { (drawer?.id ?? "all") + marks.map(\.rawValue).joined() }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GrowHeader(total: total, onToggleAmounts: onToggleAmounts)
                    pills
                    content
                        .padding(.horizontal, ChimpSpacing.xxl)
                        .padding(.top, 14)
                    Spacer(minLength: ChimpSpacing.l)
                    // Le pied de page reste en bas de l'écran (maquette : « margin-top: auto »).
                    ChimpGrowFinePrint()
                        .padding(.horizontal, ChimpSpacing.xxl)
                        .padding(.bottom, ChimpSpacing.m)
                }
                .frame(minHeight: proxy.size.height + proxy.safeAreaInsets.top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            .refreshable {
                ChimpSoundPlayer.shared.play(.branch)
                await model.refresh()
            }
        }
        .background(Color(.chimpBackground))
        .task { await model.refresh() }
        .chimpSheet(
            isPresented: Binding(get: { plantChoice != nil }, set: { if !$0 { plantChoice = nil } }),
            height: CGFloat(200 + 84 * (plantChoice?.marks.count ?? 1))
        ) {
            if let plantChoice { plantSheet(plantChoice) }
        }
    }

    private var pots: [GrowPot] { model.pots }
    private var drawers: [SendDrawer] { model.potDrawers }
    private var total: Decimal? { pots.isEmpty ? nil : GrowPots.totalUSD(pots, xlmUSD: model.xlmUSD, btcUSD: model.btcUSD) }

    // MARK: Pastilles

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChimpDrawerPill(title: String(localized: "All drawers"), isSelected: selectedDrawerID == nil) { selectedDrawerID = nil }
                ForEach(drawers) { drawer in
                    ChimpDrawerPill(title: Self.pillTitle(drawer), isSelected: selectedDrawerID == drawer.id) { selectedDrawerID = drawer.id }
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.vertical, 2)
        }
        .padding(.top, 14)
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 11) {
            problems
            if isLoadingFirst {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, ChimpSpacing.xl)
            } else if let drawer = drawers.first(where: { $0.id == selectedDrawerID }) {
                drawerSection(drawer, compact: false, alwaysShow: true)
            } else if pots.isEmpty {
                Text("Nothing growing yet.").chimpFont(.bodyS).foregroundStyle(.chimpTextSecondary).padding(.horizontal, 2)
                if !model.plantable.isEmpty {
                    plantSomethingElse(drawer: nil, marks: model.plantable)
                }
            } else {
                ForEach(drawers) { drawer in
                    if pots.contains(where: { $0.drawerID == drawer.id }) {
                        drawerSection(drawer, compact: true, alwaysShow: false)
                    }
                }
            }
        }
    }

    private var isLoadingFirst: Bool {
        pots.isEmpty && (model.phase == .loading || model.savingsPhase == .loading || model.lending?.phase == .loading || model.sentora?.phase == .loading
            || model.solv?.phase == .loading)
            && drawers.isEmpty
    }

    /// Un protocole qui ne répond pas : une ligne, avec « Retry ».
    @ViewBuilder
    private var problems: some View {
        let silent: [String] = [
            model.phase == .unavailable ? "DeFindex" : nil,
            model.lending?.phase == .unavailable ? "XOXNO" : nil,
            model.sentora?.phase == .unavailable ? "Sentora" : nil,
            model.solv?.phase == .unavailable ? "Solv" : nil,
            model.savingsService != nil && model.savingsPhase == .unavailable
                ? model.savingsService?.marks.map(\.name).joined(separator: ", ") : nil,
        ].compactMap { $0 }
        if !silent.isEmpty {
            ChimpNoticeBanner(text: "\(silent.joined(separator: ", ")) isn't answering right now. Showing what I know.", marker: .error) {
                ChimpPillButton("Retry") { Task { await model.refresh() } }
            }
        }
    }

    @ViewBuilder
    private func drawerSection(_ drawer: SendDrawer, compact: Bool, alwaysShow: Bool) -> some View {
        let mine = pots.filter { $0.drawerID == drawer.id }
        if !mine.isEmpty {
            Text(verbatim: drawerLabel(drawer, pots: mine))
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            ForEach(mine) { pot in
                Button { onOpen(.pot(pot.mark, drawerAddress: pot.drawerAddress)) } label: { card(pot, compact: compact) }
                    .buttonStyle(ChimpPressableStyle())
            }
        } else if alwaysShow {
            Text("Nothing growing in \(Self.pillTitle(drawer)) yet.").chimpFont(.bodyS).foregroundStyle(.chimpTextSecondary).padding(.horizontal, 2)
        }
        if alwaysShow {
            let missing = model.plantable.filter { mark in !mine.contains { $0.mark == mark } }
            if !missing.isEmpty { plantSomethingElse(drawer: drawer, marks: missing) }
        }
    }

    /// « MAIN · +$1.48 » (le total du tiroir seulement s'il est connu en entier).
    private func drawerLabel(_ drawer: SendDrawer, pots: [GrowPot]) -> String {
        let name = Self.pillTitle(drawer)
        guard let total = GrowPots.totalUSD(pots, xlmUSD: model.xlmUSD, btcUSD: model.btcUSD) else { return name }
        return "\(name) · \(ChimpPrivacy.amount(Self.dollars(total, locale: locale), hidden: hidesAmounts))"
    }

    private func card(_ pot: GrowPot, compact: Bool) -> some View {
        ChimpPotCard(mark: pot.mark, subtitle: Self.subtitle(pot), compact: compact) {
            if let value = pot.value {
                // Le CETES montre l'évolution de son prix en pourcentage : pas un montant, toujours visible.
                ChimpPotAmount(
                    amount: Self.amount(value, pot: pot, locale: locale), chip: Self.chip(pot, locale: locale), isNegative: Self.isNegative(pot),
                    chipIsAmount: !pot.mark.tracksPrice
                )
            }
        }
    }

    private func plantSomethingElse(drawer: SendDrawer?, marks: [ChimpPotProtocol]) -> some View {
        Button { plant(drawer: drawer, marks: marks) } label: { ChimpPlantSomethingElse(marks: marks) }
            .buttonStyle(ChimpPressableStyle())
    }

    private func plant(drawer: SendDrawer?, marks: [ChimpPotProtocol]) {
        if marks.count == 1, let mark = marks.first {
            plantChoice = nil
            onOpen(Self.plantRoute(mark, drawer: drawer, fallbackAddress: drawers.first?.address))
        } else {
            plantChoice = PlantChoice(drawer: drawer, marks: marks)
        }
    }

    private func plantSheet(_ choice: PlantChoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you want to plant?").chimpFont(.sheetTitle).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(choice.marks) { mark in
                    Button { plant(drawer: choice.drawer, marks: [mark]) } label: {
                        ChimpPotCard(mark: mark, subtitle: Self.grows(mark), compact: true) {
                            Image(systemName: "chevron.right").fontWeight(.black).foregroundStyle(.chimpTextSecondary)
                        }
                    }
                    .buttonStyle(ChimpPressableStyle())
                }
            }
            .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    /// Où mène « planter » un protocole : le dépôt du vault ou du prêt, ou le swap USDC → CETES (ou USDY).
    static func plantRoute(_ mark: ChimpPotProtocol, drawer: SendDrawer?, fallbackAddress: String?) -> GrowRoute {
        switch mark {
        case .defindex: .deposit(drawerID: drawer?.id)
        case .xoxno: .lendingDeposit(drawerID: drawer?.id)
        case .sentora: .sentoraDeposit(drawerID: drawer?.id)
        case .solv: .solvDeposit(drawerID: drawer?.id)
        case .etherfuse: .swap(SwapPrefill(drawerAddress: drawer?.address ?? fallbackAddress ?? "", given: .usdc, received: .cetes, amount: nil))
        case .ondo: .swap(SwapPrefill(drawerAddress: drawer?.address ?? fallbackAddress ?? "", given: .usdc, received: .usdy, amount: nil))
        }
    }

    // MARK: Textes partagés

    /// « Grows XLM », « Grows USDC », « CETES · Mexican bonds ».
    static func grows(_ mark: ChimpPotProtocol) -> String {
        switch mark {
        case .defindex: String(localized: "Grows XLM")
        case .xoxno: String(localized: "Grows USDC")
        case .sentora: String(localized: "USDC · rewards each term")
        case .solv: String(localized: "SolvBTC · Bitcoin yield")
        case .etherfuse: String(localized: "CETES · Mexican bonds")
        case .ondo: String(localized: "USDY · US Treasuries")
        }
    }

    static func subtitle(_ pot: GrowPot) -> String {
        switch pot.state {
        case .needsRenewal: return String(localized: "Needs renewal · your money is still there")
        case .hasDebt: return String(localized: "Has a loan · can't be moved here")
        case .frozen: return String(localized: "Frozen by \(pot.asset.issuerName ?? pot.mark.name)")
        case .growing:
            return pot.positions > 1 ? "\(grows(pot.mark)) · " + String(localized: "\(pot.positions) positions") : grows(pot.mark)
        }
    }

    /// DeFindex : « 50.12 XLM » ; XOXNO et Etherfuse : le nombre seul, « 1,820.40 » (maquette).
    static func amount(_ value: Decimal, pot: GrowPot, locale: Locale) -> String {
        let number = twoDecimals(value, locale: locale)
        return pot.mark == .defindex ? "\(number) \(pot.asset.code)" : number
    }

    /// Deux décimales, séparateur de milliers, tronqué (jamais arrondi vers le haut).
    static func twoDecimals(_ value: Decimal, locale: Locale) -> String {
        var source = value
        var truncated = Decimal()
        NSDecimalRound(&truncated, &source, 2, .down)
        // L'espace fine des milliers (français) n'existe pas dans Luckiest Guy : une espace normale à la place.
        return NSDecimalNumber(decimal: truncated).doubleValue.formatted(.number.precision(.fractionLength(2)).grouping(.automatic).locale(locale))
            .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// La pastille d'un tiroir : « Main », ou le nom de la carte (« Jungle »).
    static func pillTitle(_ drawer: SendDrawer) -> String {
        if case .card(let name, _) = drawer.kind { return name }
        return shortTitle(drawer)
    }

    /// « +0.12 XLM », « −0.03 USDC », « Price +0.62% » ; `nil` sans base.
    static func chip(_ pot: GrowPot, locale: Locale) -> String? {
        if pot.mark.tracksPrice {
            return pot.priceChange.map { String(localized: "Price \(percent($0, locale: locale))") }
        }
        return pot.growth.map { changeText($0, asset: pot.asset, locale: locale) }
    }

    static func isNegative(_ pot: GrowPot) -> Bool {
        (pot.mark.tracksPrice ? pot.priceChange : pot.growth).map { $0 < 0 } ?? false
    }

    /// « +0.62% », « −0.10% ».
    static func percent(_ fraction: Decimal, locale: Locale) -> String {
        let value = NSDecimalNumber(decimal: abs(fraction) * 100).doubleValue
        let sign = fraction > 0 ? "+" : (fraction < 0 ? "\u{2212}" : "")
        return sign + value.formatted(.number.precision(.fractionLength(2)).locale(locale)) + "%"
    }

    /// « +$1.51 », « −$0.20 » (tronqué au centime).
    static func dollars(_ amount: Decimal, locale: Locale) -> String {
        var value = abs(amount)
        var cents = Decimal()
        NSDecimalRound(&cents, &value, 2, .down)
        let sign = amount > 0 ? "+" : (amount < 0 ? "\u{2212}" : "")
        return sign + "$" + NSDecimalNumber(decimal: cents).doubleValue.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func shortTitle(_ drawer: SendDrawer) -> String {
        if case .main = drawer.kind { return String(localized: "Main") }
        return drawer.title
    }

    /// « +0.12 XLM », « −0.03 XLM », « 0 XLM » : l'évolution réelle, en quantité (2 décimales, tronquée).
    static func changeText(_ change: Decimal, asset: SendAsset, locale: Locale) -> String {
        let sign = change > 0 ? "+" : (change < 0 ? "\u{2212}" : "")
        return sign + asset.displayedWithCode(abs(change), locale: locale)
    }
}

/// G1 · l'en-tête vert : « Grow », ce qui a poussé en tout (en dollars, seulement s'il est connu en entier), Chimpy qui
/// jardine (il se balance doucement, sauf si « Réduire les animations » est activé).
struct GrowHeader: View {
    let total: Decimal?
    var onToggleAmounts: (() -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.chimpHidesAmounts) private var hidesAmounts
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Grow")
                    .chimpFont(.growTitle)
                    .foregroundStyle(Color(.chimpTicketPaper))
                    .shadow(color: Color(.chimpGrowShade), radius: 0, x: 0, y: 3)
                    .accessibilityAddTraits(.isHeader)
                if let total {
                    Text(verbatim: ChimpPrivacy.amount(GrowView.dollars(total, locale: locale), hidden: hidesAmounts))
                        .chimpFont(.growTotal)
                        .foregroundStyle(total < 0 ? Color(.chimpNegative) : Color(.chimpTicketPaper))
                        .shadow(color: Color(.chimpGrowShade), radius: 0, x: 0, y: 4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.top, 8)
                    Text("grown in total").chimpFont(.rowTitle).foregroundStyle(Color(.chimpTicketInk)).padding(.top, 6)
                } else {
                    Text("What your coins really did. No promised rates.")
                        .chimpFont(.rowTitle)
                        .foregroundStyle(Color(.chimpTicketInk))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
            .padding(.trailing, 130)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(.chimpyPlantHero)
                .resizable()
                .scaledToFit()
                .frame(width: 128)
                .padding(.trailing, 6)
                .padding(.bottom, 10)
                .chimpBob(duration: 5)
                .accessibilityHidden(true)
        }
        .padding(.top, screenInsets.top + 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .background {
            Color(.chimpCardLeaf).overlay { ChimpPattern(opacity: 0.14) }
        }
        .clipped()
        .accessibilityElement(children: .combine)
        // Hors du bloc lu d'un coup par VoiceOver : le bouton reste atteignable.
        .overlay(alignment: .topTrailing) {
            if let onToggleAmounts, total != nil {
                ChimpAmountsEyeButton(isHiding: hidesAmounts, color: Color(.chimpTicketPaper), action: onToggleAmounts)
                    .padding(.top, screenInsets.top + 12)
                    .padding(.trailing, 20)
            }
        }
    }
}
