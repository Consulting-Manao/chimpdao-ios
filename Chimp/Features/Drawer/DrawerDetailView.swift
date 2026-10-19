import SwiftUI

/// B2r · Main account (« B2 + tiles ») et B3 · wallet d'une carte (maquettes du 2026-09-30) : le total, les pastilles
/// des cartes qui peuvent signer, une tuile par actif, « LATELY » (Main) ou les actions de la carte (B3), puis Send /
/// Move / Swap depuis ce tiroir.
///
/// Écarts avec la maquette (DESIGN_NOTES §12) : l'adresse est ajoutée (demande de Barth) ; « Receive » a été retiré de la
/// barre du bas le 2026-10-14 (quatre boutons coupaient « Receive ») : l'adresse copiable suffit, la place va à Grow ;
/// « Give this card away » (G4) est masqué, session à part.
///
/// Grow (maquettes « B2 / B3 — SWAP + VAULT » du 2026-10-15) : la tuile « DEFINDEX · GROWING » (valeur, évolution réelle
/// depuis le dépôt) à côté des actifs, dans les deux tiroirs (le Main de l'app est en tuiles, B2r), « Plant more » et
/// l'avertissement sous la grille ; le bouton Grow ouvre « Put money in » depuis ce tiroir.
struct DrawerDetailView: View {
    /// Swap éteint sur ce réseau : pas de bouton.
    @Environment(\.chimpFeatures) private var features
    @Bindable var model: DrawerDetailModel
    let activity: ActivityViewModel
    var actions: DrawerDetailActions
    /// Les positions du vault, lues par l'onglet Grow (une par tiroir).
    var grow: GrowModel?

    @Environment(\.locale) private var locale

