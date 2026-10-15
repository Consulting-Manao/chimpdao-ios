import SwiftUI

/// Où l'onglet Grow emmène.
enum GrowRoute: Hashable {
    /// F2 · le vault.
    case vault
    /// F6 · la position d'un tiroir (adresse du tiroir ; une par tiroir, jamais fusionnées).
    case position(drawerAddress: String)
    /// F3 · mettre, depuis un tiroir (ou le premier).
    case deposit(drawerID: String?)
    /// F7 · retirer, vers le tiroir qui détient la position.
    case withdraw(drawerID: String)
}

/// F1 · Grow (maquette du 2026-10-15, décisions de Barth du même jour) : ce qui pousse (valeur, évolution réelle depuis
/// le dépôt), le seul lieu pour faire pousser (« Goes through 2 protocols: DeFindex, then Blend », aucun niveau de risque
/// tant qu'aucune grille n'est validée), une ligne « Yours » par tiroir, Chimpy et l'avertissement. Jamais un taux.
struct GrowView: View {
    let model: GrowModel
    let onOpen: (GrowRoute) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.sm) {
                    switch model.phase {
                    case .loading where model.context == nil:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, ChimpSpacing.xl)
                    case .unavailable where model.context == nil:
                        VaultUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
                    default:
                        content
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                ChimpSoundPlayer.shared.play(.branch)
                await model.refresh()
            }
        }
        .background(Color(.chimpBackground))
        .task { await model.refresh() }
    }

    // MARK: En-tête

    @ViewBuilder
    private var header: some View {
        if model.holdings.isEmpty {
            ChimpHeader(title: "Grow", subtitle: "XLM only · no promised rates")
        } else {
            GrowHero(value: model.totalValue, change: model.totalChange, asset: model.vault?.asset ?? .xlm)
        }
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if model.phase == .unavailable {
            ChimpNoticeBanner(text: "DeFindex isn't answering right now. Showing the last numbers.", marker: .error) {
                ChimpPillButton("Retry") { Task { await model.refresh() } }
            }
        }
        if model.holdings.isEmpty {
            ChimpySays(text: "Nothing growing yet. Your XLM can go in the vault below.", pose: .plant)
                .padding(.bottom, ChimpSpacing.s)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("Places to grow").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary)
            Text("Just one for now.").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
        }
        if let vault = model.vault {
            Button { onOpen(.vault) } label: { VaultPlaceCard(vault: vault) }
                .buttonStyle(ChimpPressableStyle())
        }
        if !model.holdings.isEmpty {
            Text("Yours").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).padding(.top, ChimpSpacing.s)
            ForEach(model.holdings, id: \.drawerID) { holding in
                Button { onOpen(.position(drawerAddress: holding.drawerAddress)) } label: { yours(holding) }
                    .buttonStyle(ChimpPressableStyle())
            }
        }
        ChimpySays(text: "No promised rates here. I only show what your XLM really did.", pose: .teacher)
            .padding(.top, ChimpSpacing.m)
        ChimpVaultNotice(chipsOnly: true)
    }

    /// « In Main · 50 XLM put in · updated 09:00 · 50.12 XLM · +0.12 XLM ».
    private func yours(_ holding: VaultHolding) -> some View {
        let asset = model.vault?.asset ?? .xlm
        let drawer = model.drawer(id: holding.drawerID)
        return HStack(spacing: ChimpSpacing.m) {
            ChimpDrawerIconView(icon: drawer?.icon ?? .main, size: CGSize(width: 34, height: 24), border: 2.5, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("In \(drawer.map(Self.shortTitle) ?? "")").chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                Text(Self.putInLine(holding, asset: asset, locale: locale)).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            }
            Spacer(minLength: ChimpSpacing.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: asset.displayedWithCode(holding.value, locale: locale)).chimpFont(.monoValue).foregroundStyle(.chimpTextPrimary)
                if let change = holding.change {
                    Text(verbatim: Self.changeText(change, asset: asset, locale: locale))
                        .chimpFont(.captionStrong)
                        .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
                }
            }
            Image(systemName: "chevron.right").fontWeight(.black).foregroundStyle(.chimpTextSecondary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }

    // MARK: Textes partagés

    static func shortTitle(_ drawer: SendDrawer) -> String {
        if case .main = drawer.kind { return String(localized: "Main") }
        return drawer.title
    }

    /// « +0.12 XLM », « −0.03 XLM », « 0 XLM » : l'évolution réelle, en quantité (2 décimales, tronquée).
    static func changeText(_ change: Decimal, asset: SendAsset, locale: Locale) -> String {
        let sign = change > 0 ? "+" : (change < 0 ? "\u{2212}" : "")
        return sign + asset.displayedWithCode(abs(change), locale: locale)
    }

    /// « 50 XLM put in · updated 09:00 », ou « updated 09:00 » si la base n'est pas connue.
    static func putInLine(_ holding: VaultHolding, asset: SendAsset, locale: Locale) -> String {
        let updated = String(localized: "updated \(holding.readAt.formatted(date: .omitted, time: .shortened))")
        guard let basis = holding.basis else { return updated }
        return String(localized: "\(asset.displayedWithCode(basis.putIn, locale: locale)) put in") + " · " + updated
    }
}

