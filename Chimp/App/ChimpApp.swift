import SwiftUI

@main
struct ChimpApp: App {
    @State private var session: AppSession
    /// Verrou Face ID (I2), réglé par compte, désactivé par défaut.
    @State private var lock: AppLock

    init() {
        ChimpFonts.register()
        let session = AppSession.live()
        _session = State(initialValue: session)
        // Réglage « Sounds » (I2) : lu à chaque son, il prend effet aussitôt.
        let preferences = session.preferences
        ChimpSoundPlayer.shared.isEnabled = { preferences.soundsEnabled }
        _lock = State(initialValue: AppLock(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, lock: lock)
                .chimpReadsScreenInsets()
            #if DESIGN_CATALOG
                .modifier(SwapDemoLaunch())
            #endif
        }
    }
}
