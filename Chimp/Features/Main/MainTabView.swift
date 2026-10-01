import SwiftUI

/// Coque de l'app : onglets Wallet / Grow / Activity et barre d'onglets du design system.
/// Chaque onglet a sa propre pile de navigation pour les écrans à venir. La barre d'onglets
/// appartient à l'écran racine de chaque onglet : les écrans poussés la recouvrent
/// (DESIGN_NOTES §8.1 : les flux d'action s'ouvrent sans barre d'onglets).
struct MainTabView: View {
    @State private var selection = ChimpTab.wallet
    /// Gardé ici pour que les soldes restent chargés quand on change d'onglet.
    @State private var walletModel: WalletViewModel
    private let session: AppSession
    private let config: ChimpNetworkConfig
    /// Écrans poussés dans l'onglet Wallet.
    @State private var walletPath: [WalletRoute] = []
    /// Gardé ici pour que l'historique reste affiché quand on change d'onglet.
    @State private var activityModel: ActivityViewModel
    /// Écran d'état d'un paiement en attente, ouvert depuis l'Activity.
    @State private var isShowingPendingSend = false
    /// « Pay again » ou « Send back » depuis un reçu de l'Activity : Envoyer prérempli.
    @State private var prefilledSend: SendPrefill?
    #if DESIGN_CATALOG
    @State private var isShowingCatalog = false
    #endif

    /// Le vrai Wallet : soldes lus sur le réseau de l'app (testnet), prix du XLM par l'oracle de mainnet.
    init(session: AppSession, config: ChimpNetworkConfig = .testnet) {
        self.session = session
        self.config = config
        let wallet = WalletViewModel(dataSource: ChainWalletDataSource(
            session: session, chain: ChainWalletReader(config: config), oracle: ReflectorPriceOracle()
        ))
        _walletModel = State(initialValue: wallet)
        // L'historique : téléphone + RPC de testnet ; les cartes lues par le Wallet complètent celles du téléphone.
        _activityModel = State(initialValue: ActivityViewModel(source: ChainActivityDataSource(
            session: session, config: config, walletCards: { [weak wallet] in wallet?.cards ?? [] }
        )))
    }

    var body: some View {
        switch selection {
        case .wallet:
            NavigationStack(path: $walletPath) {
                WalletView(
                    model: walletModel, onSettings: settingsAction, onAction: openWalletAction,
                    onAddCard: { walletPath.append(.addCard) }, onOpenDrawer: { walletPath.append(.drawer($0)) }
                )
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(for: WalletRoute.self) { route in
                        switch route {
                        case .receive(let drawerID):
                            ReceiveDestination(session: session, initialDrawerID: drawerID)
                        case .send(let drawerID):
                            // Le vrai envoi (testnet) ; au retour, les soldes du Wallet sont relus.
                            SendFlowRoot(service: ChainSendService(session: session), fromDrawerID: drawerID, onExit: closeFlow)
                        case .move(let drawerID):
                            // E1 : le même parcours, entre ses propres tiroirs (testnet).
                            SendFlowRoot(service: ChainSendService(session: session), kind: .move, fromDrawerID: drawerID, onExit: closeFlow)
                        case .prefilledSend(let prefill):
                            // « Pay again » ou « Send back » d'un reçu ouvert depuis la page d'un tiroir.
                            SendFlowRoot(service: ChainSendService(session: session), prefill: prefill, onExit: closeFlow)
                        case .pendingSend:
                            // Envoyer rouvre l'état du paiement en attente (« Check again »), jamais un nouvel envoi.
                            SendFlowRoot(service: ChainSendService(session: session), onExit: closeFlow)
                        case .removeCard(let mode, let key):
                            // G6 / G7 : retirer une carte ou la déclarer perdue (testnet), depuis sa page (B3).
                            RemoveCardDestination(mode: mode, key: key, wallet: walletModel, session: session) { removed in
                                if removed {
                                    walletPath.removeAll()
                                    Task { await walletModel.refresh() }
                                    Task { await activityModel.refresh() }
                                } else if !walletPath.isEmpty {
                                    walletPath.removeLast()
                                }
                            } onAddCard: {
                                walletPath = [.addCard]
                            } onMoveFirst: {
                                walletPath.append(.move(key))
                            }
                        case .changePIN(let key):
                            // Changer le PIN d'une Infineon, depuis sa page (B3).
                            ChangePINDestination(key: key, wallet: walletModel, session: session) {
                                if !walletPath.isEmpty { walletPath.removeLast() }
                            }
                        case .drawer(let selection):
                            // B2 / B3 : le détail d'un tiroir, sur les soldes déjà lus par le Wallet.
                            DrawerDestination(selection: selection, wallet: walletModel, activity: activityModel, session: session, actions: drawerActions)
                        case .addCard:
                            // G1 → G3 : ajouter une carte au compte (testnet) ; au retour, le Wallet relit ses cartes.
                            AddCardDestination(session: session) {
                                walletPath.removeAll()
                                Task { await walletModel.refresh() }
                            }
                        case .settings:
                            // I2 : au retour, le Wallet relit les noms et couleurs des cartes.
                            SettingsDestination(
                                session: session, walletCards: walletModel.cards, walletTotal: walletModel.content?.total,
                                config: config, onDeveloper: developerAction
                            ) {
                                walletPath.removeAll()
                                Task { await walletModel.refresh() }
                            }
                        }
                    }
                #if DESIGN_CATALOG
                    .navigationDestination(isPresented: $isShowingCatalog) {
                        DesignSystemCatalogView()
                    }
                #endif
            }
        case .activity:
            NavigationStack {
                ActivityView(model: activityModel, onPending: { isShowingPendingSend = true }, onSendPrefilled: { prefilledSend = $0 })
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(isPresented: $isShowingPendingSend) {
                        // Envoyer rouvre l'état du paiement en attente (« Check again »), jamais un nouvel envoi.
                        SendFlowRoot(service: ChainSendService(session: session)) {
                            isShowingPendingSend = false
                            Task { await activityModel.refresh() }
                        }
                    }
                    .navigationDestination(item: $prefilledSend) { prefill in
                        SendFlowRoot(service: ChainSendService(session: session), prefill: prefill) {
                            prefilledSend = nil
                            Task { await activityModel.refresh() }
                        }
                    }
            }
        case .grow:
            NavigationStack {
                PlaceholderTabView(tab: selection)
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
            }
        }
    }

