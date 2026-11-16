import SwiftUI

/// B1 · page d'un tiroir (maquette « Chimp Main & Card v2 », 2026-11-12) : Main ou le wallet d'une carte. Un bandeau
/// illustré (Chimpy dans son hamac pour Main, Chimpy et la carte pour une carte), le panneau du total avec sa barre
/// « ready » / « growing », quatre tuiles d'action, puis les listes N1b (« Ready to spend », « Growing », « This card »).
///
/// Écarts avec la maquette (DESIGN_NOTES §14) : l'adresse copiable est dans le panneau (décision de Barth du
/// 2026-11-12) ; toute la page défile (le bandeau part avec), pour « tirer pour rafraîchir » et les grandes tailles de
/// texte ; le bouton retour est celui de l'app ; « Change PIN » est gardé dans « This card » ; « Give this card away »
/// (G4) reste masqué ; l'avertissement du vault est le bloc complet de l'app (principe 6) ; les stablebonds (CETES)
/// sont dans « Growing ».
struct DrawerDetailView: View {
    /// Swap éteint sur ce réseau : pas de tuile.
    @Environment(\.chimpFeatures) private var features
    @Bindable var model: DrawerDetailModel
    var actions: DrawerDetailActions
    /// Les positions du vault, lues par l'onglet Grow (une par tiroir). `nil` : Grow éteint sur ce réseau.
    var grow: GrowModel?

    @Environment(\.locale) private var locale

