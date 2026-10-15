import SwiftUI

/// F2 · le vault (maquette du 2026-10-15) : ce que c'est, où va l'argent (ton XLM → DeFindex → Blend), les risques
/// dits simplement, l'avertissement, « Put money in ». Aucun niveau de risque tant qu'aucune grille n'est validée avec
/// Pamphile (décision de Barth du 2026-10-15) : à la place, le nombre de protocoles traversés.
struct VaultInfoView: View {
    let model: GrowModel
    let onBack: () -> Void
    let onDeposit: () -> Void

    @Environment(\.chimpScreenInsets) private var screenInsets

    /// « Goes through 2 protocols: DeFindex, then Blend ».
    static func protocolsLine(_ vault: VaultInfo) -> LocalizedStringKey {
        let names = vault.protocols
        guard names.count > 1, let first = names.first, let last = names.last else {
            return "Goes through \(names.first ?? "DeFindex")"
        }
        return "Goes through \(names.count) protocols: \(first), then \(last)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "\(model.vault?.name ?? "DeFindex XLM") vault", subtitle: "Grow · XLM only", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    if let vault = model.vault {
                        content(vault)
                    } else if model.phase == .unavailable {
                        VaultUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpButton("Put money in", action: onDeposit)
                .disabled(model.vault == nil)
                .padding(.horizontal, ChimpSpacing.bottomBar.leading)
                .padding(.top, ChimpSpacing.sm)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .background(Color(.chimpBackground))
        }
    }

    @ViewBuilder
    private func content(_ vault: VaultInfo) -> some View {
        Text(Self.protocolsLine(vault))
            .chimpFont(.captionS)
            .fontWeight(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.chimpTextPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay { Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
        section("What it is") {
            Text("A shared pot of \(vault.asset.code). The vault lends it out, borrowers pay interest, and that goes back into the pot. You own a slice of it.")
                .chimpFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        section("Where your \(vault.asset.code) goes") {
            HStack(spacing: ChimpSpacing.xs) {
                step(mark: nil, title: "Your \(vault.asset.code)", detail: "from a drawer")
                arrow
                step(mark: vault.protocols.first, title: LocalizedStringKey(vault.protocols.first ?? "DeFindex"), detail: "runs the vault")
                arrow
                step(mark: vault.protocols.last, title: LocalizedStringKey(vault.protocols.last ?? "Blend"), detail: "lends it out")
            }
        }
        ChimpVaultNotice(asset: vault.asset.code, protocols: vault.protocols)
        section("The risks, plainly") {
            VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                risk("It can earn little or nothing, and you can even end up with less \(vault.asset.code).")
                risk("\(vault.protocols.last ?? "Blend") or \(vault.protocols.first ?? "DeFindex") could have a bug, or borrowers might not pay back.")
                risk("If lots of people leave at once, getting yours out can take a while.")
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text(title).chimpFont(.displayS).foregroundStyle(.chimpTextPrimary).accessibilityAddTraits(.isHeader)
            content().foregroundStyle(.chimpTextPrimary)
        }
    }

    private func step(mark: String?, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Group {
                if let mark {
                    Text(verbatim: String(mark.prefix(1))).chimpFont(.displayS)
                } else {
                    Image(.tileLogo).resizable().scaledToFit().padding(6)
                }
            }
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color(.chimpSurface)))
            .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
            Text(title).chimpFont(.rowTitle).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).chimpFont(.captionS).foregroundStyle(.chimpTextSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var arrow: some View {
        Text(verbatim: "→").chimpFont(.displayS).foregroundStyle(.chimpTextSecondary).accessibilityHidden(true)
    }

    private func risk(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: ChimpSpacing.s) {
            Text(verbatim: "!")
                .chimpFont(.rowTitle)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(.chimpNegative)))
                .accessibilityHidden(true)
            Text(text).chimpFont(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// F6 · ma position, **une par tiroir** (décision de Barth du 2026-10-15) : valeur actuelle, évolution réelle depuis le
/// dépôt (la valeur seule si la base n'est pas connue), heure de lecture, ce qui a été mis et quand. Les parts ne
/// s'affichent que sur les reçus. « Take money out », « Put more in ».
struct VaultPositionView: View {
    let model: GrowModel
    let drawerAddress: String
    let onBack: () -> Void
    /// Retirer, puis mettre, depuis ce tiroir (identifiant du tiroir).
    let onWithdraw: (String) -> Void
    let onDeposit: (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.chimpScreenInsets) private var screenInsets

    private var holding: VaultHolding? { model.holding(drawerAddress: drawerAddress) }
    private var drawer: SendDrawer? { model.drawer(address: drawerAddress) }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(
                title: "\(model.vault?.name ?? "DeFindex XLM") vault",
                subtitle: "Yours · in \(drawer.map(GrowView.shortTitle) ?? "")",
                onBack: onBack
            )
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    if let holding, let vault = model.vault {
                        content(holding, vault: vault)
                    } else if model.phase == .unavailable {
                        VaultUnanswered(details: model.technicalDetails) { Task { await model.refresh() } }
                    } else if model.phase == .loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        ChimpySays(text: "Nothing growing in this drawer anymore.", pose: .plant)
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
                ChimpButton("Take money out") { if let holding { onWithdraw(holding.drawerID) } }
                    .disabled(holding == nil)
                ChimpButton("Put more in", kind: .secondary) { if let drawer { onDeposit(drawer.id) } }
                    .disabled(model.vault == nil || drawer == nil)
            }
            .padding(.horizontal, ChimpSpacing.bottomBar.leading)
            .padding(.top, ChimpSpacing.sm)
            .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
            .background(Color(.chimpBackground))
        }
    }

    @ViewBuilder
    private func content(_ holding: VaultHolding, vault: VaultInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value now").textCase(.uppercase).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: vault.asset.displayedWithCode(holding.value, locale: locale))
                .chimpFont(.amountL)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let change = holding.change {
                Text("\(GrowView.changeText(change, asset: vault.asset, locale: locale)) since you put it in")
                    .chimpFont(.rowTitle)
                    .foregroundStyle(change < 0 ? Color(.chimpNegative) : Color(.chimpPositive))
            }
            Text("Updated today at \(holding.readAt.formatted(date: .omitted, time: .shortened))")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
        }
        .accessibilityElement(children: .combine)
        if let basis = holding.basis {
            VStack(alignment: .leading, spacing: 2) {
                Text("You put in").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                Text(verbatim: vault.asset.displayedWithCode(basis.putIn, locale: locale)).chimpFont(.amountS).foregroundStyle(.chimpTextPrimary)
                Text("on \(basis.since.formatted(.dateTime.day().month(.abbreviated)))").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, ChimpSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
            .accessibilityElement(children: .combine)
        }
        ChimpVaultNotice(asset: vault.asset.code, protocols: vault.protocols)
    }
}
