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
    @Environment(\.scenePhase) private var scenePhase
    /// Gardé ici pour que l'historique reste affiché quand on change d'onglet.
    @State private var activityModel: ActivityViewModel
    /// Écran d'état d'un paiement en attente, ouvert depuis l'Activity.
    @State private var isShowingPendingSend = false
    /// « Pay again » ou « Send back » depuis un reçu de l'Activity : Envoyer prérempli.
    @State private var prefilledSend: SendPrefill?
    /// « Swap again » depuis un reçu de l'Activity : Swap prérempli.
    @State private var prefilledSwap: SwapPrefill?
    /// Les positions du vault, partagées par l'onglet Grow et les pages des tiroirs (tuile « GROWING »).
    @State private var growModel: GrowModel
    /// Écrans poussés dans l'onglet Grow.
    @State private var growPath: [GrowRoute] = []
    /// Cadeaux qui attendent sur les cartes du compte (carte partenaire, D5), relus avec les soldes.
    @State private var gifts: [PrizeGift] = []
    /// « Somebody likes you! » en plein écran.
    @State private var openGift: PrizeGift?
    /// Cadeaux déjà montrés tout seuls depuis le lancement (« Later » : la ligne du Wallet reste).
    @State private var shownGifts: Set<String> = []
    #if DESIGN_CATALOG
    @State private var isShowingCatalog = false
    #endif

    /// Le vrai Wallet : soldes lus sur le réseau de la session (celui de ce build), prix du XLM par l’oracle de mainnet.
    init(session: AppSession) {
        let config = session.config
        self.session = session
        self.config = config
        let wallet = WalletViewModel(dataSource: ChainWalletDataSource(
            session: session, chain: ChainWalletReader(config: config), oracle: ReflectorPriceOracle.shared,
            stablebondPrices: StablebondWalletPrices(config: config)
        ), preferences: session.preferences)
        _walletModel = State(initialValue: wallet)
        _growModel = State(initialValue: GrowModel(
            service: ChainVaultService(session: session),
            savingsService: config.features.grow && !config.issuedAssets.isEmpty ? ChainSavingsService(session: session) : nil,
            lendingService: config.features.grow && config.integrations != nil ? ChainLendingService(session: session) : nil,
            sentoraService: config.features.grow && config.integrations?.sentora != nil ? ChainSentoraService(session: session) : nil,
            solvService: config.solv != nil ? ChainSolvService(session: session) : nil,
            solvPricing: config.solv != nil ? StablebondWalletPrices(config: config) : nil,
            priceOracle: ReflectorPriceOracle.shared, history: DefaultsPotHistoryStore(),
            rateReader: XoxnoRateClient(config: config)
        ))
        // L’historique : téléphone + RPC du réseau de la session ; les cartes lues par le Wallet complètent celles du téléphone.
        _activityModel = State(initialValue: ActivityViewModel(source: ChainActivityDataSource(
            session: session, walletCards: { [weak wallet] in wallet?.cards ?? [] }
        )))
    }

    /// L'œil du Wallet (et de Grow) vaut pour tous les onglets ; les parcours qui font signer le remettent à `false`.
    var body: some View {
        tabs
            .environment(\.chimpHidesAmounts, session.preferences.hidesBalances)
            .environment(\.chimpPotRates, growModel.rates)
            // J2 : à l'ouverture de l'app (lancement ou retour), sur le Wallet seul, sans opération en attente.
            .task { checkNightOwl() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { checkNightOwl() } }
            .task { await loadGifts() }
            .fullScreenCover(item: $openGift) { gift in
                NavigationStack {
                    PrizeClaimRoot(service: ChainPrizeService(session: session), gift: gift) {
                        openGift = nil
                        refreshAll()
                    }
                }
            }
    }

    /// Les cadeaux des cartes du compte (rien si le contrat `prize` n'est pas configuré). Le premier qui n'a pas encore été
    /// montré s'ouvre tout seul, sur le Wallet seulement et sans opération en attente.
    private func loadGifts() async {
        guard ChainPrizeService.isAvailable(config) else { return }
        guard let found = try? await ChainPrizeService(session: session).gifts() else { return }
        gifts = found
        guard openGift == nil, selection == .wallet, walletPath.isEmpty, session.wallet.pendingSend == nil,
              let next = found.first(where: { !shownGifts.contains(Self.giftKey($0)) }) else { return }
        shownGifts.insert(Self.giftKey(next))
        openGift = next
    }

    /// Un cadeau montré une fois par carte et par montant : un nouveau dépôt se montre de nouveau.
    private static func giftKey(_ gift: PrizeGift) -> String {
        "\(gift.id):\(gift.amount)"
    }

    private func checkNightOwl() {
        guard selection == .wallet, walletPath.isEmpty, session.wallet.pendingSend == nil else { return }
        walletModel.openedAt(.now)
    }

    @ViewBuilder
    private var tabs: some View {
        switch selection {
        case .wallet:
            NavigationStack(path: $walletPath) {
                WalletView(
                    model: walletModel, onSettings: settingsAction, onAction: openWalletAction,
                    onAddCard: { walletPath.append(.addCard) }, onOpenDrawer: { walletPath.append(.drawer($0)) },
                    onAddMoney: config.features.addMoney && config.integrations != nil ? { walletPath.append(.addMoney) } : nil,
                    gifts: gifts, onOpenGift: { openGift = $0 }
                )
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(for: WalletRoute.self) { route in
                        switch route {
                        case .receive(let drawerID):
                            ReceiveDestination(session: session, initialDrawerID: drawerID) {
                                walletPath.append(.addMoney)
                            }
                        case .addMoney:
                            AddMoneyView(
                                onBack: { if !walletPath.isEmpty { walletPath.removeLast() } },
                                onRozo: !config.features.addMoney || config.integrations == nil || session.wallet.account == nil ? nil : { walletPath.append(.rozoTransfer) }
                            ) {
                                walletPath.append(.crossChainQuote)
                            }
                            .toolbar(.hidden, for: .navigationBar)
                        case .crossChainQuote:
                            // N1 : devis NEAR Intents seulement (aucun envoi), D4.
                            CrossChainQuoteDestination(config: config) { if !walletPath.isEmpty { walletPath.removeLast() } }
                        case .rozoTransfer:
                            // N2 : ROZO, intermédiaire de confiance (D4) ; l'arrivée apparaît ensuite dans l'Activity.
                            RozoTransferDestination(config: config, session: session, onBack: { if !walletPath.isEmpty { walletPath.removeLast() } }, onDone: closeFlow)
                        case .send(let drawerID):
                            // Le vrai envoi (testnet) ; au retour, les soldes du Wallet sont relus. Un swap ou un dépôt en
                            // attente : son état d'abord (une seule opération à l'issue incertaine à la fois).
                            pendingFirst(onExit: closeFlow) {
                                SendFlowRoot(service: ChainSendService(session: session), fromDrawerID: drawerID, onExit: closeFlow)
                            }
                        case .move(let drawerID):
                            // E1 : le même parcours, entre ses propres tiroirs (testnet).
                            pendingFirst(onExit: closeFlow) {
                                SendFlowRoot(service: ChainSendService(session: session), kind: .move, fromDrawerID: drawerID, onExit: closeFlow)
                            }
                        case .prefilledSend(let prefill):
                            // « Pay again » ou « Send back » d'un reçu ouvert depuis la page d'un tiroir.
                            pendingFirst(onExit: closeFlow) {
                                SendFlowRoot(service: ChainSendService(session: session), prefill: prefill, onExit: closeFlow)
                            }
                        case .pendingSend:
                            // L'état de l'opération en attente (« Check again »), jamais une nouvelle : un swap s'ouvre
                            // dans Swap, une opération du vault dans le vault, un envoi ou un Move dans Envoyer.
                            pendingFirst(onExit: closeFlow) {
                                SendFlowRoot(service: ChainSendService(session: session), onExit: closeFlow)
                            }
                        case .swap(let drawerID):
                            // E3 : le vrai swap (testnet), dans le tiroir choisi d'avance ou dans Main. Un envoi en
                            // attente : E3f (« Check again » à la place du bouton).
                            pendingFirst(onExit: closeFlow) {
                                SwapFlowRoot(service: ChainSwapService(session: session), fromDrawerID: drawerID, onExit: closeFlow)
                            }
                        case .prefilledSwap(let prefill):
                            // « Swap again » d'un reçu ouvert depuis la page d'un tiroir.
                            pendingFirst(onExit: closeFlow) {
                                SwapFlowRoot(service: ChainSwapService(session: session), prefill: prefill, onExit: closeFlow)
                            }
                        case .vault(let action, let drawerID):
                            // F3 / F7 : mettre ou retirer (testnet), depuis ce tiroir. Un envoi en attente : F3c.
                            pendingFirst(onExit: closeFlow) {
                                VaultFlowRoot(
                                    service: ChainVaultService(session: session), action: action, drawerID: drawerID,
                                    onSeePosition: showPositionFromWallet, onExit: closeFlow
                                )
                            }
                        case .savings(let address, let mark):
                            // G2 (Etherfuse, Ondo) depuis la tuile CETES ou USDY d'un tiroir.
                            walletPot(mark, address: address)
                        case .vaultPosition(let address):
                            // G2 depuis la tuile « GROWING » d'un tiroir.
                            walletPot(.defindex, address: address)
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
                            DrawerDestination(
                                selection: selection, wallet: walletModel, activity: activityModel, grow: config.features.grow ? growModel : nil, session: session,
                                actions: drawerActions
                            )
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
            // « See the receipt » d'Envoyer (C9) ouvre le reçu de l'Activity.
            .environment(activityModel)
        case .activity:
            NavigationStack {
                ActivityView(
                    model: activityModel, onPending: { isShowingPendingSend = true }, onSendPrefilled: { prefilledSend = $0 },
                    onSwapPrefilled: { prefilledSwap = $0 }, onPosition: showPositionInGrow
                )
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(isPresented: $isShowingPendingSend) {
                        // L'état de l'opération en attente (« Check again »), jamais une nouvelle : Swap, le vault ou Envoyer.
                        pendingFirst(onExit: closePendingFromActivity) {
                            SendFlowRoot(service: ChainSendService(session: session), onExit: closePendingFromActivity)
                        }
                    }
                    .navigationDestination(item: $prefilledSwap) { prefill in
                        let close = {
                            prefilledSwap = nil
                            refreshAll()
                        }
                        pendingFirst(onExit: close) {
                            SwapFlowRoot(service: ChainSwapService(session: session), prefill: prefill, onExit: close)
                        }
                    }
                    .navigationDestination(item: $prefilledSend) { prefill in
                        let close = {
                            prefilledSend = nil
                            refreshAll()
                        }
                        pendingFirst(onExit: close) {
                            SendFlowRoot(service: ChainSendService(session: session), prefill: prefill, onExit: close)
                        }
                    }
            }
            .environment(activityModel)
        case .grow:
            NavigationStack(path: $growPath) {
                GrowView(model: growModel, onToggleAmounts: { session.preferences.hidesBalances.toggle() }) { growPath.append($0) }
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(for: GrowRoute.self) { route in
                        growDestination(route)
                            .toolbar(.hidden, for: .navigationBar)
                    }
            }
            .environment(activityModel)
        }
    }

    // MARK: Grow

    /// F2, F6, F3 et F7 dans la pile de l'onglet Grow.
    @ViewBuilder
    private func growDestination(_ route: GrowRoute) -> some View {
        switch route {
        case .pot(let mark, let address):
            // G2 : la page d'un pot.
            PotView(
                model: growModel, mark: mark, drawerAddress: address, onBack: popGrow,
                onAdd: { growPath.append(Self.addRoute(mark, drawerID: $0)) },
                onTakeOut: { growPath.append(Self.takeOutRoute(mark, drawerID: $0)) },
                onSwap: { growPath.append(.swap($0)) }
            )
        case .deposit(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainVaultService(session: session), action: .deposit, drawerID: drawerID,
                    onSeePosition: showPositionInGrow, onExit: closeGrowFlow
                )
            }
        case .withdraw(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainVaultService(session: session), action: .withdraw, drawerID: drawerID,
                    onSeePosition: showPositionInGrow, onExit: closeGrowFlow
                )
            }
        case .swap(let prefill):
            // « Get some », « Get more », « Swap back » (F9, F10) : la paire seule, montant vide.
            pendingFirst(onExit: closeGrowFlow) {
                SwapFlowRoot(service: ChainSwapService(session: session), prefill: prefill, onExit: closeGrowFlow)
            }
        case .lendingDeposit(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainLendingService(session: session), action: .deposit, drawerID: drawerID,
                    onSeePosition: showLendingInGrow, onExit: closeGrowFlow
                )
            }
        case .lendingWithdraw(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainLendingService(session: session), action: .withdraw, drawerID: drawerID,
                    onSeePosition: showLendingInGrow, onExit: closeGrowFlow
                )
            }
        case .sentoraDeposit(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainSentoraService(session: session), action: .deposit, drawerID: drawerID,
                    onSeePosition: { showPotInGrow(.sentora, address: $0) }, onExit: closeGrowFlow
                )
            }
        case .sentoraWithdraw(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainSentoraService(session: session), action: .withdraw, drawerID: drawerID,
                    onSeePosition: { showPotInGrow(.sentora, address: $0) }, onExit: closeGrowFlow
                )
            }
        case .solvDeposit(let drawerID):
            pendingFirst(onExit: closeGrowFlow) {
                VaultFlowRoot(
                    service: ChainSolvService(session: session), action: .deposit, drawerID: drawerID,
                    onSeePosition: { showPotInGrow(.solv, address: $0) }, onExit: closeGrowFlow
                )
            }
        }
    }

    /// « Add » sur la page d'un pot : le dépôt de son protocole.
    static func addRoute(_ mark: ChimpPotProtocol, drawerID: String) -> GrowRoute {
        switch mark {
        case .xoxno: .lendingDeposit(drawerID: drawerID)
        case .sentora: .sentoraDeposit(drawerID: drawerID)
        case .solv: .solvDeposit(drawerID: drawerID)
        default: .deposit(drawerID: drawerID)
        }
    }

    /// « Take out » sur la page d'un pot : le retrait de son protocole.
    static func takeOutRoute(_ mark: ChimpPotProtocol, drawerID: String) -> GrowRoute {
        switch mark {
        case .xoxno: .lendingWithdraw(drawerID: drawerID)
        case .sentora: .sentoraWithdraw(drawerID: drawerID)
        default: .withdraw(drawerID: drawerID)
        }
    }

    /// « See my position » : la page du pot de ce protocole dans l'onglet Grow, positions relues.
    private func showPotInGrow(_ mark: ChimpPotProtocol, address: String) {
        refreshAll()
        guard config.features.grow else { return }
        growPath = [.pot(mark, drawerAddress: address)]
        selection = .grow
    }

    /// G2 ouvert depuis la page d'un tiroir (Wallet) : ses parcours restent dans la pile du Wallet.
    private func walletPot(_ mark: ChimpPotProtocol, address: String) -> some View {
        PotView(
            model: growModel, mark: mark, drawerAddress: address, onBack: { if !walletPath.isEmpty { walletPath.removeLast() } },
            onAdd: { walletPath.append(.vault(.deposit, drawerID: $0)) },
            onTakeOut: { walletPath.append(.vault(.withdraw, drawerID: $0)) },
            onSwap: { walletPath.append(.prefilledSwap($0)) }
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private func popGrow() {
        if !growPath.isEmpty { growPath.removeLast() }
    }

    /// Fin d'un parcours du vault ouvert dans Grow : retour à l'écran d'où il est parti ; tout est relu.
    private func closeGrowFlow() {
        popGrow()
        refreshAll()
    }

    /// « See my position » après un dépôt XOXNO : la position du tiroir dans l'onglet Grow, positions relues.
    private func showLendingInGrow(_ address: String) {
        refreshAll()
        guard config.features.grow else { return }
        growPath = [.pot(.xoxno, drawerAddress: address)]
        selection = .grow
    }

    /// « See my position » (F5, reçu) : F6 du tiroir dans l'onglet Grow, positions relues.
    private func showPositionInGrow(_ address: String) {
        refreshAll()
        guard config.features.grow else { return }
        growPath = [.pot(.defindex, drawerAddress: address)]
        selection = .grow
    }

    /// « See my position » (F5) d'un parcours ouvert depuis le Wallet : F6, à la place du parcours.
    private func showPositionFromWallet(_ address: String) {
        if let index = walletPath.lastIndex(where: { if case .drawer = $0 { true } else { false } }) {
            walletPath.removeSubrange((index + 1)...)
        } else {
            walletPath.removeAll()
        }
        refreshAll()
        walletPath.append(.vaultPosition(address))
    }

    private func closePendingFromActivity() {
        isShowingPendingSend = false
        refreshAll()
    }

    private func refreshAll() {
        Task { await walletModel.refresh() }
        Task { await loadGifts() }
        Task { await activityModel.refresh() }
        // Grow éteint sur ce réseau : rien à relire (aucun écran ne le montre).
        if config.features.grow { Task { await growModel.refresh() } }
    }

    /// Une opération signée attend son issue : son propre parcours d'abord (une seule à la fois, et chaque parcours
    /// note sa propre ligne d'historique) : un swap dans Swap, une opération du vault dans le vault. Sinon `content`
    /// (qui, devant un envoi en attente, montre son propre « Check it first »).
    @ViewBuilder
    private func pendingFirst(onExit: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Group {
            if hasPendingPrize {
                PrizeClaimRoot(service: ChainPrizeService(session: session), gift: nil, onExit: onExit)
            } else if hasPendingVault {
                VaultFlowRoot(
                    service: ChainVaultService(session: session), action: .deposit,
                    onSeePosition: showPositionInGrow, onExit: onExit
                )
            } else if hasPendingSwap {
                SwapFlowRoot(service: ChainSwapService(session: session), onExit: onExit)
            } else {
                content()
            }
        }
        // Règle 8 : dans un parcours qui fait signer, les montants restent visibles même si l'œil est fermé.
        .chimpShowsAmounts()
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
            walletPath.append(.swap(nil))
        }
    }

    /// Une opération signée attend son issue, et c'est un swap : Envoyer et Move ouvrent son état.
    private var hasPendingSwap: Bool { session.wallet.pendingSend?.swap != nil }

    /// Une opération signée attend son issue, et c'est un dépôt ou un retrait du vault.
    private var hasPendingVault: Bool { session.wallet.pendingSend?.vault != nil }

    /// Une opération signée attend son issue, et c'est le retrait d'un cadeau (carte partenaire, D5).
    private var hasPendingPrize: Bool { session.wallet.pendingSend?.prize != nil }

    /// Fin d'un parcours (Send, Move…) : retour à la page du tiroir d'où il est parti, sinon au Wallet ; soldes et
    /// historique relus.
    private func closeFlow() {
        if let index = walletPath.lastIndex(where: { if case .drawer = $0 { true } else { false } }) {
            walletPath.removeSubrange((index + 1)...)
        } else {
            walletPath.removeAll()
        }
        refreshAll()
    }

    /// Actions de la page d'un tiroir (B2, B3) : chacune part de ce tiroir.
    private var drawerActions: DrawerDetailActions {
        DrawerDetailActions(
            onBack: {
                if !walletPath.isEmpty { walletPath.removeLast() }
            },
            onSend: { walletPath.append(.send($0)) },
            onMove: { walletPath.append(.move($0)) },
            onSwap: { walletPath.append(.swap($0)) },
            onSendPrefilled: { walletPath.append(.prefilledSend($0)) },
            onSwapPrefilled: { walletPath.append(.prefilledSwap($0)) },
            onPending: { walletPath.append(.pendingSend) },
            onAllActivity: { address in
                activityModel.filter = .drawer(address)
                selection = .activity
            },
            onChangePIN: { walletPath.append(.changePIN($0)) },
            onRemove: { walletPath.append(.removeCard($0, $1)) },
            onAddCard: { walletPath = [.addCard] },
            onGrow: { walletPath.append(.vault(.deposit, drawerID: $0)) },
            onPosition: { walletPath.append(.vaultPosition($0)) },
            onSavings: { address, code in walletPath.append(.savings(address, ChimpPotProtocol.savings(code: code) ?? .etherfuse)) }
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
    /// Swap (E3), dans un tiroir choisi d'avance ou dans Main.
    case swap(String?)
    /// « Swap again » d'un reçu.
    case prefilledSwap(SwapPrefill)
    case settings
    case addCard
    case drawer(DrawerSelection)
    /// G6 (retirer) ou G7 (carte perdue), pour la carte de cette clé.
    case removeCard(RemoveCardModel.Mode, String)
    /// Changer le PIN de la carte de cette clé.
    case changePIN(String)
    /// F3 (mettre) ou F7 (retirer), depuis ce tiroir (identifiant).
    case vault(VaultAction, drawerID: String?)
    /// F6 : la position de ce tiroir (adresse).
    case vaultPosition(String)
    /// F10 : les CETES de ce tiroir (adresse).
    case savings(String, ChimpPotProtocol)
    /// « Add money » (D4).
    case addMoney
    /// N1 : devis NEAR Intents (« From another chain »).
    case crossChainQuote
    /// N2 : « From Base · via ROZO ».
    case rozoTransfer
}

/// Recevoir (D1) poussé depuis le Wallet : un ViewModel neuf à chaque ouverture, gardé tant que l'écran est affiché.
private struct ReceiveDestination: View {
    @State private var model: ReceiveViewModel
    let onAddMoney: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(session: AppSession, initialDrawerID: String? = nil, onAddMoney: (() -> Void)? = nil) {
        _model = State(initialValue: ReceiveViewModel(dataSource: LocalReceiveDataSource(session: session), initialDrawerID: initialDrawerID))
        self.onAddMoney = session.config.features.addMoney ? onAddMoney : nil
    }

    var body: some View {
        ReceiveView(model: model, onBack: { dismiss() }, onAddMoney: onAddMoney)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// N1 : un ViewModel neuf à chaque ouverture, sur l'API 1Click (devis à blanc, sans clé).
private struct CrossChainQuoteDestination: View {
    @State private var model: CrossChainQuoteModel?
    let onBack: () -> Void

    init(config: ChimpNetworkConfig, onBack: @escaping () -> Void) {
        _model = State(initialValue: config.integrations.map { integrations in
            CrossChainQuoteModel(
                client: OneClickClient(api: integrations.nearIntents.api, refundAccount: integrations.nearIntents.refundAccount),
                recipient: integrations.nearIntents.quoteRecipient
            )
        })
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if let model {
                CrossChainQuoteView(model: model, onBack: onBack)
            } else {
                Color(.chimpBackground).onAppear(perform: onBack)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .chimpShowsAmounts()
    }
}

/// N2 : un ViewModel neuf à chaque ouverture, vers le Main du compte, sur l'API de ROZO (sans clé).
private struct RozoTransferDestination: View {
    @State private var model: RozoTransferModel?
    let config: ChimpNetworkConfig
    let onBack: () -> Void
    let onDone: () -> Void

    init(config: ChimpNetworkConfig, session: AppSession, onBack: @escaping () -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: config.integrations.flatMap { integrations in
            session.wallet.account.flatMap { account in
                // Revue de sécurité F6 : l'arrivée est vérifiée sur Stellar (SAC USDC de Config/, payeurs ROZO de Config/).
                ((try? SACClient.stellarAssets(config: config)) ?? []).first { $0.code == "USDC" }.map { usdc in
                    RozoTransferModel(
                        client: RozoClient(config: integrations.rozo),
                        verifier: StellarRozoPayoutVerifier(events: SorobanClient(config: config), usdc: usdc.contract, payoutAccounts: integrations.rozo.payoutAccounts),
                        config: integrations.rozo, recipient: account.address
                    )
                }
            }
        })
        self.config = config
        self.onBack = onBack
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if let model {
                RozoTransferView(model: model, explorerURL: config.explorerURL(transactionHash:), onBack: onBack, onDone: onDone)
            } else {
                Color(.chimpBackground).onAppear(perform: onBack)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .chimpShowsAmounts()
    }
}

/// Détail d'un tiroir (B2, B3) : un ViewModel neuf à chaque ouverture, sur les soldes du Wallet.
private struct DrawerDestination: View {
    @State private var model: DrawerDetailModel
    let activity: ActivityViewModel
    /// `nil` quand Grow est éteint sur ce réseau : ni tuile « GROWING » ni bouton « Grow ».
    let grow: GrowModel?
    let actions: DrawerDetailActions

    init(
        selection: DrawerSelection, wallet: WalletViewModel, activity: ActivityViewModel, grow: GrowModel?, session: AppSession,
        actions: DrawerDetailActions
    ) {
        _model = State(initialValue: DrawerDetailModel(selection: selection, wallet: wallet, session: session))
        self.activity = activity
        self.grow = grow
        self.actions = actions
    }

    var body: some View {
        DrawerDetailView(model: model, activity: activity, actions: actions, grow: grow)
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
        // Règle 8 : ce que le retrait fait de l'argent de la carte reste lisible, même si l'œil est fermé.
        .chimpShowsAmounts()
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
            session: session, chain: ChainWalletReader(config: config), oracle: ReflectorPriceOracle.shared,
            stablebondPrices: StablebondWalletPrices(config: config)
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

private extension View {
    /// Pose la barre d'onglets en bas de l'écran racine d'un onglet ; le contenu défilant en tient compte.
    func withTabBar(_ selection: Binding<ChimpTab>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpTabBar(selection: selection)
        }
    }
}

#Preview {
    MainTabView(session: AppSession(store: InMemoryLocalWalletStore(), config: .testnet))
}
