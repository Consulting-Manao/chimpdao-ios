import SwiftUI

/// C9 « Swoosh! » : une douzaine de bananes traversent l'écran en tournoyant, une seule fois (retour du call avec Pamphile,
/// 2026-10-01). Décoratif : ni touchable, ni lu par VoiceOver. **Rien** avec « Réduire les animations ».
///
/// La banane est celle de `tile-banana`, détourée et peinte en jaune (`BananaSprite`), dessinée sans lissage (pixel art).
struct ChimpBananaBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tirées une fois, à l'apparition : les trajectoires ne changent pas en vol.
    @State private var bananas = (0..<ChimpMotion.BananaBurst.count).map { _ in FlyingBanana.random() }
    @State private var start = Date.now
    @State private var isFinished = false

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(paused: isFinished)) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    let sprite = context.resolve(Image(.bananaSprite).interpolation(.none))
                    for banana in bananas {
                        guard let frame = banana.frame(at: elapsed, in: size) else { continue }
                        context.drawLayer { layer in
                            layer.translateBy(x: frame.center.x, y: frame.center.y)
                            layer.rotate(by: frame.angle)
                            layer.draw(sprite, in: CGRect(x: -frame.side / 2, y: -frame.side / 2, width: frame.side, height: frame.side))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(ChimpMotion.BananaBurst.duration + ChimpMotion.BananaBurst.spread + 0.1))
                isFinished = true
            }
        }
    }
}

/// Une banane : elle part d'en bas, traverse l'écran en arc et sort par le haut, en tournant.
struct FlyingBanana {
    /// Départ et arrivée en fractions de l'écran (0 = gauche / haut, 1 = droite / bas).
    let startX: Double
    let endX: Double
    /// Hauteur de l'arc, en fraction de la hauteur de l'écran.
    let arc: Double
    let side: Double
    /// Tours complets pendant la traversée (signe = sens).
    let turns: Double
    let delay: Double

    static func random() -> FlyingBanana {
        let startX = Double.random(in: 0...1)
        return FlyingBanana(
            startX: startX,
            endX: startX + Double.random(in: -0.6...0.6),
            arc: Double.random(in: 0.05...0.2),
            side: Double.random(in: 34...58),
            turns: Double.random(in: 0.6...1.6) * (Bool.random() ? 1 : -1),
            delay: Double.random(in: 0...ChimpMotion.BananaBurst.spread)
        )
    }

    /// Position, angle et taille à l'instant `elapsed` ; `nil` avant le départ ou après la sortie.
    func frame(at elapsed: Double, in size: CGSize) -> (center: CGPoint, angle: Angle, side: Double)? {
        let progress = (elapsed - delay) / ChimpMotion.BananaBurst.duration
        guard progress >= 0, progress <= 1 else { return nil }
        let x = startX + (endX - startX) * progress
        // De 10 % sous l'écran à 15 % au-dessus, avec un arc vers le côté.
        let y = 1.1 - 1.25 * progress
        let bend = sin(progress * .pi) * arc * (endX >= startX ? 1 : -1)
        return (
            CGPoint(x: (x + bend) * size.width, y: y * size.height),
            .degrees(360 * turns * progress),
            side
        )
    }
}
