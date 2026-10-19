import SwiftUI

extension EnvironmentValues {
    /// Les fonctions du réseau de la session (`ChimpNetworkConfig.features`), posées une fois au lancement
    /// (`ChimpApp`). Par défaut, aucune : un écran hors de l'app (aperçu) ne montre jamais une fonction éteinte.
    @Entry var chimpFeatures: NetworkFeatures = .none
    /// Le réseau de la session, pour les textes qui ne parlent du testnet que sur le testnet. `nil` hors de l'app.
    @Entry var chimpNetwork: StellarNetwork? = nil
}
