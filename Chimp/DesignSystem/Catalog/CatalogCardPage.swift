#if DESIGN_CATALOG
import SwiftUI

struct CatalogCardPage: View {
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
                Text("A card whose NFT carries a card-shaped design shows it instead of its colour: the design alone, no name or number on top. A design that isn't card-shaped (collection portraits) leaves the colour.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ChimpCard(name: "Jungle", color: .jungle, number: "0421", amount: "$62.50", subtitle: "on card", cardKey: "art")
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
