import SwiftUI

/// L'œil du Wallet (demande de Barth du 2026-11-04) : fermé, chaque montant affiché devient « **** », partout (Wallet,
/// tiroirs, Grow, Activity, reçus). Posé à la racine depuis les réglages du téléphone. Les parcours qui font signer un
/// montant le remettent à `false` (`chimpShowsAmounts`) : on voit toujours ce qu'on signe (règle 8).
extension EnvironmentValues {
    @Entry var chimpHidesAmounts = false
}

enum ChimpPrivacy {
    static let hiddenAmount = "****"

    /// Le montant, ou « **** » si l'œil est fermé.
    static func amount(_ text: String, hidden: Bool) -> String {
        hidden ? hiddenAmount : text
    }
}

extension View {
    /// Montants toujours visibles dans ce parcours (montant à saisir, vérification, PIN et tap, issue de l'envoi).
    func chimpShowsAmounts() -> some View {
        environment(\.chimpHidesAmounts, false)
    }
}
