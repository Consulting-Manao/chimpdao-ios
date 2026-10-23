import Foundation

/// Pages web publiques de l'app (sources dans `docs/web/` du workspace). **Seul endroit** où leurs adresses sont écrites
/// (CLAUDE.md, « Config/ »). Les mêmes pour tous les réseaux.
///
/// En ligne depuis le 2026-10-23 (adresses données par Barth ; la barre finale évite une redirection du site).
/// `nil` : Réglages afficherait « Privacy · to add » et « Support · to add ».
enum PublicPages {
    /// Politique de confidentialité (`privacy.html`). Aussi demandée par App Store Connect (TestFlight externe).
    static let privacy: URL? = URL(string: "https://chimpdao.xyz/privacy/")
    /// Page d'aide (`support.html`).
    static let support: URL? = URL(string: "https://chimpdao.xyz/support/")
}
