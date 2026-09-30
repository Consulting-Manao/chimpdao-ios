import SwiftUI

/// B2r · Main account (« B2 + tiles ») et B3 · wallet d'une carte (maquettes du 2026-09-30) : le total, les pastilles
/// des cartes qui peuvent signer, une tuile par actif, « LATELY » (Main) ou les actions de la carte (B3), puis Send /
/// Receive / Move depuis ce tiroir.
///
/// Écarts avec la maquette (DESIGN_NOTES §12) : l'adresse et « Receive » sont ajoutés (demande de Barth) ;
/// tout ce qui est Grow (tuile « XOXNO · GROWING », « Plant … more », « +$3.51/mo », bouton Grow) est masqué tant que
/// Grow n'existe pas ; « Give this card away » (G4) aussi, session à part.
struct DrawerDetailView: View {
    @Bindable var model: DrawerDetailModel
    let activity: ActivityViewModel
    var actions: DrawerDetailActions

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
                async let wallet: Void = model.refresh()
                async let history: Void = activity.refresh()
                _ = await (wallet, history)
            }
            if !model.isMissing { bottomBar }
        }
        .background(Color(.chimpBackground))
        .task { await activity.refresh() }
        .activityReceiptSheet(model: activity, onPayAgain: actions.onPayAgain)
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

            if content.isEmpty {
                ChimpySays(text: emptyText, pose: .banana)
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
                }
                .padding(.top, ChimpSpacing.xl)
            }
        }
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
            ? "Main is empty. Tap Receive to get your first bananas."
            : "\(model.cardName)'s wallet is empty. Tap Receive or Move to fill it."
    }

    // MARK: Cette carte

    private var cardRows: [ChimpGroupedRow] {
        [
            ChimpGroupedRow(id: "rename", title: "Rename & colour") { renameModel = model.makeRenameModel() },
            ChimpGroupedRow(id: "remove", title: "Remove from account") { openRemoval(.remove) },
            ChimpGroupedRow(id: "lost", title: "I lost this card", tone: .destructive) { openRemoval(.lost) },
        ]
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
            ChimpButton("Receive", kind: .secondary, size: .compact) { actions.onReceive(id) }
                .disabled(model.content == nil)
            ChimpButton("Move", kind: .secondary, size: .compact) { actions.onMove(id) }
                .disabled(isEmpty)
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
    /// Recevoir, sur ce tiroir.
    var onReceive: (String) -> Void = { _ in }
    /// Move, depuis ce tiroir.
    var onMove: (String) -> Void = { _ in }
    /// « Pay again » d'un reçu.
    var onPayAgain: (String) -> Void = { _ in }
    /// Paiement en attente touché dans l'historique.
    var onPending: () -> Void = {}
    /// « All activity » (B2r) : l'onglet Activity, filtré sur ce tiroir (adresse).
    var onAllActivity: (String) -> Void = { _ in }
    /// G6 (retirer) ou G7 (carte perdue) pour cette carte (clé).
    var onRemove: (RemoveCardModel.Mode, String) -> Void = { _, _ in }
    /// G5 « Add a card ».
    var onAddCard: () -> Void = {}
}
