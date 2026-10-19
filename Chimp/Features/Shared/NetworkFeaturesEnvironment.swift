import SwiftUI

extension EnvironmentValues {
    /// Les fonctions du réseau de la session (`ChimpNetworkConfig.features`), posées une fois au lancement
    /// (`ChimpApp`). Par défaut, aucune : un écran hors de l'app (aperçu) ne montre jamais une fonction éteinte.
    @Entry var chimpFeatures: NetworkFeatures = .none
}
