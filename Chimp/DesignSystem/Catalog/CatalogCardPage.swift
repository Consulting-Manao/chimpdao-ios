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
                        subtitle: "pocket"
                    )
                }
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
