import SwiftUI

// Les couleurs vivent dans le catalogue d'assets (Assets.xcassets/Colors) :
// les couleurs de thème ont une variante claire et une variante sombre,
// les couleurs fixes sont identiques dans les deux thèmes.
//
// Xcode génère un raccourci pour chaque couleur : `Color(.chimpBackground)`,
// `.foregroundStyle(.chimpTextPrimary)`, etc. Le préfixe « chimp » évite
// les collisions avec les styles de SwiftUI (`.background`, `.primary`…).
//
// Thème (source : design/Chimp App Final.dc.html, Tweaks › Look)
//   chimpBackground        bg    fond des écrans
//   chimpHeader            hd    en-têtes, barre d'onglets, écrans pleins
//   chimpSurface           sf    cartes, lignes, champs, touches
//   chimpSurfaceSecondary  sf2   bandeaux d'info, pastilles, séparateurs
//   chimpTextPrimary       ink   texte principal
//   chimpTextSecondary     mut   texte secondaire, libellés, chevrons
//   chimpOutline           ln    contours et ombres « cartoon »
//   chimpPositive          pos   gains, ✓ (clair corrigé pour le contraste : #2A7123 au lieu de #2F7F27)
//   chimpNegative          neg   destructif, ✕
//
// Fixes
//   chimpAccent / chimpOnAccent               jaune banane et texte posé dessus
//   chimpOnHeaderPrimary / …Secondary         titres et sous-titres sur l'en-tête
//   chimpOnHeaderAccent                       libellé « STEP 2 OF 3 » (#FFD42B au lieu de #FFD11E, contraste)
//   chimpHeaderButtonFill                     boutons ronds de l'en-tête
//   chimpOutlineOnHeader                      contours posés sur l'en-tête : segments d'étape, onglet actif
//                                             (#201C1A dans les deux thèmes, comme la maquette)
//   chimpStepSegmentInactive                  segments d'étape non atteints
//   chimpScrim                                voile derrière une feuille
//   chimpHeaderShade                          voile sombre posé sur l'en-tête : bandeau bas des écrans pleins,
//                                             bouton secondaire sur l'en-tête (noir 22 %, fusion du 20 % du bouton)
//   chimpHeaderBannerBorder                   bord haut du bandeau bas des écrans pleins
//   chimpIllustrationShadow                   ombre des illustrations de Chimpy
//   chimpQRBackground / chimpQRModule         fond blanc et modules sombres du QR code, dans les deux thèmes
//                                             (un QR clair sur fond sombre se scanne mal)
//   chimpCard* / chimpOnCard*                 couleurs des cartes et leur texte
//   chimpActivity*                            fonds d'icônes de l'activité (I1)
//   chimpRisk*                                niveaux de risque (F2, F3)

/// Couleur choisie par l'utilisateur pour une carte (A5, G1b).
enum ChimpCardColor: String, CaseIterable, Identifiable {
    case jungle
    case banana
    case leaf
    case pink

    var id: String { rawValue }

    var fill: Color {
        switch self {
        case .jungle: Color(.chimpCardJungle)
        case .banana: Color(.chimpCardBanana)
        case .leaf: Color(.chimpCardLeaf)
        case .pink: Color(.chimpCardPink)
        }
    }

    /// Texte posé sur la carte : blanc sur Jungle, sombre sur les couleurs vives.
    var ink: Color {
        self == .jungle ? Color(.chimpOnCardJungle) : Color(.chimpOnCardBright)
    }
}
