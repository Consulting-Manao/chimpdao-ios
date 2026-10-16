import SwiftUI

/// Prêt XOXNO (phase 7 ; sans maquette, avec le design system, décisions de Barth du 2026-10-16) : la section « Lending » de
/// Grow, la page du marché et la page d'une position. Les écrans de dépôt et de retrait sont ceux du vault. Les trois
/// textes de risque sont obligatoires partout où l'on propose de déposer. Jamais un taux.

/// Les risques du prêt, dits simplement : où va l'argent, puis les trois textes obligatoires, puis les pastilles.
struct LendingRiskNotice: View {
    let asset: String
    var ink: Color?

    static let risks: [LocalizedStringKey] = [
        "No published audit for Stellar yet",
        "Withdrawals can be paused or limited",
        "If a borrower doesn't repay, depositors share the loss",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text("XOXNO lends your \(asset) to borrowers. You never borrow.")
                .chimpFont(.captionStrong)
                .foregroundStyle(ink ?? Color(.chimpTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.risks.enumerated()), id: \.offset) { _, risk in
                LendingRiskLine(text: risk, ink: ink)
            }
            ChimpVaultNotice(chipsOnly: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LendingRiskLine: View {
    let text: LocalizedStringKey
    var ink: Color?

    var body: some View {
        HStack(alignment: .top, spacing: ChimpSpacing.s) {
            Text(verbatim: "!")
                .chimpFont(.rowTitle)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(.chimpNegative)))
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.captionStrong)
                .foregroundStyle(ink ?? Color(.chimpTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texte d'une position qu'on ne peut pas déplacer.
enum LendingText {
    static let needsRenewal: LocalizedStringKey = "This position needs to be renewed before you can see or move it. Your money is still there."
    static let hasDebt: LocalizedStringKey = "This position has a loan on it. ChimpDAO never borrows, so it can't be moved from here."
}

/// La carte du marché dans Grow (F1).
struct LendingPlaceCard: View {
    let vault: VaultInfo

    var body: some View {
        HStack(alignment: .top, spacing: ChimpSpacing.m) {
            Text(verbatim: "X")
                .chimpFont(.displayS)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white))
                .overlay { Circle().strokeBorder(Color(.chimpTicketInk), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: vault.name).chimpFont(.rowTitle)
                Text("Lending · deposit only · testnet")
                    .chimpFont(.captionS)
                    .fontWeight(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white))
                    .overlay { Capsule().strokeBorder(Color(.chimpTicketInk), lineWidth: 2) }
                Text("XOXNO lends your \(vault.asset.code) to borrowers. No published audit for Stellar yet.")
                    .chimpFont(.captionStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").fontWeight(.black)
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpCardPink), shadow: .tile)
        .accessibilityElement(children: .combine)
    }
}

/// Les positions d'un tiroir, regroupées (chaque dépôt ouvre une position, revue de sécurité F4) : la valeur des positions
/// qu'on peut déplacer, et celles qu'on ne peut pas (à renouveler, avec dette), jamais comptées à zéro.
struct LendingDrawerGroup: Equatable {
    let drawerID: String
    let drawerAddress: String
    let holdings: [VaultHolding]

    var movable: [VaultHolding] { holdings.filter { $0.condition == .movable } }
    var value: Decimal { movable.map(\.value).reduce(0, +) }
    var needsRenewal: Bool { holdings.contains { $0.condition == .needsRenewal } }
    var hasDebt: Bool { holdings.contains { $0.condition == .hasDebt } }
    /// L'évolution depuis le dépôt : la base est celle du tiroir (tous ses dépôts), comparée à la valeur de toutes ses
    /// positions déplaçables.
    var change: Decimal? {
        guard !movable.isEmpty else { return nil }
        return movable.first?.basis?.change(value: value)
    }

    /// Un groupe par tiroir, dans l'ordre des positions.
    static func grouped(_ holdings: [VaultHolding]) -> [LendingDrawerGroup] {
        var order: [String] = []
        var byDrawer: [String: [VaultHolding]] = [:]
        for holding in holdings {
            if byDrawer[holding.drawerID] == nil { order.append(holding.drawerID) }
            byDrawer[holding.drawerID, default: []].append(holding)
        }
        return order.compactMap { id in
            byDrawer[id].map { LendingDrawerGroup(drawerID: id, drawerAddress: $0[0].drawerAddress, holdings: $0) }
        }
    }
}

/// La section « Lending » de Grow : le marché, puis une ligne par tiroir, ses positions regroupées (une position à
/// renouveler ou avec dette reste visible, jamais à zéro).
struct GrowLendingSection: View {
    let model: GrowModel
    let onOpen: (GrowRoute) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Text("Lending").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            .padding(.top, ChimpSpacing.m)
        switch model.phase {
        case .loading where model.context == nil:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, ChimpSpacing.m)
        case .unavailable where model.context == nil:
            LendingUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
        default:
            if model.phase == .unavailable {
                ChimpNoticeBanner(text: "XOXNO isn't answering right now. Showing the last numbers.", marker: .error) {
                    ChimpPillButton("Retry") { Task { await model.refresh() } }
                }
            }
            if let vault = model.vault {
                Button { onOpen(.lending) } label: { LendingPlaceCard(vault: vault) }
                    .buttonStyle(ChimpPressableStyle())
                ForEach(LendingDrawerGroup.grouped(model.holdings), id: \.drawerID) { group in
                    Button { onOpen(.lendingPosition(drawerAddress: group.drawerAddress)) } label: { row(group, asset: vault.asset) }
                        .buttonStyle(ChimpPressableStyle())
                }
            }
        }
    }

    private func row(_ group: LendingDrawerGroup, asset: SendAsset) -> some View {
        let drawer = model.drawer(id: group.drawerID)
        return HStack(spacing: ChimpSpacing.m) {
            ChimpDrawerIconView(icon: drawer?.icon ?? .main, size: CGSize(width: 34, height: 24), border: 2.5, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("In \(drawer.map(GrowView.shortTitle) ?? "")").chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                if let first = group.movable.first {
                    Text(group.holdings.count > 1 ? "\(group.holdings.count) positions · \(GrowView.putInLine(first, asset: asset, locale: locale))" : GrowView.putInLine(first, asset: asset, locale: locale))
                        .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                }
                if group.needsRenewal {
                    Text("A position needs renewal · your money is still there").chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
                }
                if group.hasDebt {
                    Text("A position has a loan · can't be moved here").chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
                }
            }
            Spacer(minLength: ChimpSpacing.s)
            if !group.movable.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: asset.displayedWithCode(group.value, locale: locale)).chimpFont(.monoValue).foregroundStyle(.chimpTextPrimary)
                    if let change = group.change {
                        Text(verbatim: GrowView.changeText(change, asset: asset, locale: locale))
                            .chimpFont(.captionStrong)
                            .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
                    }
                }
            }
            Image(systemName: "chevron.right").fontWeight(.black).foregroundStyle(.chimpTextSecondary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }
}