    @State private var renameModel: SettingsModel?
    /// G5 : le compte n'a qu'une carte (dernière lecture) ; retirer ou déclarer perdue est refusé avant tout tap.
    @State private var lastCardMode: RemoveCardModel.Mode?
    /// Distance tirée (rafraîchir) : seul le fond la lit.
    @State private var pull = ChimpPull()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpDrawerBanner(scene: scene, title: title, onBack: actions.onBack)
                        .onGeometryChange(for: CGFloat.self) { max(0, $0.frame(in: .global).minY) } action: { pull.distance = $0 }
                    page
                }
                .frame(minHeight: proxy.size.height + proxy.safeAreaInsets.top, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                ChimpSoundPlayer.shared.play(.branch)
                async let wallet: Void = model.refresh()
                async let vault: Void? = grow?.refresh()
                _ = await (wallet, vault)
            }
            .background(alignment: .top) {
                ChimpPullBackground(pull: pull, color: scene.banner, patternOpacity: 0.14)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(.chimpBackground))
        .task { await grow?.refresh() }
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

    @ViewBuilder
    private var page: some View {
        if model.isMissing {
            ChimpySays(text: "This card isn't on your account anymore.", pose: .crawl)
                .padding(.horizontal, ChimpSpacing.screenMargin)
                .padding(.top, ChimpSpacing.xl)
        } else if let content = model.content, let money = model.money {
            let split = split(content, money: money)
            ChimpSplitPanel(
                kind: kind, total: split.total, ready: split.ready, growing: split.growing,
                readyWeight: split.readyWeight, growingWeight: split.growingWeight,
                address: content.address.map(Self.shortAddress), isCopied: model.isCopied, onCopy: model.copyAddress
            )
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.top, -ChimpDrawerBanner.panelOverlap)

            if model.wallet.isShowingStaleData {
                ChimpNoticeBanner(text: "Couldn't refresh. Showing the last balances.", marker: .error)
                    .padding(.horizontal, ChimpSpacing.screenMargin)
                    .padding(.top, ChimpSpacing.l)
            }

            tiles(isEmpty: content.isEmpty)
                .padding(.horizontal, ChimpSpacing.screenMargin)
                .padding(.top, ChimpSpacing.l)

            VStack(alignment: .leading, spacing: ChimpSpacing.listGap) {
                ready(content, split: split)
                growing(content, split: split)
                if !model.isMain {
                    ChimpDrawerListTitle(title: "This card")
                        .padding(.top, ChimpSpacing.m)
                    ChimpGroupedList(rows: cardRows)
                }
            }
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.top, ChimpSpacing.xl)
            .padding(.bottom, 40)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, ChimpSpacing.xl)
        }
    }

    // MARK: En-tête

    /// Une carte pas encore lue (premier chargement) : bandeau sans scène ni titre, plutôt qu'une carte « Card » factice.
    private var scene: ChimpDrawerScene {
        if model.isMain { return .main }
        guard let card = model.card else { return .blank }
        return .card(name: model.cardName, color: model.cardColor, number: card.number)
    }

    private var title: Text {
        if model.isMain { return Text("Main") }
        return model.card == nil ? Text(verbatim: "") : Text("\(model.cardName) card")
    }

    /// « MAIN · SHARED », « N°0421 · ONLY THIS CARD SIGNS ».
    private var kind: String {
        let text = model.isMain
            ? String(localized: "Main · Shared")
            : String(localized: "N°\(model.card?.number ?? "····") · Only this card signs")
        return text.uppercased()
    }

    // MARK: Panneau

    private func split(_ content: DrawerDetailContent, money: DisplayMoney) -> DrawerDetailModel.Split {
        var parts: [DrawerDetailModel.GrowingPart] = []
        if let holding = holding(content) {
            let asset = grow?.vault?.asset ?? .xlm
            parts.append(DrawerDetailModel.GrowingPart(
                value: money.value([AssetAmount(code: asset.code, amount: holding.value)]),
                fallback: asset.displayedWithCode(holding.value, locale: locale)
            ))
        }
        for bond in model.savingsAssets {
            // Le prix lu par le Wallet d'abord (il couvre CETES, USDY, SolvBTC, xSolvBTC) : `grow` ne connaît que les
            // stablebonds de son service, et un seul prix manquant faisait retomber tout le panneau sur les quantités.
            let value = money.value([AssetAmount(code: bond.code, amount: bond.amount)])
                ?? grow?.savingsPrice(bond.code).flatMap { money.value(usd: $0.value(of: bond.amount)) }
            parts.append(DrawerDetailModel.GrowingPart(
                value: value,
                fallback: SendAsset(code: bond.code)?.displayedWithCode(bond.amount, locale: locale) ?? "\(bond.amount) \(bond.code)"
            ))
        }
        return DrawerDetailModel.split(ready: model.readyAssets, growing: parts, money: money)
    }

    // MARK: Actions

    private func tiles(isEmpty: Bool) -> some View {
        let id = model.selection.drawerID
        return HStack(spacing: ChimpSize.keypadSpacing) {
            ChimpActionTile(title: "Send", systemImage: "arrow.up.right", isPrimary: true) { actions.onSend(id) }
                .disabled(isEmpty)
            ChimpActionTile(title: "Move", systemImage: "arrow.up.arrow.down") { actions.onMove(id) }
                .disabled(isEmpty)
            if features.swap {
                ChimpActionTile(title: "Swap", systemImage: "arrow.left.arrow.right") { actions.onSwap(id) }
                    .disabled(isEmpty)
            }
            if grow != nil {
                ChimpActionTile(title: "Grow", systemImage: "leaf", image: .tileBanana) { actions.onGrow(id) }
                    .disabled(isEmpty)
            }
        }
    }

    // MARK: Ready to spend

    @ViewBuilder
    private func ready(_ content: DrawerDetailContent, split: DrawerDetailModel.Split) -> some View {
        if content.isEmpty && holding(content) == nil {
            ChimpySays(text: emptyText, pose: .plant)
        } else if !content.assets.isEmpty {
            ChimpDrawerListTitle(title: "Ready to spend", amount: split.readyTotal)
            ForEach(content.assets) { asset in
                let known = SendAsset(code: asset.code)
                ChimpHoldingRow(name: Self.assetName(asset.code), detail: asset.amount, amount: asset.value ?? asset.amount) {
                    if let known {
                        ChimpAssetIcon(glyph: known.glyph, size: 38)
                    } else {
                        Image(.tileLogo).resizable().scaledToFit()
                    }
                }
            }
        }
    }

    /// « US Dollar », « Stellar » (maquette N1b) ; les autres actifs par leur code.
    static func assetName(_ code: String) -> String {
        switch code {
        case "USDC": String(localized: "US Dollar")
        case "XLM": String(localized: "Stellar")
        default: code
        }
    }

    // MARK: Growing

    private func holding(_ content: DrawerDetailContent) -> VaultHolding? {
        content.address.flatMap { grow?.holding(drawerAddress: $0) }
    }

    @ViewBuilder
    private func growing(_ content: DrawerDetailContent, split: DrawerDetailModel.Split) -> some View {
        let holding = holding(content)
        if holding != nil || !content.savings.isEmpty {
            ChimpDrawerListTitle(title: "Growing", amount: split.growingTotal, tint: Color(.chimpPositive))
                .padding(.top, ChimpSpacing.m)
            if let holding {
                Button { actions.onPosition(holding.drawerAddress) } label: { vaultRow(holding) }
                    .buttonStyle(ChimpPressableStyle())
                    .accessibilityHint(Text("Opens your position"))
            }
            ForEach(content.savings) { bond in
                Button { if let address = content.address { actions.onSavings(address, bond.code) } } label: {
                    savingsRow(bond, address: content.address)
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityHint(Text("Opens your savings bonds"))
            }
            if holding != nil, let vault = grow?.vault {
                ChimpVaultNotice(asset: vault.asset.code, protocols: vault.protocols)
            }
        }
    }

    /// « XLM vault », « +0.48 XLM since 22 Sep » (vert, rouge si ça a baissé ; le nom du protocole si la base n'est pas
    /// connue), « 2,000.48 XLM ».
    private func vaultRow(_ holding: VaultHolding) -> some View {
        let asset = grow?.vault?.asset ?? .xlm
        let runner = grow?.vault?.protocols.first ?? "DeFindex"
        let change = holding.change.flatMap { change in
            holding.basis.map { basis in
                String(localized: "\(GrowView.changeText(change, asset: asset, locale: locale)) since \(basis.since.formatted(.dateTime.day().month(.abbreviated)))")
            }
        }
        return ChimpHoldingRow(
            name: String(localized: "\(asset.code) vault"),
            detail: change ?? runner,
            detailColor: change == nil ? Color(.chimpTextSecondary) : (holding.change ?? 0) < 0 ? Color(.chimpNegative) : Color(.chimpPositive),
            amount: asset.displayedWithCode(holding.value, locale: locale)
        ) {
            ChimpProtocolLogo(mark: .defindex, size: 38)
        }
    }

    /// Un stablebond (décision de Barth du 2026-10-15, construit comme le vault) : « CETES », puis « Price +0.62% since
    /// 22 Sep » si la base est connue, sinon « ≈ 99.58 USDC » au prix d'Etherfuse, sinon l'émetteur ; gelés : « Frozen by
    /// Etherfuse » en rouge.
    private func savingsRow(_ bond: DrawerDetailContent.Asset, address: String?) -> some View {
        let asset = SendAsset(code: bond.code) ?? .cetes
        let holding = address.flatMap { grow?.savingsHolding(drawerAddress: $0, code: bond.code) }
        let price = grow?.savingsPrice(bond.code)
        let issuer = asset.issuerName ?? String(localized: "The issuer")
        let detail: String
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
            detail = issuer
        }
        return ChimpHoldingRow(name: asset.code, detail: detail, detailColor: color, amount: bond.amount) {
            ChimpAssetIcon(glyph: asset.glyph, size: 38)
        }
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
    /// Changer le PIN de cette carte (clé).
    var onChangePIN: (String) -> Void = { _ in }
    /// G6 (retirer) ou G7 (carte perdue) pour cette carte (clé).
    var onRemove: (RemoveCardModel.Mode, String) -> Void = { _, _ in }
    /// G5 « Add a card ».
    var onAddCard: () -> Void = {}
    /// Grow : mettre dans le vault depuis ce tiroir (identifiant).
    var onGrow: (String) -> Void = { _ in }
    /// La ligne du vault : F6 pour ce tiroir (adresse).
    var onPosition: (String) -> Void = { _ in }
    /// La ligne d'un actif d'émetteur (adresse du tiroir, code de l'actif) : son pot.
    var onSavings: (String, String) -> Void = { _, _ in }
}
