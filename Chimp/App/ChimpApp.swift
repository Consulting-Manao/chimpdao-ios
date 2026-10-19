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

    init() {
        ChimpFonts.register()
        do {
            let session = AppSession.live(config: try ChimpNetworkConfig.forThisBuild())
            // Réglage « Sounds » (I2) : lu à chaque son, il prend effet aussitôt.
            let preferences = session.preferences
            ChimpSoundPlayer.shared.isEnabled = { preferences.soundsEnabled }
            _launch = State(initialValue: .ready(session, AppLock(session: session)))
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
            case .misconfigured(let error):
                MisconfiguredBuildView(error: error)
            }
        }
    }
}
