import SwiftUI

/// Animations de la maquette. Si l'utilisateur a activé « Réduire les animations »,
/// les composants arrêtent `bob` et figent les anneaux (`@Environment(\.accessibilityReduceMotion)`).
enum ChimpMotion {
    /// Anneau jaune qui grossit et s'efface autour de la carte (attente d'un tap NFC).
    enum Ring {
        static let startScale: CGFloat = 0.55
        static let endScale: CGFloat = 1.5
        static let startOpacity: Double = 0.95
        static let endOpacity: Double = 0
        static let lineWidth: CGFloat = 4

        /// Écrans pleins (A2, A8, G1, G2, H2, D3) : 3 anneaux, 2,6 s, décalés de 0 / 0,87 / 1,74 s.
        static let fullScreen = Config(duration: 2.6, count: 3, stagger: 0.87)
        /// Feuille « approchez la carte » (C5, E2, F9) : 2 anneaux, 2,4 s, décalés de 1,2 s.
        static let sheet = Config(duration: 2.4, count: 2, stagger: 1.2)

        struct Config: Equatable {
            let duration: Double
            let count: Int
            let stagger: Double
        }
    }

    /// Flottement vertical de Chimpy et des cartes (ease-in-out, en boucle).
    enum Bob {
        static let amplitude: CGFloat = 7
        /// Durées calmes relevées dans la maquette : 3 à 5 s selon l'écran (A1 : 4,5 s ; F1 : 5 s…).
        static let calm: ClosedRange<Double> = 3...5
        /// Durées nerveuses (easter eggs) : J1 1,2 s, J3 1,6 s.
        static let nervous: ClosedRange<Double> = 1.2...1.6
        /// Inclinaison de la carte en A3.
        static let tiltedCardAngle = Angle.degrees(-3)
    }

    /// Banane qui mûrit (F10) : teinte +65° (verte) → normale, aller-retour.
    enum Ripen {
        static let duration: Double = 3.2
        static let unripeHueRotation = Angle.degrees(65)
        static let unripeSaturation: Double = 0.8
    }

    /// Erreur de PIN (validé le 2026-09-28) : secousse horizontale et points en rouge.
    enum Shake {
        static let duration: Double = 0.4
        static let amplitude: CGFloat = 10
        /// Durée pendant laquelle les points restent rouges avant d'être vidés.
        static let errorDisplay: Double = 0.6
    }

    /// Appui sur un bouton (non spécifié par la maquette, validé le 2026-09-28) :
    /// le bouton descend de la hauteur de son ombre, qui disparaît.
    enum Press {
        static let duration: Double = 0.1
    }

    /// Micro-animations (non spécifiées par la maquette, retour du call avec Pamphile du 2026-10-01).
    enum Micro {
        /// Montant qui défile.
        static let roll = Animation.snappy(duration: 0.35)
        /// Fondu qui remplace le mouvement quand « Réduire les animations » est activé.
        static let fade: Double = 0.2
        /// Apparition d'une ligne de liste : montée de 8 pt, 40 ms de décalage entre deux lignes.
        static let cascade = Animation.spring(duration: 0.35, bounce: 0.2)
        static let cascadeOffset: CGFloat = 8
        static let cascadeStagger: Double = 0.04
        /// « Pop » d'un badge ou d'une coche.
        static let pop = Animation.spring(duration: 0.3, bounce: 0.45)
        /// Appui sur une tuile : 96 %, puis rebond.
        static let pressedScale: CGFloat = 0.96
        static let bounce = Animation.spring(duration: 0.25, bounce: 0.5)
    }

    /// Bananes qui traversent l'écran de C9 (« Swoosh! »).
    enum BananaBurst {
        static let count = 12
        /// Durée de la traversée.
        static let duration: Double = 1.6
        /// Les bananes partent les unes après les autres, sur 0,5 s.
        static let spread: Double = 0.5
    }

    /// Confirmation « Copied! » (D1, non spécifiée par la maquette) : durée d'affichage, puis retour à « Copy ».
    enum Copied {
        static let display: Duration = .seconds(2)
        static let transition: Double = 0.2
    }
}
