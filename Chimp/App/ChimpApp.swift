import SwiftUI

@main
struct ChimpApp: App {
    /// La session et le verrou Face ID (I2), ou la raison pour laquelle ce build ne peut pas démarrer.
    @State private var launch: Launch

    enum Launch {
        case ready(AppSession, AppLock)
        /// Configuration réseau incomplète (mainnet pas encore prêt) : jamais de repli sur un autre réseau.
        case misconfigured(NetworkConfigError)
    }

    /// Chimp Admin (configuration Admin) : verrouillée par Face ID à chaque ouverture.
    static var isAdminApp: Bool {
        #if CHIMP_ADMIN_APP
        true
        #else
        false
        #endif
    }

    init() {
        ChimpFonts.register()
        do {
            let session = AppSession.live(config: try ChimpNetworkConfig.forThisBuild())
            // Réglage « Sounds » (I2) : lu à chaque son, il prend effet aussitôt.
            let preferences = session.preferences
            ChimpSoundPlayer.shared.isEnabled = { preferences.soundsEnabled }
            _launch = State(initialValue: .ready(session, AppLock(session: session, alwaysLocked: Self.isAdminApp)))
        } catch let error as NetworkConfigError {
            _launch = State(initialValue: .misconfigured(error))
        } catch {
            _launch = State(initialValue: .misconfigured(.incomplete(network: .mainnet, missing: ["\(error)"])))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .ready(session, lock):
                #if CHIMP_ADMIN_APP
                // Chimp Admin : les cartes et les outils, jamais le wallet.
                AdminAppRoot(session: session, lock: lock)
                    .chimpReadsScreenInsets()
                    .environment(\.chimpFeatures, session.config.features)
                    .environment(\.chimpNetwork, session.network)
                #else
                RootView(session: session, lock: lock)
                    .chimpReadsScreenInsets()
                #if DESIGN_CATALOG
                    .modifier(SwapDemoLaunch())
                    .modifier(VaultDemoLaunch())
                    .modifier(CrossChainDemoLaunch())
                    .modifier(RozoDemoLaunch())
                #endif
                    // Les fonctions du réseau (Swap, Grow, Add money, CETES), pour tous les écrans, démos comprises.
                    .environment(\.chimpFeatures, session.config.features)
                    .environment(\.chimpNetwork, session.network)
                #endif
            case .misconfigured(let error):
                MisconfiguredBuildView(error: error)
            }
        }
    }
}