    private func openWalletAction(_ action: WalletAction) {
        switch action {
        case .receive:
            walletPath.append(.receive(nil))
        case .send:
            walletPath.append(.send(nil))
        case .move:
            walletPath.append(.move(nil))
        case .swap:
            // TODO(jalon 4b) : Swap (E3), selon le périmètre V1.
            break
        }
    }

    /// Fin d'un parcours (Send, Move…) : retour à la page du tiroir d'où il est parti, sinon au Wallet ; soldes et
    /// historique relus.
    private func closeFlow() {
        if let index = walletPath.lastIndex(where: { if case .drawer = $0 { true } else { false } }) {
            walletPath.removeSubrange((index + 1)...)
        } else {
            walletPath.removeAll()
        }
        Task { await walletModel.refresh() }
        Task { await activityModel.refresh() }
    }

    /// Actions de la page d'un tiroir (B2, B3) : chacune part de ce tiroir.
    private var drawerActions: DrawerDetailActions {
        DrawerDetailActions(
            onBack: {
                if !walletPath.isEmpty { walletPath.removeLast() }
            },
            onSend: { walletPath.append(.send($0)) },
            onReceive: { walletPath.append(.receive($0)) },
            onMove: { walletPath.append(.move($0)) },
            onSendPrefilled: { walletPath.append(.prefilledSend($0)) },
            onPending: { walletPath.append(.pendingSend) },
            onAllActivity: { address in
                activityModel.filter = .drawer(address)
                selection = .activity
            },
            onChangePIN: { walletPath.append(.changePIN($0)) },
            onRemove: { walletPath.append(.removeCard($0, $1)) },
            onAddCard: { walletPath = [.addCard] }
        )
    }

    /// Roue dentée : les réglages (I2).
    private var settingsAction: (() -> Void)? {
        { walletPath.append(.settings) }
    }

    /// Réglages, section « Developer » (Debug et Testing seulement) : le catalogue et le mode admin.
    private var developerAction: (() -> Void)? {
        #if DESIGN_CATALOG
        return { isShowingCatalog = true }
        #else
        return nil
        #endif
    }
}

/// Écrans qu'on peut pousser depuis le Wallet.
enum WalletRoute: Hashable {
    /// Recevoir, sur un tiroir choisi d'avance (identifiant) ou sur Main.
    case receive(String?)
    /// Envoyer, depuis un tiroir choisi d'avance ou depuis Main.
    case send(String?)
    /// Move, depuis un tiroir choisi d'avance ou depuis Main.
    case move(String?)
    /// « Pay again » ou « Send back » d'un reçu.
    case prefilledSend(SendPrefill)
    case pendingSend
    case settings
    case addCard
    case drawer(DrawerSelection)
    /// G6 (retirer) ou G7 (carte perdue), pour la carte de cette clé.
    case removeCard(RemoveCardModel.Mode, String)
    /// Changer le PIN de la carte de cette clé.
    case changePIN(String)
}

