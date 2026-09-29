import SwiftUI

/// Espacements (points). Échelle observée dans la maquette : 4 → 26.
enum ChimpSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let sm: CGFloat = 10
    static let m: CGFloat = 12
    static let ml: CGFloat = 14
    static let l: CGFloat = 16
    static let lg: CGFloat = 18
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 22
    static let xxxl: CGFloat = 26

    /// Marges latérales d'un écran.
    static let screenMargin: CGFloat = 20
    /// Marges latérales d'un écran plein (fond `chimpHeader` : A2, C7, H3…).
    static let fullScreenMargin: CGFloat = 24
    /// Écart entre les éléments d'une liste.
    static let listGap: CGFloat = 10
    /// Écart entre deux blocs.
    static let blockGap: CGFloat = 14
    /// Écart avant un libellé de section.
    static let sectionGap: CGFloat = 22

    /// Zone du bouton principal en bas d'écran. Dans la maquette, 42 pt sous le bouton
    /// incluent la barre d'accueil (34 pt) : il reste 8 pt au-dessus de la zone sûre.
    static let bottomBar = EdgeInsets(top: 14, leading: 22, bottom: 8, trailing: 22)

    /// L'en-tête et la barre d'onglets empiètent de 4 pt sur les zones sûres :
    /// dans la maquette, le contenu de l'en-tête commence à 58 pt du haut (barre d'état : 62 pt)
    /// et celui de la barre d'onglets s'arrête à 30 pt du bas (barre d'accueil : 34 pt).
    /// Seulement sur les iPhone à encoche ou Dynamic Island : sur l'iPhone SE, la barre d'état
    /// occupe toute sa zone sûre et il n'y a pas de barre d'accueil.
    static let chromeSafeAreaOverlap: CGFloat = 4
    /// Sans barre d'état haute (iPhone SE) : écart entre la barre d'état et le contenu de l'en-tête,
    /// repris de la maquette (texte de la barre d'état jusqu'à 43 pt, contenu à 58 pt).
    static let statusBarGap: CGFloat = 15
    /// Sans barre d'accueil (iPhone SE) : marge sous les onglets.
    static let tabBarBottomWithoutHomeIndicator: CGFloat = 16

    /// Marges de l'en-tête (Chimp Top), mesurées depuis le bas de la zone sûre du haut.
    static func header(for screen: EdgeInsets, bottom: CGFloat = 18) -> EdgeInsets {
        EdgeInsets(top: screen.hasTallStatusBar ? -chromeSafeAreaOverlap : statusBarGap, leading: 20, bottom: bottom, trailing: 20)
    }

    /// Marges de la barre d'onglets (Chimp Nav), mesurées depuis le haut de la zone sûre du bas.
    static func tabBar(for screen: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: 10,
            leading: 16,
            bottom: screen.hasHomeIndicator ? -chromeSafeAreaOverlap : tabBarBottomWithoutHomeIndicator,
            trailing: 16
        )
    }
}

/// Rayons des coins (points).
enum ChimpRadius {
    /// Segments (List/Compare).
    static let segment: CGFloat = 8
    /// Icônes d'actifs.
    static let icon: CGFloat = 12
    /// Onglet actif, icônes carrées, vignette de carte de la feuille de signature.
    static let tab: CGFloat = 14
    /// Petits boutons, touches du pavé, listes groupées, vignettes de couleur.
    static let key: CGFloat = 16
    /// Boutons principaux, lignes d'actifs, champs, bulle de Chimpy.
    static let control: CGFloat = 18
    /// Composant Chimp Card.
    static let chimpCard: CGFloat = 20
    /// Icône carrée d'une carte « tiroir » (Main).
    static let drawerIcon: CGFloat = 15
    /// Grandes cartes (carte Main du Wallet, carte de revue).
    static let panel: CGFloat = 22
    /// Haut des feuilles (bottom sheets).
    static let sheet: CGFloat = 34
    /// Carte blanche du QR code (D1).
    static let qrCard: CGFloat = 24
    /// Carré jaune au centre du QR code.
    static let qrBadge: CGFloat = 8
    // Pilules (chips, « + Add », interrupteur) : utiliser `Capsule()`.
}