    @State private var renameModel: SettingsModel?
    /// G5 : le compte n'a qu'une carte (dernière lecture) ; retirer ou déclarer perdue est refusé avant tout tap.
    @State private var lastCardMode: RemoveCardModel.Mode?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle, onBack: actions.onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.isMissing {
                        ChimpySays(text: "This card isn't on your account anymore.", pose: .crawl)
                    } else if let content = model.content {
                        balances(content)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, ChimpSpacing.xl)
                    }
                    if !model.isMissing {
                        if !model.isMain {
                            sectionLabel("This card")
                                .padding(.top, ChimpSpacing.xl)
                            ChimpGroupedList(rows: cardRows)
                                .padding(.top, ChimpSpacing.sm)
                        }
                        history
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
                .padding(.bottom, ChimpSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                ChimpSoundPlayer.shared.play(.branch)
                async let wallet: Void = model.refresh()
                async let history: Void = activity.refresh()
                async let vault: Void? = grow?.refresh()
                _ = await (wallet, history, vault)
            }
            if !model.isMissing { bottomBar }
        }
        .background(Color(.chimpBackground))
        .task { await activity.refresh() }
        .task { await grow?.refresh() }
        .activityReceiptSheet(
            model: activity, onSendPrefilled: actions.onSendPrefilled, onSwapPrefilled: actions.onSwapPrefilled,
            onPosition: actions.onPosition
        )
        .chimpSheet(isPresented: Binding(get: { lastCardMode != nil }, set: { if !$0 { lastCardMode = nil } }), height: 560, fitsContent: true) {
            if let mode = lastCardMode {
                LastCardSheet(mode: mode, name: model.cardName, onAddCard: {
                    lastCardMode = nil
                    actions.onAddCard()
                }, onOK: { lastCardMode = nil })
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { renameModel?.editingCard != nil },
            set: { if !$0 { renameModel = nil } }
        )) {
            if let renameModel {
                CardRenameView(model: renameModel)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: En-tête

    private var title: LocalizedStringKey {
        model.isMain ? "Main account" : "\(model.cardName) card"
    }

    private var subtitle: LocalizedStringKey {
        if model.isMain { return "Shared · any of your cards can sign" }
        return "N°\(model.card?.number ?? "····") · only this card can sign"
    }

    // MARK: Soldes

    private func balances(_ content: DrawerDetailContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            total(content)
            HStack(spacing: ChimpSpacing.s) {
                ForEach(content.signers) { signer in
                    ChimpSignerChip(name: signer.name, color: signer.color)
                }
            }
            .padding(.top, ChimpSpacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.isMain
                ? Text("Cards that can sign: \(content.signers.map(\.name).formatted(.list(type: .and)))")
                : Text("Only this card can sign: \(model.cardName)"))

            if let address = content.address {
                ChimpAddressPill(address: Self.shortAddress(address), isCopied: model.isCopied, action: model.copyAddress)
                    .padding(.top, ChimpSpacing.l)
            }

            if model.wallet.isShowingStaleData {
                ChimpNoticeBanner(text: "Couldn't refresh. Showing the last balances.", marker: .error)
                    .padding(.top, ChimpSpacing.l)
            }

            if content.isEmpty && holding(content) == nil {
                ChimpySays(text: emptyText, pose: .plant)
                    .padding(.top, ChimpSpacing.xl)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: ChimpSpacing.m), GridItem(.flexible(), spacing: ChimpSpacing.m)],
                    alignment: .leading,
                    spacing: ChimpSpacing.m
                ) {
                    ForEach(content.assets) { asset in
                        ChimpAssetTile(
                            band: asset.band, bandFill: Self.bandFill(asset.code),
                            value: asset.value ?? asset.amount, detail: asset.value == nil ? nil : asset.amount
                        )
                    }
                    if let holding = holding(content) {
                        Button { actions.onPosition(holding.drawerAddress) } label: { growingTile(holding) }
                            .buttonStyle(ChimpPressableStyle())
                            .accessibilityHint(Text("Opens your position"))
                    }
                    ForEach(content.savings) { bond in
                        Button { if let address = content.address { actions.onSavings(address) } } label: { savingsTile(bond, address: content.address) }
                            .buttonStyle(ChimpPressableStyle())
                            .accessibilityHint(Text("Opens your savings bonds"))
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                if holding(content) != nil, let vault = grow?.vault {
                    plantMore
                        .padding(.top, ChimpSpacing.m)
                    ChimpVaultNotice(asset: vault.asset.code, protocols: vault.protocols)
                        .padding(.top, ChimpSpacing.s)
                }
            }
        }
    }

    // MARK: Grow

    private func holding(_ content: DrawerDetailContent) -> VaultHolding? {
        content.address.flatMap { grow?.holding(drawerAddress: $0) }
    }

    /// « DEFINDEX · GROWING », « 40.09 XLM », « +0.11 XLM since 22 Sep » (la valeur seule si la base n'est pas connue).
    private func growingTile(_ holding: VaultHolding) -> some View {
        let asset = grow?.vault?.asset ?? .xlm
        let runner = grow?.vault?.protocols.first ?? "DeFindex"
        return ChimpAssetTile(
            band: "\(runner.uppercased()) · \(String(localized: "Growing").uppercased())",
            bandFill: Color(.chimpHeader), bandInk: Color(.chimpOnHeaderPrimary),
            value: asset.displayedWithCode(holding.value, locale: locale),
            detail: holding.change.flatMap { change in
                holding.basis.map { basis in
                    String(localized: "\(GrowView.changeText(change, asset: asset, locale: locale)) since \(basis.since.formatted(.dateTime.day().month(.abbreviated)))")
                }
            },
            detailColor: (holding.change ?? 0) < 0 ? Color(.chimpNegative) : Color(.chimpPositive)
        )
    }

    /// Tuile d'un stablebond, construite comme « GROWING » (décision de Barth du 2026-10-15) : « ETHERFUSE · CETES »,
    /// la quantité, puis « Price +0.62% since 22 Sep » si la base est connue, sinon « ≈ 99.58 USDC » au prix d'Etherfuse,
    /// sinon rien ; gelés : « Frozen by Etherfuse » en rouge.
    private func savingsTile(_ bond: DrawerDetailContent.Asset, address: String?) -> some View {
        let asset = SendAsset(code: bond.code) ?? .cetes
        let holding = address.flatMap { grow?.savingsHolding(drawerAddress: $0) }
        let price = grow?.savingsPrice
        let issuer = asset.issuerName ?? String(localized: "The issuer")
        let detail: String?
        var color = Color(.chimpTextSecondary)
        if holding?.frozen == true {
            detail = String(localized: "Frozen by \(issuer)")
            color = Color(.chimpNegative)
        } else if let holding, let change = holding.priceChange(price), let since = holding.basis?.since {
            detail = String(localized: "Price \(SavingsText.change(change, locale: locale)) since \(since.formatted(.dateTime.day().month(.abbreviated)))")
            color = change < 0 ? Color(.chimpNegative) : Color(.chimpPositive)
        } else if let holding, let price {
            detail = SavingsText.value(holding.amount, price: price, locale: locale)
        } else {
            detail = nil
        }
        return ChimpAssetTile(
            band: "\(issuer.uppercased()) · \(asset.code)", bandFill: Color(.chimpAssetCetes), bandInk: Color(.chimpTicketInk),
            value: bond.amount, detail: detail, detailColor: color
        )
    }

    /// « Plant more » : mettre encore depuis ce tiroir (bordure pointillée, maquette B3).
    private var plantMore: some View {
        Button { actions.onGrow(model.selection.drawerID) } label: {
            HStack(spacing: ChimpSpacing.s) {
                Image(.tileBanana).resizable().scaledToFit().frame(width: 24).accessibilityHidden(true)
                Text("Plant more").chimpFont(.buttonSmall)
            }
            .foregroundStyle(.chimpTextSecondary)
            .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(.chimpTextSecondary), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [7, 5]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
    }

    private func total(_ content: DrawerDetailContent) -> some View {
        Text(verbatim: content.total)
            .chimpFont(.amountL)
            .foregroundStyle(.chimpTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// Couleur du bandeau d'une tuile (maquette : USDC vert, XLM jaune).
    static func bandFill(_ code: String) -> Color {
        code == "USDC" ? Color(.chimpCardLeaf) : Color(.chimpCardBanana)
    }

    private var emptyText: LocalizedStringKey {
        model.isMain
            ? "Main is empty. Share its address above to get your first bananas."
            : "\(model.cardName)'s wallet is empty. Share its address above, or tap Move to fill it."
    }

    // MARK: Cette carte

    private var cardRows: [ChimpGroupedRow] {
        var rows = [ChimpGroupedRow(id: "rename", title: "Rename & colour") { renameModel = model.makeRenameModel() }]
        // Pas dans la maquette : changer le PIN (Infineon seulement ; une DUOX n'a pas de PIN).
        if model.pinCard != nil, case .card(let key) = model.selection {
            rows.append(ChimpGroupedRow(id: "pin", title: "Change PIN") { actions.onChangePIN(key) })
        }
        rows.append(ChimpGroupedRow(id: "remove", title: "Remove from account") { openRemoval(.remove) })
        rows.append(ChimpGroupedRow(id: "lost", title: "I lost this card", tone: .destructive) { openRemoval(.lost) })
        return rows
    }

    /// Dernière carte (lue par le Wallet) : G5 tout de suite ; sinon la revue (G6, G7). La revue revérifie sur la chaîne.
    private func openRemoval(_ mode: RemoveCardModel.Mode) {
        guard case .card(let key) = model.selection else { return }
        if model.cardCount <= 1 {
            lastCardMode = mode
        } else {
            actions.onRemove(mode, key)
        }
    }

    // MARK: Historique

    /// B2r « LATELY » : les deux derniers mouvements de Main, « All activity » ouvre l'onglet Activity sur Main.
    /// B3 : rien (maquette).
    @ViewBuilder
    private var history: some View {
        if model.isMain, let address = model.content?.address {
            let rows = DrawerDetailModel.lately(
                records: activity.records, drawer: address, drawers: activity.drawers,
                cardName: { [source = activity.source] in source.cardName(key: $0) }
            )
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Lately")
                Spacer()
                Button { actions.onAllActivity(address) } label: {
                    Text("All activity")
                        .chimpFont(.captionStrong)
                        .underline()
                        .foregroundStyle(.chimpTextPrimary)
                        // Zone de toucher de 44 pt sans écarter la ligne (la maquette la veut serrée).
                        .padding(ChimpSpacing.m)
                        .contentShape(Rectangle())
                        .padding(-ChimpSpacing.m)
                }
                .buttonStyle(ChimpPressableStyle())
            }
            .padding(.top, ChimpSpacing.xl)
            .padding(.bottom, ChimpSpacing.xxs)
            if rows.isEmpty {
                Text(activity.phase == .loaded && !activity.isSyncing ? "Nothing moved here yet." : "Reading the last 7 days on Stellar…")
                    .chimpFont(.captionS)
                    .foregroundStyle(.chimpTextSecondary)
                    .padding(.vertical, 9)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle().fill(Color(.chimpSurfaceSecondary)).frame(height: ChimpBorder.thin)
                        }
                        Button { activity.selectedRecord = row.record } label: {
                            ChimpRecentRow(title: row.title, meta: row.meta, amount: row.amount, isIncoming: row.isIncoming)
                        }
                        .buttonStyle(ChimpPressableStyle())
                        .accessibilityHint(Text("Opens the receipt"))
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var bottomBar: some View {
        let isEmpty = model.content?.isEmpty ?? true
        let id = model.selection.drawerID
        return HStack(spacing: ChimpSpacing.sm) {
            ChimpButton("Send", size: .compact) { actions.onSend(id) }
                .disabled(isEmpty)
            ChimpButton("Move", kind: .secondary, size: .compact) { actions.onMove(id) }
                .disabled(isEmpty)
            // Maquette B2 / B3 « with Swap » : Swap s'ouvre avec ce tiroir déjà choisi.
            if features.swap {
                ChimpButton("Swap", kind: .secondary, size: .compact) { actions.onSwap(id) }
                    .disabled(isEmpty)
            }
            // Maquette B2 / B3 « Swap + Vault » : « Put money in » depuis ce tiroir.
            if grow != nil {
                ChimpButton("Grow", kind: .secondary, size: .compact) { actions.onGrow(id) }
                    .disabled(isEmpty)
            }
        }
        .padding(ChimpSpacing.bottomBar)
        .background(Color(.chimpBackground))
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        sectionLabel(Text(text))
    }

    private func sectionLabel(_ text: Text) -> some View {
        text
            .chimpFont(.label)
            .textCase(.uppercase)
            .foregroundStyle(.chimpTextSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

extension DrawerDetailView {
    /// Adresse raccourcie comme dans Recevoir (D1) : 8 premiers et 6 derniers caractères.
    static func shortAddress(_ address: String) -> String {
        address.count > 16 ? "\(address.prefix(8))…\(address.suffix(6))" : address
    }
}

/// Ce que la page d'un tiroir demande à la coque (`MainTabView`) : chaque action part **de ce tiroir**.
struct DrawerDetailActions {
    var onBack: () -> Void = {}
    /// Envoyer, avec ce tiroir en « From » (identifiant du tiroir).
    var onSend: (String) -> Void = { _ in }
    /// Move, depuis ce tiroir.
    var onMove: (String) -> Void = { _ in }
    /// Swap, dans ce tiroir.
    var onSwap: (String) -> Void = { _ in }
    /// « Pay again » ou « Send back » d'un reçu.
    var onSendPrefilled: (SendPrefill) -> Void = { _ in }
    /// « Swap again » d'un reçu.
    var onSwapPrefilled: (SwapPrefill) -> Void = { _ in }
    /// Paiement en attente touché dans l'historique.
    var onPending: () -> Void = {}
    /// « All activity » (B2r) : l'onglet Activity, filtré sur ce tiroir (adresse).
    var onAllActivity: (String) -> Void = { _ in }
    /// Changer le PIN de cette carte (clé).
    var onChangePIN: (String) -> Void = { _ in }
    /// G6 (retirer) ou G7 (carte perdue) pour cette carte (clé).
    var onRemove: (RemoveCardModel.Mode, String) -> Void = { _, _ in }
    /// G5 « Add a card ».
    var onAddCard: () -> Void = {}
    /// Grow, « Plant more » : mettre dans le vault depuis ce tiroir (identifiant).
    var onGrow: (String) -> Void = { _ in }
    /// La tuile « GROWING », « See my position » d'un reçu : F6 pour ce tiroir (adresse).
    var onPosition: (String) -> Void = { _ in }
    /// La tuile d'un stablebond (CETES) : F10 pour ce tiroir (adresse).
    var onSavings: (String) -> Void = { _ in }
}