/// Recevoir (D1) poussé depuis le Wallet : un ViewModel neuf à chaque ouverture, gardé tant que l'écran est affiché.
private struct ReceiveDestination: View {
    @State private var model: ReceiveViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: AppSession, initialDrawerID: String? = nil) {
        _model = State(initialValue: ReceiveViewModel(dataSource: LocalReceiveDataSource(session: session), initialDrawerID: initialDrawerID))
    }

    var body: some View {
        ReceiveView(model: model, onBack: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Détail d'un tiroir (B2, B3) : un ViewModel neuf à chaque ouverture, sur les soldes du Wallet.
private struct DrawerDestination: View {
    @State private var model: DrawerDetailModel
    let activity: ActivityViewModel
    let actions: DrawerDetailActions

    init(selection: DrawerSelection, wallet: WalletViewModel, activity: ActivityViewModel, session: AppSession, actions: DrawerDetailActions) {
        _model = State(initialValue: DrawerDetailModel(selection: selection, wallet: wallet, session: session))
        self.activity = activity
        self.actions = actions
    }

    var body: some View {
        DrawerDetailView(model: model, activity: activity, actions: actions)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Retirer une carte (G6) ou la déclarer perdue (G7) : un ViewModel neuf à chaque ouverture, sur les montants lus par
/// le Wallet. Carte que le Wallet ne connaît plus : rien (retour).
private struct RemoveCardDestination: View {
    @State private var model: RemoveCardModel?
    let onExit: (Bool) -> Void
    let onAddCard: () -> Void
    let onMoveFirst: () -> Void

    init(mode: RemoveCardModel.Mode, key: String, wallet: WalletViewModel, session: AppSession,
         onExit: @escaping (Bool) -> Void, onAddCard: @escaping () -> Void, onMoveFirst: @escaping () -> Void) {
        let drawer = DrawerDetailModel(selection: .card(key), wallet: wallet, session: session)
        _model = State(initialValue: zip2(drawer.removalTarget, session.wallet.account?.address).map { target, account in
            RemoveCardModel.live(mode: mode, account: account, target: target, members: drawer.memberKeys, session: session)
        })
        self.onExit = onExit
        self.onAddCard = onAddCard
        self.onMoveFirst = onMoveFirst
    }

    var body: some View {
        Group {
            if let model {
                RemoveCardFlowView(model: model, onExit: onExit, onAddCard: onAddCard, onMoveFirst: onMoveFirst)
            } else {
                ChimpySays(text: "This card isn't on your account anymore.", pose: .crawl)
                    .padding(ChimpSpacing.xxl)
                    .onAppear { onExit(false) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Changer le PIN, depuis la page d'une carte. Carte inconnue ou DUOX : rien (retour).
private struct ChangePINDestination: View {
    let card: PINCard?
    let onExit: () -> Void

    init(key: String, wallet: WalletViewModel, session: AppSession, onExit: @escaping () -> Void) {
        card = DrawerDetailModel(selection: .card(key), wallet: wallet, session: session).pinCard
        self.onExit = onExit
    }

    var body: some View {
        if let card {
            ChangePINScreen(card: card, onExit: onExit)
        } else {
            Color(.chimpBackground).onAppear(perform: onExit)
        }
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

/// Ajouter une carte (G1 → G3) : un ViewModel neuf à chaque ouverture, sur la vraie carte et le testnet. Sur un appareil
/// sans NFC (simulateur), les builds Debug et Testing prennent une carte et une chaîne factices.
private struct AddCardDestination: View {
    @State private var model: AddCardModel?
    let onExit: () -> Void

    init(session: AppSession, onExit: @escaping () -> Void) {
        _model = State(initialValue: session.wallet.account.map { AddCardModel.live(account: $0.address, session: session) })
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if let model {
                AddCardFlowView(model: model, onExit: onExit)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Réglages (I2) poussés depuis le Wallet : un ViewModel neuf à chaque ouverture.
private struct SettingsDestination: View {
    @State private var model: SettingsModel
    let onDeveloper: (() -> Void)?
    let onExit: () -> Void

    init(
        session: AppSession, walletCards: [CardBalance], walletTotal: String?, config: ChimpNetworkConfig,
        onDeveloper: (() -> Void)?, onExit: @escaping () -> Void
    ) {
        let summaries = ChainAccountSummaryReader(wallet: ChainWalletDataSource(
            session: session, chain: ChainWalletReader(config: config), oracle: ReflectorPriceOracle()
        ))
        _model = State(initialValue: SettingsModel(
            session: session, walletCards: walletCards, walletTotal: walletTotal, summaries: summaries
        ))
        self.onDeveloper = onDeveloper
        self.onExit = onExit
    }

    var body: some View {
        SettingsView(model: model, onBack: onExit, onDeveloper: onDeveloper)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Onglet pas encore construit (Grow) : en-tête seul.
struct PlaceholderTabView: View {
    let tab: ChimpTab

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: tab.title)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.chimpBackground))
    }
}

private extension View {
    /// Pose la barre d'onglets en bas de l'écran racine d'un onglet ; le contenu défilant en tient compte.
    func withTabBar(_ selection: Binding<ChimpTab>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpTabBar(selection: selection)
        }
    }
}

#Preview {
    MainTabView(session: AppSession(store: InMemoryLocalWalletStore(), network: .testnet))
}