/// Épaisseurs des contours (points), couleur `chimpOutline`.
///
/// Attention : dans la maquette (CSS), un contour s'ajoute *autour* du rembourrage et de la taille
/// indiquée, sauf mention `box-sizing:border-box`. En SwiftUI, `strokeBorder` dessine *à l'intérieur*
/// du cadre : il faut donc ajouter l'épaisseur du contour au rembourrage pour retrouver les mêmes tailles.
enum ChimpBorder {
    /// Pastilles, segments, petites vignettes, séparateurs de liste.
    static let thin: CGFloat = 2
    /// La signature visuelle : boutons, cartes, lignes, champs, touches.
    static let regular: CGFloat = 3
    /// Bord haut des feuilles, carte au centre des anneaux NFC, anneau de sélection.
    static let thick: CGFloat = 4
}

/// Ombre « cartoon » : décalée, sans flou, couleur `chimpOutline`.
struct ChimpShadow: Equatable {
    let x: CGFloat
    let y: CGFloat

    /// Bouton principal ou secondaire pleine largeur.
    static let button = ChimpShadow(x: 0, y: 5)
    /// Boutons moyens, onglet actif.
    static let raised = ChimpShadow(x: 0, y: 4)
    /// Tuiles d'action, bulle de Chimpy.
    static let tile = ChimpShadow(x: 3, y: 3)
    /// Grandes cartes, Chimp Card, carte NFC.
    static let card = ChimpShadow(x: 4, y: 4)
    /// Carte du QR code (D1).
    static let qrCard = ChimpShadow(x: 5, y: 5)

    /// Ombre floue des illustrations de Chimpy (couleur `chimpIllustrationShadow`).
    static let illustrationOffset = CGSize(width: 5, height: 6)
}

