import SwiftUI

/// Style d'un bouton « surface » (tuile d'action, carte tiroir) : fond, contour épais et ombre dure.
/// À l'appui, il descend sur son ombre, qui disparaît (règle validée le 2026-09-28).
/// Désactivé : opacité 45 %.
struct ChimpSurfaceButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    let fill: Color
    var shadow: ChimpShadow = .tile

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .background { shape.fill(fill) }
            .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .offset(x: isPressed ? shadow.x : 0, y: isPressed ? shadow.y : 0)
            .background {
                shape.fill(Color(.chimpOutline)).offset(x: shadow.x, y: shadow.y)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : ChimpOpacity.disabled)
            // Enfoncé d'un coup, puis relâché avec un petit rebond (sauf « Réduire les animations »).
            .animation(isPressed || reduceMotion ? .easeOut(duration: ChimpMotion.Press.duration) : ChimpMotion.Micro.bounce, value: isPressed)
    }
}
