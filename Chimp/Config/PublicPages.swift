import Foundation

/// Pages web publiques de l'app (sources dans `docs/web/` du workspace). **Seul endroit** où leurs adresses sont écrites
/// (CLAUDE.md, « Config/ »). Les mêmes pour tous les réseaux.
///
/// `nil` tant que les pages ne sont pas en ligne : Réglages affiche alors « Privacy · to add » et « Support · to add ».
/// Barth donne les adresses (HTTPS) quand elles sont publiées (demande du 2026-10-20).
enum PublicPages {
    /// Politique de confidentialité (`privacy.html`). Aussi demandée par App Store Connect (TestFlight externe).
    static let privacy: URL? = nil
    /// Page d'aide (`support.html`).
    static let support: URL? = nil
}