/// Tailles fixes (points).
enum ChimpSize {
    /// Zone tactile minimale (recommandation Apple).
    static let minimumTouchTarget: CGFloat = 44
    /// Bouton rond de l'en-tête (retour).
    static let headerButton: CGFloat = 40
    /// Bouton rond de l'en-tête (réglages).
    static let headerGearButton: CGFloat = 42
    /// Hauteur d'un segment de la barre d'étapes, contour de 2 pt compris (7 + 2 × 2 dans la maquette).
    static let stepSegmentHeight: CGFloat = 11
    /// Chimpy dans sa bulle.
    static let chimpyThumbnail: CGFloat = 68
    /// Point du code PIN, contour compris (22 + 3 × 2 dans la maquette).
    static let pinDot: CGFloat = 28
    /// Écart entre deux points du PIN.
    static let pinDotSpacing: CGFloat = 16
    /// Écart entre les touches du pavé numérique.
    static let keypadSpacing: CGFloat = 9
    /// Rembourrage vertical d'une touche du pavé, hors contour.
    static let keyVerticalPadding: CGFloat = 11
    /// Même rembourrage sur petit écran (iPhone SE) : 8 pt de moins par touche, toujours au-dessus de 44 pt.
    static let keyVerticalPaddingCompact: CGFloat = 7
    /// Vignette de couleur (A5, G1b).
    static let colorSwatch: CGFloat = 52
    /// Hauteur d'une feuille (PIN, choix d'un tiroir…).
    static let sheetHeight: CGFloat = 560
    /// Hauteur de la feuille « approchez la carte » : plus haute que la maquette (560) pour
    /// l'instruction, la ligne PIN et le bouton « Scan my card » ajoutés à l'étape C.
    static let cardTapSheetHeight: CGFloat = 660
    /// Zone des anneaux NFC autour de la carte (feuille).
    static let nfcRingArea: CGFloat = 180
    /// Vignette de carte au centre des anneaux, contour compris (118 × 76 + 4 × 2).
    static let cardThumbnail = CGSize(width: 126, height: 84)
    /// Logo dans la vignette de carte.
    static let cardThumbnailLogo: CGFloat = 40
    /// Pastille de couleur du bandeau « qui peut signer », contour compris (14 + 2 × 2).
    static let signerSwatch: CGFloat = 18
    /// Icône carrée d'une carte « tiroir », contour compris (48 + 3 × 2).
    static let drawerIcon: CGFloat = 54
    /// Logo dans l'icône d'une carte « tiroir ».
    static let drawerIconLogo: CGFloat = 32
    /// Symbole d'une tuile d'action (Send, Receive…).
    static let actionTileGlyph: CGFloat = 21
    /// Avatar de l'en-tête du Wallet (tête de Chimpy).
    static let headerAvatar: CGFloat = 40
    /// Hauteur maximale de Chimpy dans sa bulle.
    static let chimpyThumbnailMaxHeight: CGFloat = 80
    /// Poignée des feuilles.
    static let sheetHandle = CGSize(width: 52, height: 5)
    /// Largeur d'une tuile du motif de fond, et sur les cartes.
    static let patternTile: CGFloat = 420
    static let patternTileOnCard: CGFloat = 260
    /// Rapport largeur / hauteur d'une carte bancaire.
    static let cardAspectRatio: CGFloat = 1.58
    /// Hauteur utile (entre l'en-tête et le bouton du bas) sous laquelle l'écran de montant (C2) resserre
    /// son pavé : iPhone SE ≈ 460 pt, iPhone 16 ≈ 620 pt.
    static let compactAmountScreenHeight: CGFloat = 540
    /// Côté du QR code (D1), hors carte blanche.
    static let qrCode: CGFloat = 200
    /// Part du côté du QR code couverte par la tête de Chimpy (5 modules sur 25 dans la maquette).
    static let qrBadgeFraction: CGFloat = 0.2
    /// Icône d'un tiroir dans le sélecteur « INTO » (D1).
    static let drawerPickerIcon: CGFloat = 22
    /// Icône d'un tiroir dans une ligne de choix (C3), contour compris.
    static let drawerOptionIcon = CGSize(width: 38, height: 26)
    /// Pastille numérotée de la carte « What happens » (C4), contour compris (30 + 3 × 2).
    static let reviewStepBadge: CGFloat = 36
    /// Bouton radio d'une ligne de choix, contour compris.
    static let radio: CGFloat = 24
}

/// Opacités (0 à 1).
enum ChimpOpacity {
    /// Motif de fond sur les en-têtes, la barre d'onglets et les écrans pleins.
    static let pattern: Double = 0.14
    /// Motif de fond sur les cartes.
    static let patternOnCard: Double = 0.16
    /// Élément désactivé ou indisponible.
    static let disabled: Double = 0.45
    /// Appui sur un élément sans ombre (bouton secondaire, lien, onglet) : non spécifié par la maquette.
    static let pressed: Double = 0.7
}

extension View {
    /// Agrandit la zone tactile à 44 pt sans changer la place occupée à l'écran
    /// (ex. : bouton rond de 40 pt de la maquette).
    func expandedTouchTarget(visualSize: CGFloat) -> some View {
        let inset = max(0, (ChimpSize.minimumTouchTarget - visualSize) / 2)
        return frame(width: visualSize + inset * 2, height: visualSize + inset * 2)
            .contentShape(Rectangle())
            .padding(-inset)
    }

    /// Style « cartoon » : fond, contour épais et ombre dure décalée, sans flou.
    func cartoonSurface<S: InsettableShape>(
        _ shape: S,
        fill: some ShapeStyle,
        border: CGFloat = ChimpBorder.regular,
        shadow: ChimpShadow? = nil
    ) -> some View {
        background {
            ZStack {
                if let shadow {
                    shape.fill(Color(.chimpOutline)).offset(x: shadow.x, y: shadow.y)
                }
                shape.fill(fill)
                shape.strokeBorder(Color(.chimpOutline), lineWidth: border)
            }
        }
    }
}
