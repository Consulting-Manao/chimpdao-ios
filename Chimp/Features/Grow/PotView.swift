import SwiftUI

/// G2 · la page d'un pot (maquette « Chimp Grow Final », 2026-10-18) : en-tête vert (nom, actif et tiroir, « ? »), la
/// courbe des valeurs réellement relevées sur ce téléphone, le ticket (ce qu'on a, ce qui a vraiment poussé, les faits
/// utiles), une ligne de Chimpy, « Add » / « Take out » (Etherfuse : « Get more » / « Swap back »).
/// Décision de Barth du 2026-10-18 : ni les risques ni les protocoles sous-jacents sur ces écrans.
struct PotView: View {
    let model: GrowModel
    let mark: ChimpPotProtocol
    let drawerAddress: String
    let onBack: () -> Void
    /// Mettre, puis retirer, depuis ce tiroir (identifiant du tiroir).
    let onAdd: (String) -> Void
    let onTakeOut: (String) -> Void
    /// Etherfuse : le swap prérempli (la paire seule, montant vide).
    let onSwap: (SwapPrefill) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.chimpHidesAmounts) private var hidesAmounts
    @State private var isShowingInfo = false

    private var pot: GrowPot? { model.pot(mark, drawerAddress: drawerAddress) }
    private var drawer: SendDrawer? { model.potDrawers.first { $0.address == drawerAddress } }
    private var drawerName: String { drawer.map { GrowView.shortTitle($0) } ?? String(localized: "Main") }
    private var assetCode: String { pot?.asset.code ?? PotText.assetCode(mark) }

    /// La lecture du service de ce protocole.
    private var phase: GrowModel.Phase {
        switch mark {
        case .defindex: model.phase
        case .xoxno: model.lending?.phase ?? .unavailable
        case .sentora: model.sentora?.phase ?? .unavailable
        case .etherfuse, .ondo: model.savingsPhase
        }
    }

    private var place: VaultInfo? {
        switch mark {
        case .defindex: model.vault
        case .xoxno: model.lending?.vault
        case .sentora: model.sentora?.vault
        case .etherfuse, .ondo: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    if let pot {
                        receipt(pot)
                        if pot.state == .frozen, let savings = model.savings(mark) {
                            SavingsFrozenBanner(asset: savings.asset, drawerName: drawerName).padding(.top, 14)
                        }
                        ChimpySays(text: "\(PotText.chimpyLine(pot, locale: locale))", pose: .plant)
                            .padding(.top, 14)
                    } else if phase == .unavailable {
                        ChimpNoticeBanner(text: "\(PotText.unanswered(mark))", marker: .error) {
                            ChimpPillButton("Retry") { Task { await model.refresh() } }
                        }
                        .padding(.top, ChimpSpacing.l)
                    } else if phase == .loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, ChimpSpacing.xl)
                    } else {
                        ChimpySays(text: "Nothing growing here anymore.", pose: .plant).padding(.top, ChimpSpacing.l)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, -6)
                .padding(.bottom, ChimpSpacing.l)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await model.refresh() }
        .ignoresSafeArea(edges: .top)
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .task { await model.refresh() }
        .chimpSheet(isPresented: $isShowingInfo, fitsContent: true) { info }
    }

    // MARK: En-tête et courbe

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ChimpHeaderBackButton(action: onBack)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: mark.name).chimpFont(.displayM).foregroundStyle(Color(.chimpTicketInk)).accessibilityAddTraits(.isHeader)
                    Text(verbatim: PotText.subtitle(assetCode, drawerName: drawerName))
                        .chimpFont(.captionStrong)
                        .foregroundStyle(Color(.chimpTicketInk))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { isShowingInfo = true } label: {
                    Text(verbatim: "?")
                        .chimpFont(.potName)
                        .foregroundStyle(Color(.chimpTicketInk))
                        .padding(.top, 3)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.chimpAccent)))
                        .background(Circle().fill(Color(.chimpTicketInk)).offset(x: 2, y: 3))
                        .overlay { Circle().strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityLabel(Text("What is \(mark.name)?"))
            }
            .padding(.horizontal, 20)
            ChimpGrowCurve(values: curve, startLabel: PotText.startLabel(pot?.since, locale: locale), mark: mark)
                .frame(height: 166)
                .padding(.top, 12)
        }
        .padding(.top, screenInsets.top + 4)
        .background {
            Color(.chimpCardLeaf).overlay { ChimpPattern(opacity: 0.14) }
        }
        .clipped()
    }

    private var curve: [Double] {
        guard let pot else { return [0, 0] }
        return PotHistory.series(of: pot, readings: model.readings(of: pot))
    }

    // MARK: Ticket

    private func receipt(_ pot: GrowPot) -> some View {
        ChimpPaperReceipt {
            VStack(alignment: .leading, spacing: 0) {
                Text("You have").textCase(.uppercase).chimpFont(.label).foregroundStyle(Color(.chimpTicketMuted))
                if let value = pot.value {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: ChimpPrivacy.amount(GrowView.twoDecimals(value, locale: locale), hidden: hidesAmounts))
                            .chimpFont(.receiptBig)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(verbatim: pot.asset.code).chimpFont(.receiptUnit).foregroundStyle(Color(.chimpTicketMuted))
                    }
                    .padding(.top, 4)
                    if let line = PotText.sinceLine(pot, locale: locale) {
                        Text(verbatim: ChimpPrivacy.amount(line, hidden: hidesAmounts))
                            .chimpFont(.rowTitle)
                            .foregroundStyle(GrowView.isNegative(pot) ? Color(.chimpNegative) : Color(.chimpPositive))
                            .padding(.top, 6)
                    }
                } else {
                    Text(pot.state == .hasDebt ? LendingText.hasDebt : LendingText.needsRenewal)
                        .chimpFont(.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                ChimpReceiptRule().padding(.vertical, 14)
                rows(pot)
                ChimpReceiptRule().padding(.vertical, 14)
                HStack {
                    Text(verbatim: PotText.footer(mark, drawerName: drawerName))
                        .chimpFont(.potFooter)
                        .foregroundStyle(Color(.chimpTicketMuted))
                    Spacer(minLength: 8)
                    let stamp = PotText.stamp(pot, network: model.savings(mark)?.network)
                    ChimpPotStamp(text: "\(stamp.text)", color: stamp.positive ? Color(.chimpPositive) : Color(.chimpNegative))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func rows(_ pot: GrowPot) -> some View {
        if mark.tracksPrice {
            let price = model.savings(mark)?.price.price
            if let price, let value = pot.value {
                ChimpReceiptRow(label: "Worth about", value: SendAsset.usdc.displayedWithCode(price.value(of: value), locale: locale), isAmount: true)
            }
            if let price {
                ChimpReceiptRow(label: "1 \(pot.asset.code)", value: PotText.unitPrice(price.usd, locale: locale))
            }
            ChimpReceiptRow(label: "Price", value: PotText.priceSource(price))
        } else {
            if let putIn = pot.putIn {
                ChimpReceiptRow(label: "Put in", value: PotText.putIn(putIn, since: pot.since, asset: pot.asset, locale: locale), isAmount: true)
            }
            if let week = PotHistory.thisWeek(of: pot, readings: model.readings(of: pot)) {
                ChimpReceiptRow(
                    label: "This week", value: GrowView.changeText(week, asset: pot.asset, locale: locale),
                    tone: week < 0 ? .negative : (week > 0 ? .positive : .plain), isAmount: true
                )
            }
            if let days = PotHistory.days(since: pot.since) {
                ChimpReceiptRow(label: "Growing for", value: PotText.days(days))
            }
            if pot.positions > 1 {
                ChimpReceiptRow(label: "Positions", value: "\(pot.positions)")
            }
        }
    }

    // MARK: Boutons

    private var buttons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if mark.tracksPrice {
                    let asset = pot?.asset ?? model.savings(mark)?.asset ?? .cetes
                    ChimpButton(pot?.value ?? 0 > 0 ? "Get more" : "Get some") {
                        onSwap(SwapPrefill(drawerAddress: drawerAddress, given: .usdc, received: asset, amount: nil))
                    }
                    .disabled(model.savings(mark) == nil || pot?.state == .frozen)
                    ChimpButton("Swap back", kind: .secondary, raised: true) {
                        onSwap(SwapPrefill(drawerAddress: drawerAddress, given: asset, received: .usdc, amount: nil))
                    }
                    .disabled((pot?.value ?? 0) <= 0 || pot?.state == .frozen)
                } else {
                    ChimpButton("Add") { if let drawer { onAdd(drawer.id) } }
                        .disabled(place == nil || drawer == nil || place?.depositsBlocked == true)
                    ChimpButton("Take out", kind: .secondary, raised: true) { if let pot { onTakeOut(pot.drawerID) } }
                        .disabled(pot?.canMove != true || place?.withdrawalsBlocked == true)
                }
            }
            ChimpGrowFinePrint()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
        .background(Color(.chimpBackground))
    }

    // MARK: « ? »

    private var info: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            HStack(spacing: ChimpSpacing.m) {
                ChimpProtocolLogo(mark: mark, size: 48)
                Text(verbatim: mark.name).chimpFont(.sheetTitle).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            }
            Text("\(PotText.info(mark))")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(PotText.infoHonesty(mark))")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChimpButton("Got it") { isShowingInfo = false }
                .padding(.top, ChimpSpacing.s)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.bottom, ChimpSpacing.l)
    }
}

