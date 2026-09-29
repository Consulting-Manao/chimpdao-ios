import SwiftUI

/// Flottement vertical de Chimpy et des cartes (animation « bob » de la maquette) :
/// monte de 7 pt puis redescend, en boucle. S'arrête si « Réduire les animations » est activé.
private struct ChimpBobModifier: ViewModifier {
    let duration: Double
    let amplitude: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Horloge plutôt qu'animation SwiftUI : seul le décalage vertical bouge. Une animation en boucle
            // (`phaseAnimator`) animait aussi les changements de taille au premier affichage (Chimpy qui « grandit »).
            TimelineView(.animation) { context in
                content.offset(y: -amplitude * Self.height(at: context.date.timeIntervalSinceReferenceDate, duration: duration))
            }
        }
    }

    /// Hauteur relative (0 à 1) : montée puis descente, chaque moitié adoucie (ease-in-out),
    /// comme les deux intervalles de la keyframe CSS.
    static func height(at time: TimeInterval, duration: Double) -> CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: duration) / duration
        let half = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2
        return half * half * (3 - 2 * half)
    }
}

extension View {
    /// Fait flotter la vue. `duration` : durée d'un aller-retour complet
    /// (calme : 3 à 5 s selon l'écran ; nerveux : 1,2 à 1,6 s pour les easter eggs).
    func chimpBob(duration: Double, amplitude: CGFloat = ChimpMotion.Bob.amplitude) -> some View {
        modifier(ChimpBobModifier(duration: duration, amplitude: amplitude))
    }
}

#Preview {
    Image(.chimpyBanana)
        .resizable()
        .scaledToFit()
        .frame(height: 230)
        .chimpBob(duration: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.chimpBackground))
}
