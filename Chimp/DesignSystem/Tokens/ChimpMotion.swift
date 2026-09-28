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
}
