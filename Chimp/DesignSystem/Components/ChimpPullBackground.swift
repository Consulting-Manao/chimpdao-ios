import SwiftUI

/// Distance tirée, dans un objet à part : seul le fond la lit, l'écran n'est pas recalculé pendant le geste.
@Observable
final class ChimpPull {
    var distance: CGFloat = 0
}

/// Fond révélé au-dessus d'un en-tête quand on tire pour rafraîchir : la couleur de l'en-tête et son motif, décalé
/// de la distance tirée pour continuer exactement celui de l'en-tête (pas de raccord visible). Derrière le défilement,
/// donc sous la roue de chargement. Wallet (retour de Barth, 2026-10-02) et Grow (même rendu, 2026-11-05).
struct ChimpPullBackground: View {
    let pull: ChimpPull
    let color: Color
    var patternOpacity: Double = ChimpOpacity.pattern

    var body: some View {
        // Seulement la bande découverte au-dessus de l'en-tête (rien au repos) : sous un en-tête plus court que le Wallet,
        // un fond de hauteur fixe dépassait derrière les pastilles de Grow (retour de Barth, 2026-11-06). 2 pt de plus,
        // cachés sous l'en-tête, évitent un liseré.
        let height = pull.distance + 2
        let tile = ChimpPattern.tileHeight
        color
            .overlay(alignment: .top) {
                ChimpPattern(opacity: patternOpacity)
                    .frame(height: height + tile)
                    .offset(y: pull.distance.truncatingRemainder(dividingBy: tile) - tile)
            }
            .frame(height: height)
            .clipped()
    }
}