/// XOXNO ne répond pas (section, page du marché, page d'une position sans données).
struct LendingUnanswered: View {
    let details: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ChimpySays(text: "XOXNO isn't answering right now. Your money stays where it is.", pose: .unsure)
            ChimpButton("Try again", kind: .secondary, action: onRetry)
            if let details { ChimpTechnicalDetails(details: details) }
        }
    }
}

/// La page du marché : ce que c'est, ce qui peut sortir maintenant, les risques, « Put money in ».
struct LendingInfoView: View {
    let model: GrowModel
    let onBack: () -> Void
    let onDeposit: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: LocalizedStringKey(model.vault?.name ?? "XOXNO USDC"), subtitle: "Lending · deposit only", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    if let vault = model.vault {
                        content(vault)
                    } else if model.phase == .unavailable {
                        LendingUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh() }
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpButton("Put money in", action: onDeposit)
                .disabled(model.vault == nil || model.vault?.depositsBlocked == true)
                .padding(.horizontal, ChimpSpacing.bottomBar.leading)
                .padding(.top, ChimpSpacing.sm)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
    }

    @ViewBuilder
    private func content(_ vault: VaultInfo) -> some View {
        if vault.depositsBlocked {
            ChimpNoticeBanner(text: "XOXNO isn't taking deposits right now.", marker: .error)
        }
        section("What it is") {
            Text("A shared pot of \(vault.asset.code). XOXNO lends it to borrowers, who pay interest into the pot. You only deposit: the app never borrows.")
                .chimpFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        section("Can come out right now") {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: vault.asset.displayedWithCode(vault.availableNow, locale: locale))
                    .chimpFont(.amountS)
                    .foregroundStyle(.chimpTextPrimary)
                Text("For everyone together. The rest is lent out and comes back as borrowers repay.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        section("The risks, plainly") {
            LendingRiskNotice(asset: vault.asset.code)
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text(title).chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// La page d'une position (une par tiroir) : valeur, évolution réelle depuis le dépôt, ce qui peut sortir maintenant ;
/// une position à renouveler ou avec dette le dit, sans action.
struct LendingPositionView: View {
    let model: GrowModel
    let drawerAddress: String
    let onBack: () -> Void
    let onWithdraw: (String) -> Void
    let onDeposit: (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    private var holdings: [VaultHolding] { model.holdings.filter { $0.drawerAddress == drawerAddress } }
    private var movable: VaultHolding? { holdings.first { $0.condition == .movable } }
    private var drawer: SendDrawer? { model.drawer(address: drawerAddress) }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: LocalizedStringKey(model.vault?.name ?? "XOXNO USDC"),
                subtitle: "Yours · in \(drawer.map(GrowView.shortTitle) ?? "")",
                onBack: onBack
            )
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    if let vault = model.vault, !holdings.isEmpty {
                        if holdings.count > 1, let group = LendingDrawerGroup.grouped(holdings).first {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All positions").textCase(.uppercase).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
                                Text(verbatim: vault.asset.displayedWithCode(group.value, locale: locale))
                                    .chimpFont(.amountL).foregroundStyle(.chimpTextPrimary).lineLimit(1).minimumScaleFactor(0.5)
                                if let change = group.change {
                                    Text("\(GrowView.changeText(change, asset: vault.asset, locale: locale)) since you put it in")
                                        .chimpFont(.rowTitle)
                                        .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
                                }
                            }
                            .accessibilityElement(children: .combine)
                            ChimpNoticeBanner(
                                text: "This drawer has \(holdings.count) positions: each deposit opens a new one. Taking money out works on one position at a time, the biggest first.",
                                marker: .info
                            )
                        }
                        ForEach(Array(holdings.enumerated()), id: \.offset) { _, holding in
                            content(holding, vault: vault)
                        }
                        LendingRiskNotice(asset: vault.asset.code)
                    } else if model.phase == .unavailable {
                        LendingUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
                    } else if model.phase == .loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        ChimpySays(text: "Nothing lent from this drawer anymore.", pose: .plant)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh() }
        }
        .task { await model.refresh() }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: ChimpSpacing.sm) {
                ChimpButton("Take money out") { if let movable { onWithdraw(movable.drawerID) } }
                    .disabled(movable == nil || model.vault?.withdrawalsBlocked == true)
                ChimpButton("Put more in", kind: .secondary) { if let drawer { onDeposit(drawer.id) } }
                    .disabled(model.vault == nil || drawer == nil || model.vault?.depositsBlocked == true)
            }
            .padding(.horizontal, ChimpSpacing.bottomBar.leading)
            .padding(.top, ChimpSpacing.sm)
            .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
            .background(Color(.chimpBackground))
        }
    }

    @ViewBuilder
    private func content(_ holding: VaultHolding, vault: VaultInfo) -> some View {
        switch holding.condition {
        case .needsRenewal:
            ChimpySays(text: LendingText.needsRenewal, pose: .unsure)
        case .hasDebt:
            ChimpNoticeBanner(text: LendingText.hasDebt, marker: .error)
            valueBlock(holding, vault: vault)
        case .movable:
            valueBlock(holding, vault: vault)
            if vault.withdrawalsBlocked {
                ChimpNoticeBanner(text: "XOXNO has paused withdrawals right now. Your money is still there.", marker: .error)
            } else {
                let now = min(holding.value, vault.availableNow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can come out right now").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: vault.asset.displayedWithCode(now, locale: locale)).chimpFont(.amountS).foregroundStyle(.chimpTextPrimary)
                    if now < holding.value {
                        Text("The rest is lent out and comes back as borrowers repay.").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, ChimpSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func valueBlock(_ holding: VaultHolding, vault: VaultInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value now").textCase(.uppercase).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: vault.asset.displayedWithCode(holding.value, locale: locale))
                .chimpFont(.amountL)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // La base est celle du tiroir (tous ses dépôts) : l'évolution n'a de sens que pour une position seule.
            if let change = holding.change, holding.condition == .movable, holdings.count == 1 {
                Text("\(GrowView.changeText(change, asset: vault.asset, locale: locale)) since you put it in")
                    .chimpFont(.rowTitle)
                    .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
            }
            if let basis = holding.basis, holding.condition == .movable, holdings.count == 1 {
                Text("You put in \(vault.asset.displayedWithCode(basis.putIn, locale: locale)) on \(basis.since.formatted(.dateTime.day().month(.abbreviated)))")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
            }
            Text("Updated today at \(holding.readAt.formatted(date: .omitted, time: .shortened))")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// L'avertissement du lieu : celui du vault, ou les risques du prêt.
struct GrowPlaceNotice: View {
    let lending: Bool
    let asset: String
    let protocols: [String]
    var ink: Color?

    var body: some View {
        if lending {
            LendingRiskNotice(asset: asset, ink: ink)
        } else {
            ChimpVaultNotice(asset: asset, protocols: protocols, ink: ink)
        }
    }
}
