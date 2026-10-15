import SwiftUI

/// Textes partagés de F9, F10 et de la tuile CETES (B2/B3).
enum SavingsText {
    /// « 2 min ago », « just now », « 3 h ago » : l'âge du prix, toujours dit.
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return String(localized: "just now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(localized: "\(minutes) min ago") }
        return String(localized: "\(minutes / 60) h ago")
    }

    /// « +0.62% », « −1.10% ».
    static func change(_ fraction: Decimal, locale: Locale) -> String {
        let sign = fraction > 0 ? "+" : (fraction < 0 ? "\u{2212}" : "")
        return sign + abs(fraction).formatted(.percent.locale(locale).precision(.fractionLength(2)))
    }

    /// « ≈ 99.58 USDC » : la valeur indicative, au prix d'Etherfuse (USD, affiché en USDC comme la maquette).
    static func value(_ amount: Decimal, price: StablebondPrice, locale: Locale) -> String {
        "≈ " + SendAsset.usdc.displayedWithCode(price.value(of: amount), locale: locale)
    }

    /// « 1 CETES ≈ 0.0547 USDC ».
    static func unitPrice(_ price: StablebondPrice, code: String, locale: Locale) -> String {
        "1 \(code) ≈ " + price.usd.formatted(.number.locale(locale).precision(.significantDigits(1...3))) + " USDC"
    }
}

/// « Price from Etherfuse, 2 min ago · indicative » (pastille verte), ou « Price unavailable right now · showing the
/// amount only » : la source et l'heure toujours dites (maquettes F9, F9a, F10, F10a).
struct SavingsPriceLine: View {
    let price: StablebondPrice?
    /// F10 : le prix d'un jeton devant (« 1 CETES ≈ 0.0547 USDC · … »).
    var unitOf: String?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(price == nil ? Color(.chimpTextSecondary) : Color(.chimpCardLeaf))
                .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: 2) }
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.mono)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        guard let price else { return String(localized: "Price unavailable right now · showing the amount only") }
        let from = String(localized: "Price from \(price.source), \(SavingsText.age(of: price.asOf)) · indicative")
        guard let unitOf else { return from }
        return SavingsText.unitPrice(price, code: unitOf, locale: locale) + " · " + from
    }
}

/// Builds de test seulement (Debug et Testing, testnet) : « Testnet: pool prices don't match real prices » (décision de
/// Barth du 2026-10-15), sur le swap et les écrans du CETES.
struct ChimpTestnetPriceNote: View {
    let network: StellarNetwork?

