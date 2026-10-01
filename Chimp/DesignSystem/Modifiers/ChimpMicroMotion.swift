import SwiftUI

/// Micro-animations (retour du call avec Pamphile, 2026-10-01). Toutes respectent « Réduire les animations » : rien ne
/// bouge alors, seul un fondu court remplace le mouvement.

/// Montant qui défile chiffre par chiffre quand il change (solde du Wallet, tiroirs, « avant → après »).
private struct ChimpRollingNumber<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? .easeInOut(duration: ChimpMotion.Micro.fade) : ChimpMotion.Micro.roll, value: value)
    }
}

/// Apparition en cascade d'une ligne de liste : elle monte de quelques points en apparaissant, avec un léger décalage
/// selon sa place (les 8 premières seulement : une longue liste n'attend pas).
private struct ChimpCascadeAppear: ViewModifier {
    let index: Int
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : ChimpMotion.Micro.cascadeOffset)
            .onAppear {
                guard !isShown else { return }
                let delay = Double(min(index, 8)) * ChimpMotion.Micro.cascadeStagger
                withAnimation(reduceMotion ? .easeInOut(duration: ChimpMotion.Micro.fade) : ChimpMotion.Micro.cascade.delay(delay)) {
                    isShown = true
                }
            }
    }
}

/// Petit « pop » quand un élément apparaît (badge « is ready », coche « PIN ready », « Copied! »).
private struct ChimpPopIn: ViewModifier {
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShown || reduceMotion ? 1 : 0.6)
            .opacity(isShown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: ChimpMotion.Micro.fade) : ChimpMotion.Micro.pop) { isShown = true }
            }
    }
}

extension View {
    /// Le montant défile quand `value` change.
    func chimpRollingNumber<Value: Equatable>(_ value: Value) -> some View {
        modifier(ChimpRollingNumber(value: value))
    }

    /// Apparition en cascade (ligne `index` d'une liste).
    func chimpCascadeAppear(index: Int) -> some View {
        modifier(ChimpCascadeAppear(index: index))
    }

    /// Petit « pop » à l'apparition.
    func chimpPopIn() -> some View {
        modifier(ChimpPopIn())
    }
}

/// Bouton qui s'enfonce légèrement sous le doigt puis rebondit (tuiles d'action, lignes touchables).
struct ChimpBouncyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? ChimpMotion.Micro.pressedScale : 1)
            .opacity(configuration.isPressed ? ChimpOpacity.pressed : 1)
            .animation(reduceMotion ? nil : ChimpMotion.Micro.bounce, value: configuration.isPressed)
    }
}
