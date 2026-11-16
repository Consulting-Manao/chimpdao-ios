#if DESIGN_CATALOG
import SwiftUI

struct CatalogCardPage: View {
    /// Démonstration du choix d'allure (« Rename & colour ») : la couleur et le dessin se choisissent côte à côte.
    @State private var swatchColor: ChimpCardColor = .jungle
    @State private var usesDesign = false

    private var sampleArt: CardArt? { UIImage(named: "CardArtSample").map { CardArt(image: $0, design: "Hamac") } }

    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Card", settings: settings) {
            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("Colours")
                ForEach(ChimpCardColor.allCases) { color in
                    ChimpCard(
                        name: color.rawValue.capitalized,
                        color: color,
                        number: "0421",
                        amount: "$62.50",
                        subtitle: "on card"
                    )
                }
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("NFT design")
                Text("In « Rename & colour », a card whose NFT carries a card-shaped design gets one more swatch, next to the colours. Pick it and the design takes the whole face: the design alone, no name or number on top. The colour stays picked underneath. A design that isn't card-shaped (collection portraits) isn't offered at all.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ChimpCard(
                    name: "Jungle", color: swatchColor, number: "0421", amount: "$62.50", subtitle: "on card",
                    cardKey: usesDesign ? "art" : nil
                )
                .animation(.easeInOut(duration: 0.2), value: usesDesign)
                ChimpColorSwatchPicker(selection: $swatchColor, design: sampleArt, designSelection: $usesDesign)
                HStack(spacing: ChimpSpacing.m) {
                    ChimpCard(name: "Jungle", color: .jungle, number: "0421", cardKey: "art")
                    ChimpCard(name: "Banana", color: .banana, number: "0588")
                }
            }
            .environment(\.chimpCardArt) { key in
                key == "art" ? UIImage(named: "CardArtSample").map { CardArt(image: $0, design: "Hamac") } : nil
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("Side by side (B1)")
                HStack(spacing: ChimpSpacing.m) {
                    ChimpCard(name: "Jungle", color: .jungle, number: "0421", amount: "$62.50")
                    ChimpCard(name: "Banana", color: .banana, number: "0588", amount: "$12.00")
                }
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("Without amount (A5, G1b)")
                ChimpCard(name: "Leaf", color: .leaf, number: "0913")
                    .frame(maxWidth: 220)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CatalogCardPage(settings: CatalogSettings())
    }
}
#endif
