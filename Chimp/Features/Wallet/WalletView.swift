import SwiftUI

/// Écran Wallet (B1) : total, tuiles d'action, Main, cartes. Uniquement des composants du design system.
///
/// États : chargement (squelette), soldes, solde à zéro, aucune carte, erreur réseau
/// (sans données : message + « Try again » ; avec des soldes plus anciens : bandeau + « Retry »).
struct WalletView: View {
    /// Swap éteint sur ce réseau : pas de tuile.
    @Environment(\.chimpFeatures) private var features
    /// Testnet : bandeau permanent « TESTNET » (Chimp Test sur l'App Store).
    @Environment(\.chimpNetwork) private var network
    let model: WalletViewModel
    /// Roue dentée affichée seulement si une action est fournie.
    var onSettings: (() -> Void)?
    /// Tuile d'action touchée (Send, Receive…) : la navigation est décidée par la coque (`MainTabView`).
    var onAction: (WalletAction) -> Void = { _ in }
    /// « + Add » (G1) : ajouter une carte au compte.
    var onAddCard: () -> Void = {}
    /// Main ou une carte touchée : son détail (B2, B3).
    var onOpenDrawer: (DrawerSelection) -> Void = { _ in }
    /// « Add money » (D4, sans maquette) : affiché seulement si une action est fournie.
    var onAddMoney: (() -> Void)?

    /// De combien l'en-tête est tiré vers le bas (« tirer pour rafraîchir »).
    @State private var pull = WalletPull()

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
                    // Seulement quand on tire vers le bas : 0 au repos et pendant le défilement normal (aucune mise à jour).
                    .onGeometryChange(for: CGFloat.self) { max(0, $0.frame(in: .global).minY) } action: { pull.distance = $0 }
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
        .refreshable {
            // Tirer pour rafraîchir : on secoue la branche.
            ChimpSoundPlayer.shared.play(.branch)
            await model.refresh()
        }
        // Tiré vers le bas, le haut de l'écran garde la couleur et le motif de l'en-tête (retour de Barth, 2026-10-02).
        .background(alignment: .top) {
            WalletPullBackground(pull: pull)
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
            if network == .testnet {
                ChimpTestnetBanner()
                    // Lisible même pendant le chargement (le reste est en squelette).
                    .unredacted()
                    .padding(.bottom, ChimpSpacing.l)
            }
            if let problem = model.securityProblem {
                ChimpNoticeBanner(text: LocalizedStringKey(problem), marker: .error)
                    .padding(.bottom, ChimpSpacing.m)
            } else if model.isShowingStaleData {
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

            // Chimp Test (quantités seulement) : ce n'est pas une panne de prix, pas de bandeau.
            if content.isShowingAssetAmounts && AmountDisplay.showsDollars {
                // État absent de la maquette (décision du 2026-09-29) : pas de total partiel en dollars.
                ChimpNoticeBanner(text: "Prices are unavailable right now, so amounts are shown per asset.")
                    .padding(.bottom, ChimpSpacing.l)
            }

            HStack(spacing: ChimpSize.keypadSpacing) {
                ForEach(model.availableActions.filter { $0 != .swap || features.swap }) { action in
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

            if let onAddMoney {
                ChimpNavigationRow(title: "Add money", subtitle: "From another chain", action: onAddMoney)
                    .padding(.top, ChimpSpacing.m)
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
            if let problem = model.securityProblem {
                ChimpySays(text: LocalizedStringKey(problem), pose: .stop)
            } else {
                ChimpySays(text: "I can't reach the jungle right now. Check your connection.", pose: .crawl)
            }
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

/// Distance tirée, dans un objet à part : seul le fond la lit, le Wallet n'est pas recalculé pendant le geste.
@Observable
private final class WalletPull {
    var distance: CGFloat = 0
}

/// Fond révélé au-dessus de l'en-tête quand on tire pour rafraîchir : la couleur de l'en-tête et son motif, décalé
/// de la distance tirée pour continuer exactement celui de l'en-tête (pas de raccord visible). Derrière le défilement,
/// donc sous la roue de chargement.
private struct WalletPullBackground: View {
    let pull: WalletPull
    private let height: CGFloat = 320

    var body: some View {
        let tile = ChimpPattern.tileHeight
        Color(.chimpHeader)
            .overlay(alignment: .top) {
                ChimpPattern()
                    .frame(height: height + tile)
                    .offset(y: pull.distance.truncatingRemainder(dividingBy: tile) - tile)
            }
            .frame(height: height)
            .clipped()
    }
}
