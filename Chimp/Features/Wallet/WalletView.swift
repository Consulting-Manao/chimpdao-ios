import SwiftUI

/// Écran Wallet (B1) : total, tuiles d'action, Main, cartes. Uniquement des composants du design system.
///
/// États : chargement (squelette), soldes, solde à zéro, aucune carte, erreur réseau
/// (sans données : message + « Try again » ; avec des soldes plus anciens : bandeau + « Retry »).
struct WalletView: View {
    let model: WalletViewModel
    /// Roue dentée affichée seulement si une action est fournie.
    var onSettings: (() -> Void)?
    /// Tuile d'action touchée (Send, Receive…) : la navigation est décidée par la coque (`MainTabView`).
    var onAction: (WalletAction) -> Void = { _ in }
    /// « + Add » (G1) : ajouter une carte au compte.
    var onAddCard: () -> Void = {}
    /// Main ou une carte touchée : son détail (B2, B3).
    var onOpenDrawer: (DrawerSelection) -> Void = { _ in }

    var body: some View {
        // Le défilement passe sous la barre d'état : l'en-tête comble lui-même la zone sûre du haut,
        // pour que son fond et son motif montent sans coupure (voir ChimpBalanceHeader).
        GeometryReader { proxy in
            scrollView(topSafeArea: proxy.safeAreaInsets.top)
        }
        .background(Color(.chimpBackground))
        .task { await model.loadIfNeeded() }
    }

    private func scrollView(topSafeArea: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(topSafeArea: topSafeArea)
                VStack(alignment: .leading, spacing: 0) {
                    switch model.phase {
                    case .failed:
                        failure
                    case .loading, .loaded:
                        balances(model.content ?? .placeholder)
                            .redacted(reason: model.content == nil ? .placeholder : [])
                            .accessibilityHidden(model.content == nil)
                    }
                }
                .padding(.horizontal, ChimpSpacing.screenMargin)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, ChimpSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.chimpBackground))
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await model.refresh() }
        // Tiré vers le bas, le haut de l'écran garde la couleur de l'en-tête.
        .background(alignment: .top) {
            Color(.chimpHeader).frame(height: 320)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: En-tête

    private func header(topSafeArea: CGFloat) -> some View {
        let content = model.content
        return ChimpBalanceHeader(
            firstName: model.firstName,
            label: "Your whole banana pile",
            total: content?.total ?? "—",
            change: content?.weeklyChange.map { "\($0) this week" },
            onSettings: onSettings,
            topSafeArea: topSafeArea
        )
        .redacted(reason: model.phase == .loading ? .placeholder : [])
    }

    // MARK: Soldes

    private func balances(_ content: WalletContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isShowingStaleData {
                ChimpNoticeBanner(
                    text: "Couldn't refresh. Balances from \(content.updatedAt.formatted(date: .omitted, time: .shortened)).",
                    marker: .error
                ) {
                    ChimpPillButton("Retry") {
                        Task { await model.refresh() }
                    }
                }
                .padding(.bottom, ChimpSpacing.l)
            }

            if content.isShowingAssetAmounts {
                // État absent de la maquette (décision du 2026-09-29) : pas de total partiel en dollars.
                ChimpNoticeBanner(text: "Prices are unavailable right now, so amounts are shown per asset.")
                    .padding(.bottom, ChimpSpacing.l)
            }

            HStack(spacing: ChimpSize.keypadSpacing) {
                ForEach(model.availableActions) { action in
                    ChimpActionTile(
                        title: action.title,
                        systemImage: action.systemImage,
                        isPrimary: action == .send
                    ) {
                        onAction(action)
                    }
                    .disabled(!model.isEnabled(action))
                }
            }

            if content.isZeroBalance {
                ChimpySays(text: "Your jungle is empty. Tap Receive to get your first bananas.", pose: .wave)
                    .padding(.top, ChimpSpacing.l)
            }

            ChimpDrawerCard(
                label: "Main",
                amount: content.mainAmount,
                ready: content.mainReady,
                growing: content.mainGrowing
            ) {
                if model.content != nil { onOpenDrawer(.main) }
            }
            .chimpCascadeAppear(index: 0)
            .padding(.top, ChimpSpacing.l)

            HStack(alignment: .firstTextBaseline) {
                Text("My cards")
                    .chimpFont(.displayS)
                    .foregroundStyle(.chimpTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                ChimpPillButton("+ Add", action: onAddCard)
                    .disabled(model.phase != .loaded)
            }
            .padding(.top, ChimpSpacing.xl)

            cards(content.cards, perAsset: content.isShowingAssetAmounts)
                .padding(.top, 11)
        }
    }

    @ViewBuilder
    private func cards(_ cards: [WalletContent.Card], perAsset: Bool) -> some View {
        if cards.isEmpty {
            // Filet de sécurité : d'après le contrat, un compte a toujours au moins une carte.
            Text("No card here yet")
                .chimpFont(.buttonSecondary)
                .foregroundStyle(.chimpTextSecondary)
                .frame(maxWidth: .infinity)
                .aspectRatio(ChimpSize.cardAspectRatio * 2, contentMode: .fit)
                .background {
                    RoundedRectangle(cornerRadius: ChimpRadius.chimpCard)
                        .strokeBorder(Color(.chimpOutline), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [8, 6]))
                }
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: ChimpSpacing.m), GridItem(.flexible(), spacing: ChimpSpacing.m)],
                spacing: ChimpSpacing.m
            ) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    Button {
                        if model.content != nil { onOpenDrawer(.card(card.id)) }
                    } label: {
                        // Montants par actif (« 12.5 XLM · 100 USDC ») : « on card » laisse la place au montant.
                        ChimpCard(name: card.name, color: card.color, number: card.number, amount: card.amount, subtitle: perAsset ? nil : "on card")
                    }
                    .buttonStyle(ChimpBouncyPressStyle())
                    .chimpCascadeAppear(index: index + 1)
                }
            }
        }
    }

    // MARK: Erreur

    private var failure: some View {
        VStack(spacing: ChimpSpacing.xl) {
            ChimpySays(text: "I can't reach the jungle right now. Check your connection.", pose: .crawl)
            ChimpButton("Try again") {
                Task { await model.refresh() }
            }
        }
        .padding(.top, ChimpSpacing.s)
    }
}

extension WalletAction {
    var title: LocalizedStringKey {
        switch self {
        case .send: "Send"
        case .receive: "Receive"
        case .move: "Move"
        case .swap: "Swap"
        }
    }

    var systemImage: String {
        switch self {
        case .send: "arrow.up.right"
        case .receive: "arrow.down.left"
        case .move: "arrow.up.arrow.down"
        case .swap: "arrow.left.arrow.right"
        }
    }
}

#Preview("Maquette") {
    NavigationStack {
        WalletView(model: WalletViewModel(dataSource: MockWalletDataSource()), onSettings: {})
    }
}

#Preview("Erreur · sombre") {
    NavigationStack {
        WalletView(model: WalletViewModel(dataSource: MockWalletDataSource(scenario: .networkError)))
    }
    .preferredColorScheme(.dark)
}
