import SwiftUI

@main
struct ChimpApp: App {
    init() {
        ChimpFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .chimpReadsScreenInsets()
        }
    }
}
