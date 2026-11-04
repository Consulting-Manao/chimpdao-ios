import Foundation

/// Le scan démarre tout seul après le PIN (ou après la vérification pour une carte sans PIN), sans « Scan my card »
/// (demande de Barth du 2026-11-04). La feuille « approchez la carte » reste derrière la fenêtre NFC d'iOS : son bouton
/// sert à retaper après une annulation ou un échec, jamais relancé tout seul.
enum AutoScan {
    /// Court délai : le temps de voir le dernier point du PIN se remplir avant la fenêtre NFC d'iOS.
    static let pause: Duration = .milliseconds(300)

    /// Lance `scan` après la pause, si `isStillWanted` le confirme encore à ce moment-là (feuille toujours ouverte, aucun
    /// scan démarré entre-temps par « Scan my card »).
    static func start(when isStillWanted: @escaping () -> Bool, scan: @escaping () async -> Void) {
        Task {
            try? await Task.sleep(for: pause)
            guard isStillWanted() else { return }
            await scan()
        }
    }
}
