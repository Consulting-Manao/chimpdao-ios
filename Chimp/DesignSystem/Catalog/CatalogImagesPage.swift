#if DESIGN_CATALOG
import SwiftUI

/// Images du design (Assets.xcassets/Images), à leur plus grande taille d'affichage dans la maquette.
struct CatalogImagesPage: View {
    let settings: CatalogSettings

    private static let images: [(name: String, resource: ImageResource, height: CGFloat)] = [
        ("TileLogo", .tileLogo, 56),
        ("TileHead", .tileHead, 150),
        ("TileBanana", .tileBanana, 58),
        ("ChimpyStand", .chimpyStand, 230),
        ("ChimpyBanana", .chimpyBanana, 230),
        ("ChimpyHamac", .chimpyHamac, 169),
        ("ChimpyCrawl", .chimpyCrawl, 180),
    ]

    var body: some View {
        CatalogPage("Images", settings: settings) {
            ForEach(Self.images, id: \.name) { image in
                VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                    Image(image.resource)
                        .resizable()
                        .scaledToFit()
                        .frame(height: image.height)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Text(verbatim: image.name).chimpFont(.rowTitle)
                }
                .padding(ChimpSpacing.ml)
                .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                // Aperçu brut du motif ; le vrai modificateur de fond arrive avec l'en-tête (étape B).
                Color(.chimpHeader)
                    .frame(height: 160)
                    .overlay {
                        Image(.pattern)
                            .resizable(resizingMode: .tile)
                            .opacity(ChimpOpacity.pattern)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                    .accessibilityHidden(true)
                Text(verbatim: "Pattern").chimpFont(.rowTitle)
                Text("Tiled every 420 pt, opacity 0.14, on chimpHeader").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            }
            .padding(ChimpSpacing.ml)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    NavigationStack {
        CatalogImagesPage(settings: CatalogSettings())
    }
}
#endif
