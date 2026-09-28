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
            content.phaseAnimator([0.0, 1.0]) { view, phase in
                view.offset(y: -amplitude * phase)
            } animation: { _ in
                // Chaque moitié (montée, descente) est adoucie, comme les deux intervalles de la keyframe CSS.
                .easeInOut(duration: duration / 2)
            }
        }
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
