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
    /// Écrans poussés dans l'onglet Wallet.
    @State private var walletPath: [WalletRoute] = []
    /// Gardé ici pour que l'historique reste affiché quand on change d'onglet.
    @State private var activityModel: ActivityViewModel
    /// Écran d'état d'un paiement en attente, ouvert depuis l'Activity.
    @State private var isShowingPendingSend = false
    /// « Pay again » depuis un reçu de l'Activity : Envoyer avec cette adresse collée en C1.
    @State private var payAgainAddress: String?
    #if DESIGN_CATALOG
    @State private var isShowingCatalog = false
    #endif

    /// Le vrai Wallet : soldes lus sur le réseau de l'app (testnet), prix du XLM par l'oracle de mainnet.
    init(session: AppSession, config: ChimpNetworkConfig = .testnet) {
        self.session = session
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
                WalletView(model: walletModel, onSettings: settingsAction, onAction: openWalletAction, onAddCard: { walletPath.append(.addCard) })
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(for: WalletRoute.self) { route in
                        switch route {
                        case .receive:
                            ReceiveDestination(session: session)
                        case .send:
                            // Le vrai envoi (testnet) ; au retour, les soldes du Wallet sont relus.
                            SendFlowRoot(service: ChainSendService(session: session)) {
                                walletPath.removeAll()
                                Task { await walletModel.refresh() }
                            }
                        case .move:
                            // E1 : le même parcours, entre ses propres tiroirs (testnet).
                            SendFlowRoot(service: ChainSendService(session: session), kind: .move) {
                                walletPath.removeAll()
                                Task { await walletModel.refresh() }
                            }
                        case .addCard:
                            // G1 → G3 : ajouter une carte au compte (testnet) ; au retour, le Wallet relit ses cartes.
                            AddCardDestination(session: session) {
                                walletPath.removeAll()
                                Task { await walletModel.refresh() }
                            }
                        case .settings:
                            // I2 : au retour, le Wallet relit les noms et couleurs des cartes.
                            SettingsDestination(session: session, walletCards: walletModel.cards, onDeveloper: developerAction) {
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
                ActivityView(model: activityModel, onPending: { isShowingPendingSend = true }, onPayAgain: { payAgainAddress = $0 })
                    .toolbar(.hidden, for: .navigationBar)
                    .withTabBar($selection)
                    .navigationDestination(isPresented: $isShowingPendingSend) {
                        // Envoyer rouvre l'état du paiement en attente (« Check again »), jamais un nouvel envoi.
                        SendFlowRoot(service: ChainSendService(session: session)) {
                            isShowingPendingSend = false
                            Task { await activityModel.refresh() }
                        }
                    }
                    .navigationDestination(item: $payAgainAddress) { address in
                        SendFlowRoot(service: ChainSendService(session: session), prefilledAddress: address) {
                            payAgainAddress = nil
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
            walletPath.append(.receive)
        case .send:
            walletPath.append(.send)
        case .move:
            walletPath.append(.move)
        case .swap:
            // TODO(jalon 4b) : Swap (E3), selon le périmètre V1.
            break
        }
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
    case receive
    case send
    case move
    case settings
    case addCard
}

/// Recevoir (D1) poussé depuis le Wallet : un ViewModel neuf à chaque ouverture, gardé tant que l'écran est affiché.
private struct ReceiveDestination: View {
    @State private var model: ReceiveViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: AppSession) {
        _model = State(initialValue: ReceiveViewModel(dataSource: LocalReceiveDataSource(session: session)))
    }

    var body: some View {
        ReceiveView(model: model, onBack: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
    }
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

    init(session: AppSession, walletCards: [CardBalance], onDeveloper: (() -> Void)?, onExit: @escaping () -> Void) {
        _model = State(initialValue: SettingsModel(session: session, walletCards: walletCards))
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