/// Les textes de G2 (testés à part).
enum PotText {
    static func assetCode(_ mark: ChimpPotProtocol) -> String {
        switch mark {
        case .defindex: "XLM"
        case .xoxno, .sentora: "USDC"
        case .etherfuse: "CETES"
        case .ondo: "USDY"
        }
    }

    /// « XLM · in Main ».
    static func subtitle(_ code: String, drawerName: String) -> String {
        String(localized: "\(code) · in \(drawerName)")
    }

    /// « DEFINDEX · IN MAIN ».
    static func footer(_ mark: ChimpPotProtocol, drawerName: String) -> String {
        String(localized: "\(mark.name) · in \(drawerName)").uppercased()
    }

    /// « 22 SEP » : le jour du premier dépôt, au départ de la courbe ; rien sans date.
    static func startLabel(_ since: Date?, locale: Locale) -> String {
        since.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(locale)).uppercased() } ?? ""
    }

    /// « 50 XLM · 22 SEP ».
    static func putIn(_ amount: Decimal, since: Date?, asset: SendAsset, locale: Locale) -> String {
        let value = asset.displayedWithCode(amount, locale: locale)
        guard let since else { return value }
        return value + " · " + startLabel(since, locale: locale)
    }

    /// « 26 DAYS », « 1 DAY ».
    static func days(_ count: Int) -> String {
        (count == 1 ? String(localized: "1 day") : String(localized: "\(count) days")).uppercased()
    }

    /// « +0.12 XLM since you planted », « Price +0.62% since you got them » ; `nil` sans base.
    static func sinceLine(_ pot: GrowPot, locale: Locale) -> String? {
        if pot.mark.tracksPrice {
            return pot.priceChange.map { String(localized: "Price \(GrowView.percent($0, locale: locale)) since you got them") }
        }
        return pot.growth.map { String(localized: "\(GrowView.changeText($0, asset: pot.asset, locale: locale)) since you planted") }
    }

    /// « 0.0547 USDC ».
    static func unitPrice(_ usd: Decimal, locale: Locale) -> String {
        usd.formatted(.number.locale(locale).precision(.significantDigits(1...3))) + " USDC"
    }

    /// « ETHERFUSE · 2 MIN AGO », ou « UNAVAILABLE RIGHT NOW ».
    static func priceSource(_ price: StablebondPrice?, now: Date = .now) -> String {
        guard let price else { return String(localized: "Unavailable right now").uppercased() }
        return (price.source + " · " + SavingsText.age(of: price.asOf, now: now)).uppercased()
    }

    /// Le tampon du ticket : « GROWING » (vert), « TESTNET PRICES » (rouge, CETES sur testnet), « FROZEN », « RENEW »,
    /// « LOAN » (rouge).
    static func stamp(_ pot: GrowPot, network: StellarNetwork?) -> (text: String, positive: Bool) {
        switch pot.state {
        case .needsRenewal: return (String(localized: "Renew"), false)
        case .hasDebt: return (String(localized: "Loan"), false)
        case .frozen: return (String(localized: "Frozen"), false)
        case .growing:
            if pot.mark.tracksPrice {
                return network == .testnet ? (String(localized: "Testnet prices"), false) : (String(localized: "Indicative"), true)
            }
            return (String(localized: "Growing"), true)
        }
    }

    /// La ligne de Chimpy : celle de la maquette quand ça a poussé, une ligne honnête sinon (décision de Barth du
    /// 2026-10-18).
    static func chimpyLine(_ pot: GrowPot, locale: Locale) -> String {
        switch pot.state {
        case .needsRenewal: return String(localized: "Your money is still there. It needs a renewal before I can show or move it.")
        case .hasDebt: return String(localized: "This one has a loan on it. I never borrow, so I can't move it from here.")
        case .frozen:
            return pot.mark == .ondo
                ? String(localized: "Ondo froze this USDY. Nothing moved, but it can't be swapped for now.")
                : String(localized: "Etherfuse froze these CETES. Nothing moved, but they can't be swapped for now.")
        case .growing: break
        }
        if pot.mark == .etherfuse {
            return String(localized: "CETES follow the Mexican peso. I show the price Etherfuse gives me.")
        }
        if pot.mark == .ondo {
            return String(localized: "USDY's price goes up as US Treasuries pay. I show the price RedStone gives me.")
        }
        if pot.mark == .sentora {
            return String(localized: "Sentora keeps exactly what you put in. Its rewards come at the end of the term.")
        }
        guard let growth = pot.growth else {
            return String(localized: "I don't know what you put in from this phone, so I only show what you have now.")
        }
        let change = GrowView.changeText(growth, asset: pot.asset, locale: locale)
        if growth < 0 {
            return String(localized: "It went down by \(pot.asset.displayedWithCode(-growth, locale: locale)). I show it as it is: it can go back up, or not.")
        }
        if growth == 0 {
            return String(localized: "Nothing has grown yet. I'll only show what really happens.")
        }
        switch pot.mark {
        case .xoxno: return String(localized: "Borrowers paid that \(change) back. No promises about next week.")
        default: return String(localized: "That \(change) really happened. Next week it could be more, or less.")
        }
    }

    /// « ? » : ce que c'est, en une phrase simple, sans risques ni protocole sous-jacent (décision de Barth du 2026-10-18).
    static func info(_ mark: ChimpPotProtocol) -> String {
        switch mark {
        case .defindex: String(localized: "DeFindex puts your XLM to work and gives you back what it earns. You can add more or take it out whenever you want.")
        case .xoxno: String(localized: "XOXNO lends your USDC to borrowers, who pay it back with a little extra. You can add more or take it out whenever you want.")
        case .etherfuse: String(localized: "CETES are tokens for short-term Mexican government bonds, issued by Etherfuse. You get them with a swap, and swap them back the same way.")
        case .sentora: String(localized: "Sentora keeps your USDC in its vault and gives it back exactly. At the end of each term, it pays a reward rate it publishes. Taking money out before the end gives up that term's rewards.")
        case .ondo: String(localized: "USDY is a dollar token backed by short-term US Treasuries, issued by Ondo. Its price goes up a little every day. You get it with a swap, and swap it back the same way. Not for US persons.")
        }
    }

    static func infoHonesty(_ mark: ChimpPotProtocol) -> String {
        switch mark {
        case .etherfuse: String(localized: "I show the price Etherfuse gives me, never a promised rate.")
        case .ondo: String(localized: "I show the price RedStone gives me, never a promised rate.")
        default: String(localized: "I only show what really grew, never a promised rate.")
        }
    }

    /// Le service de ce protocole ne répond pas.
    static func unanswered(_ mark: ChimpPotProtocol) -> String {
        String(localized: "\(mark.name) isn't answering right now. Your money stays where it is.")
    }
}
