#if DESIGN_CATALOG
import SwiftUI

/// Composants ajoutés pour Recevoir (D1) : QR code, sélecteur de tiroir, lignes de choix, pilule d'adresse,
/// ligne de navigation, étiquette.
struct CatalogReceivePartsPage: View {
    let settings: CatalogSettings
    @State private var selection = "main"
    @State private var isCopied = false

    var body: some View {
        CatalogPage("Receive parts", settings: settings) {
            section("QR code") {
                HStack {
                    Spacer()
                    ChimpQRCode(message: "CAIO2SJ6UNDZELXIPQTONOBOURBWJFNNB5DHQWRVUDVZVPZRJLAZVOX2")
                    Spacer()
                }
                Text("Generated on the phone by Core Image, error correction H. White in both themes.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                HStack {
                    Spacer()
                    ChimpQRCode(message: nil, side: 120)
                    Spacer()
                }
            }

            section("Drawer picker") {
                ChimpDrawerPicker(label: "Into", icon: .main, title: "Main account") {}
                ChimpDrawerPicker(label: "Into", icon: .card(.jungle), title: "Jungle's wallet") {}
                Text("Single drawer: no arrow, not a button.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpDrawerPicker(label: "Into", icon: .main, title: "Main account")
            }

            section("Drawer options") {
                ChimpDrawerOptionRow(icon: .main, title: "Main account", subtitle: "Any of your cards can spend it", isSelected: selection == "main") {
                    selection = "main"
                }
                ChimpDrawerOptionRow(icon: .card(.jungle), title: "Jungle's wallet", subtitle: "Only this card can spend it", isSelected: selection == "jungle") {
                    selection = "jungle"
                }
                ChimpDrawerOptionRow(icon: .card(.banana), title: "Banana's wallet", isSelected: selection == "banana") {
                    selection = "banana"
                }
            }

            section("Address pill") {
                HStack {
                    Spacer()
                    ChimpAddressPill(address: "CAIO2SJ6…AZVOX2", isCopied: isCopied) { isCopied.toggle() }
                    Spacer()
                }
            }

            section("Navigation row and tag") {
                ChimpNavigationRow(title: "Add money from another chain", subtitle: "See a live price from NEAR Intents") {}
                ChimpTagBadge(text: "Testnet", systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            CatalogSectionTitle(title)
            content()
        }
    }
}

#Preview {
    NavigationStack {
        CatalogReceivePartsPage(settings: CatalogSettings())
    }
}
#endif
