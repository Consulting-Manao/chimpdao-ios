import SwiftUI

/// Motif jungle en mosaïque, posé sur les en-têtes, la barre d'onglets, les écrans pleins et les cartes.
/// Purement décoratif : ignoré par VoiceOver et par les touchers.
struct ChimpPattern: View {
    /// Largeur d'une tuile du motif (420 pt sur les en-têtes, 260 pt sur les cartes).
    var tileWidth: CGFloat = ChimpSize.patternTile
    var opacity: Double = ChimpOpacity.pattern

    /// Hauteur d'une tuile pour la largeur par défaut (420 pt) : le motif se répète tous les `tileHeight` points.
    static let tileHeight: CGFloat = {
        let size = UIImage(resource: .pattern).size
        return size.width > 0 ? ChimpSize.patternTile * size.height / size.width : 251
    }()

    var body: some View {
        GeometryReader { proxy in
            // L'image fait 420 pt de large : on la répète, puis on la réduit pour obtenir la taille de tuile voulue.
            let scale = tileWidth / ChimpSize.patternTile
            Image(.pattern)
                .resizable(resizingMode: .tile)
                .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        Color(.chimpHeader)
            .overlay { ChimpPattern() }
            .frame(height: 200)
        Color(.chimpCardJungle)
            .overlay { ChimpPattern(tileWidth: ChimpSize.patternTileOnCard, opacity: ChimpOpacity.patternOnCard) }
            .frame(height: 120)
    }
}