/// L'en-tête vert de F1 : « GROWING NOW », la valeur, l'évolution réelle, Chimpy qui plante.
struct GrowHero: View {
    let value: Decimal
    let change: Decimal?
    let asset: SendAsset

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        HStack(alignment: .bottom, spacing: ChimpSpacing.xxs) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Growing now").textCase(.uppercase).chimpFont(.label)
                Text(verbatim: asset.displayedWithCode(value, locale: locale))
                    .chimpFont(.displayXL)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let change {
                    Text("\(GrowView.changeText(change, asset: asset, locale: locale)) since you put it in").chimpFont(.rowTitle)
                }
            }
            Spacer(minLength: 0)
            Image(.chimpyPlant)
                .resizable()
                .scaledToFit()
                .frame(width: 112)
                .padding(.bottom, -10)
                .chimpBob(duration: 5)
                .accessibilityHidden(true)
        }
        .foregroundStyle(ChimpCardColor.leaf.ink)
        .padding(ChimpSpacing.header(for: screenInsets))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ChimpCardColor.leaf.fill
                .overlay { ChimpPattern(opacity: 0.14) }
                .ignoresSafeArea(edges: .top)
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

/// La carte jaune du vault (F1) : « D », nom, « Goes through 2 protocols: DeFindex, then Blend », où va l'argent.
struct VaultPlaceCard: View {
    let vault: VaultInfo

    var body: some View {
        HStack(alignment: .top, spacing: ChimpSpacing.m) {
            Text(verbatim: String(vault.protocols.first?.prefix(1) ?? "D"))
                .chimpFont(.displayS)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white))
                .overlay { Circle().strokeBorder(Color(.chimpTicketInk), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(vault.name) vault").chimpFont(.rowTitle)
                Text(VaultInfoView.protocolsLine(vault))
                    .chimpFont(.captionS)
                    .fontWeight(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white))
                    .overlay { Capsule().strokeBorder(Color(.chimpTicketInk), lineWidth: 2) }
                Text("This vault lends your \(vault.asset.code) on \(vault.protocols.last ?? "Blend") through \(vault.protocols.first ?? "DeFindex")")
                    .chimpFont(.captionStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").fontWeight(.black)
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpCardBanana), shadow: .tile)
        .accessibilityElement(children: .combine)
    }
}

/// Le vault ne répond pas (F1, F2, F6 sans données) : décision de Barth du 2026-10-15.
struct VaultUnanswered: View {
    let details: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ChimpySays(text: "DeFindex isn't answering right now. Your money stays in the vault.", pose: .unsure)
            ChimpButton("Try again", kind: .secondary, action: onRetry)
            if let details { ChimpTechnicalDetails(details: details) }
        }
    }
}