    var body: some View {
        #if DESIGN_CATALOG
        if network == .testnet {
            Label {
                Text("Testnet: pool prices don't match real prices")
            } icon: {
                Image(systemName: "flask.fill")
            }
            .chimpFont(.captionS)
            .fontWeight(.heavy)
            .foregroundStyle(.chimpTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }
}

/// Bandeau rouge d'un tiroir dont les CETES sont gelés (texte validé par Barth le 2026-10-15, F9 et F10).
struct SavingsFrozenBanner: View {
    let asset: SendAsset
    let drawerName: String

    var body: some View {
        let issuer = asset.issuerName ?? String(localized: "The issuer")
        VStack(alignment: .leading, spacing: 2) {
            Text("\(issuer) froze the \(asset.code) in \(drawerName)").chimpFont(.rowTitle)
            Text("They can't be swapped until \(issuer) unfreezes them. Nothing moved.").chimpFont(.caption)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .padding(.horizontal, 13)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpNegative))
        .accessibilityElement(children: .combine)
    }
}

/// La carte CETES de F1, section « Savings bonds » (maquettes F9, F9a, F9b) : l'actif, puis **une ligne par tiroir**
/// (« In Main · 1,820.40 CETES · ≈ 99.58 USDC · Price +0.62% since you got them »), le bandeau rouge d'un tiroir gelé,
/// la ligne du prix ; sans CETES : « You don't have any CETES yet… » et « Get some ».
struct SavingsCard: View {
    let model: GrowModel
    let onOpen: (GrowRoute) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if let savings = model.savings {
            card(savings)
        } else if model.savingsPhase == .unavailable {
            VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                ChimpNoticeBanner(text: "I can't read your CETES right now.", marker: .error) {
                    ChimpPillButton("Retry") { Task { await model.refresh() } }
                }
                if let details = model.savingsDetails { ChimpTechnicalDetails(details: details) }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, ChimpSpacing.m)
        }
    }

    private func card(_ savings: SavingsContext) -> some View {
        let main = savings.drawers.first { $0.kind == .main }
        let first = savings.holdings.first?.drawerAddress ?? main?.address
        return VStack(alignment: .leading, spacing: 0) {
            Button { if let first { onOpen(.savings(drawerAddress: first)) } } label: { header(savings.asset) }
                .buttonStyle(ChimpPressableStyle())
            if savings.holdings.isEmpty {
                divider
                Text("You don't have any \(savings.asset.code) yet. You get them with a swap, from XLM or USDC.")
                    .chimpFont(.body)
                    .foregroundStyle(.chimpTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let main {
                    ChimpButton("Get some", size: .compact) {
                        onOpen(.swap(SwapPrefill(drawerAddress: main.address, given: .usdc, received: savings.asset, amount: nil)))
                    }
                    .padding(.top, ChimpSpacing.s)
                }
            } else {
                ForEach(savings.holdings) { holding in
                    divider
                    Button { onOpen(.savings(drawerAddress: holding.drawerAddress)) } label: { line(holding, savings: savings) }
                        .buttonStyle(ChimpPressableStyle())
                }
            }
            SavingsPriceLine(price: savings.price.price)
                .padding(.top, 9)
            ChimpTestnetPriceNote(network: savings.network)
                .padding(.top, ChimpSpacing.xs)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .tile)
    }

    private func header(_ asset: SendAsset) -> some View {
        HStack(spacing: ChimpSpacing.m) {
            ChimpAssetIcon(glyph: asset.glyph, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: asset.code).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                if let line = asset.descriptionLine {
                    Text(verbatim: line).chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                }
            }
            Spacer(minLength: ChimpSpacing.s)
            Image(systemName: "chevron.right").fontWeight(.black).foregroundStyle(.chimpTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Color(.chimpSurfaceSecondary)).frame(height: ChimpBorder.thin).padding(.vertical, 9)
    }

    private func line(_ holding: SavingsHolding, savings: SavingsContext) -> some View {
        let name = savings.drawer(address: holding.drawerAddress).map(GrowView.shortTitle) ?? ""
        let price = savings.price.price
        return VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            HStack(alignment: .bottom, spacing: ChimpSpacing.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("In \(name)").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: savings.asset.displayedWithCode(holding.amount, locale: locale))
                        .chimpFont(.amountM)
                        .foregroundStyle(.chimpTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer(minLength: ChimpSpacing.s)
                if let price {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: SavingsText.value(holding.amount, price: price, locale: locale))
                            .chimpFont(.monoValue)
                            .foregroundStyle(.chimpTextPrimary)
                        if let change = holding.priceChange(price) {
                            Text("Price \(SavingsText.change(change, locale: locale))")
                                .chimpFont(.captionStrong)
                                .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
                            Text("since you got them").chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                        }
                    }
                }
            }
            if holding.frozen {
                SavingsFrozenBanner(asset: savings.asset, drawerName: name)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// F10 · CETES d'un tiroir (maquettes F10, F10a, F10b) : ce qu'on a et sa valeur indicative, l'évolution du prix depuis
/// le swap, la source et l'heure du prix, ce que c'est, les risques dits simplement, l'avertissement ; « Get more » (ou
/// « Get some ») et « Swap back », préremplis avec la paire seule, montant vide (décision de Barth du 2026-10-15).
struct SavingsView: View {
    let model: GrowModel
    let drawerAddress: String
    let onBack: () -> Void
    let onSwap: (SwapPrefill) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    private var savings: SavingsContext? { model.savings }
    private var asset: SendAsset { savings?.asset ?? .cetes }
    private var holding: SavingsHolding? { model.savingsHolding(drawerAddress: drawerAddress) }
    private var drawerName: String { savings?.drawer(address: drawerAddress).map(GrowView.shortTitle) ?? String(localized: "Main") }
    private var amount: Decimal { holding?.amount ?? 0 }
    private var frozen: Bool { holding?.frozen ?? false }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: LocalizedStringKey(asset.code), subtitle: "Savings bonds · by \(asset.issuerName ?? "Etherfuse")", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                    if savings != nil {
                        youHave
                        if frozen { SavingsFrozenBanner(asset: asset, drawerName: drawerName) }
                    } else if model.savingsPhase == .unavailable {
                        ChimpNoticeBanner(text: "I can't read your CETES right now.", marker: .error) {
                            ChimpPillButton("Retry") { Task { await model.refresh() } }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    whatItIs
                    risks
                    ChimpTestnetPriceNote(network: savings?.network)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh() }
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .task { await model.refresh() }
    }

    private var youHave: some View {
        let price = savings?.price.price
        return VStack(alignment: .leading, spacing: 4) {
            Text("You have · in \(drawerName)").textCase(.uppercase).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: asset.displayedWithCode(amount, locale: locale))
                .chimpFont(.amountL)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if amount == 0 {
                Text("Get some with a swap from XLM or USDC.").chimpFont(.body).foregroundStyle(.chimpTextSecondary)
            } else if let price {
                ChimpFlowLayout(spacing: 8) {
                    Text(verbatim: SavingsText.value(amount, price: price, locale: locale)).chimpFont(.monoValue).foregroundStyle(.chimpTextPrimary)
                    if let change = holding?.priceChange(price) {
                        Text("Price \(SavingsText.change(change, locale: locale)) since you got them")
                            .chimpFont(.captionStrong)
                            .foregroundStyle(change < 0 ? Color.white : Color(.chimpTicketInk))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(change < 0 ? Color(.chimpNegative) : Color(.chimpCardLeaf)))
                            .overlay { Capsule().strokeBorder(Color(.chimpOutline), lineWidth: 2) }
                    }
                }
                .padding(.top, 2)
            }
            if amount > 0 || price != nil {
                SavingsPriceLine(price: price, unitOf: asset.code).padding(.top, 5)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
        .accessibilityElement(children: .combine)
    }

    private var whatItIs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What it is").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            Text("Tokens for short-term Mexican government bonds, called CETES. Etherfuse holds the bonds and issues the tokens. You get them with a swap, like any other coin.")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    private var risks: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("The risks, plainly").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            risk("Value follows the Mexican peso")
            risk("The issuer can freeze or take back these tokens")
            risk("Small market: buying or selling can move the price a lot")
            ChimpVaultNotice(chipsOnly: true).padding(.top, 3)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    private func risk(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: ChimpSpacing.s) {
            Text(verbatim: "!")
                .chimpFont(.rowTitle)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(.chimpNegative)))
                .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: 2.5) }
                .accessibilityHidden(true)
            Text(text).chimpFont(.bodyS).fontWeight(.heavy).foregroundStyle(.chimpTextPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        VStack(spacing: ChimpSpacing.sm) {
            ChimpButton(amount > 0 ? "Get more" : "Get some") {
                onSwap(SwapPrefill(drawerAddress: drawerAddress, given: .usdc, received: asset, amount: nil))
            }
            .disabled(savings == nil || frozen)
            ChimpButton("Swap back", kind: .secondary) {
                onSwap(SwapPrefill(drawerAddress: drawerAddress, given: asset, received: .usdc, amount: nil))
            }
            .disabled(amount <= 0 || frozen)
        }
        .padding(.horizontal, ChimpSpacing.bottomBar.leading)
        .padding(.top, ChimpSpacing.sm)
        .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
        .background(Color(.chimpBackground))
    }
}
