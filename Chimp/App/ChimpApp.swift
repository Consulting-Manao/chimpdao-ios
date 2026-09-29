import SwiftUI

@main
struct ChimpApp: App {
    @State private var session = AppSession.live()

    init() {
        ChimpFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .chimpReadsScreenInsets()
        }
    }
}
