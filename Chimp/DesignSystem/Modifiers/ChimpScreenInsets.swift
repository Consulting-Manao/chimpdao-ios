import SwiftUI

/// Zones sûres de l'écran entier (barre d'état en haut, barre d'accueil en bas), lues une fois
/// à la racine de l'app. Les composants posés dans un défilement ne les connaissent pas eux-mêmes.
///
/// Valeur par défaut (aperçus Xcode) : iPhone à Dynamic Island.
extension EnvironmentValues {
    @Entry var chimpScreenInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
}

extension EdgeInsets {
    /// Vrai sur les iPhone à encoche ou à Dynamic Island (barre d'état haute) ;
    /// faux sur l'iPhone SE, dont la barre d'état occupe toute sa zone sûre de 20 pt.
    var hasTallStatusBar: Bool { top > 24 }

    /// Vrai si l'écran a une barre d'accueil (pas de bouton principal physique).
    var hasHomeIndicator: Bool { bottom > 0 }
}

extension View {
    /// À appliquer une fois, à la racine de l'app : lit les zones sûres de l'écran
    /// et les met à disposition des composants (`chimpScreenInsets`).
    func chimpReadsScreenInsets() -> some View {
        modifier(ChimpScreenInsetsReader())
    }
}

private struct ChimpScreenInsetsReader: ViewModifier {
    @State private var insets: EdgeInsets?

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.chimpScreenInsets) { value in
                if let insets { value = insets }
            }
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                proxy.safeAreaInsets
            } action: { newValue in
                insets = newValue
            }
    }
}
