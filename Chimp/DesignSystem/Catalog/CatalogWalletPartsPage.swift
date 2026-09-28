#if DESIGN_CATALOG
import SwiftUI

/// Composants ajoutés pour le Wallet : en-tête de solde, tuiles, carte tiroir, pilule, bandeaux.
struct CatalogWalletPartsPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Wallet parts", settings: settings) {
            section("Balance header") {
                VStack(spacing: ChimpSpacing.l) {
                    ChimpBalanceHeader(
                        firstName: "Léo",
                        label: "Your whole banana pile",
                        total: "$1,485.00",
                        change: "+$6.20 this week",
                        onSettings: {}
                    )
                    ChimpBalanceHeader(label: "Your whole banana pile", total: "$0.00")
                }
                // Hors du haut de l'écran : pas d'empiètement sur la barre d'état.
                .environment(\.chimpScreenInsets, EdgeInsets())
                .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
            }

            section("Action tiles") {
                HStack(spacing: ChimpSize.keypadSpacing) {
                    ChimpActionTile(title: "Send", systemImage: "arrow.up.right", isPrimary: true) {}
                    ChimpActionTile(title: "Receive", systemImage: "arrow.down.left") {}
                    ChimpActionTile(title: "Move", systemImage: "arrow.up.arrow.down") {}
                    ChimpActionTile(title: "Swap", systemImage: "arrow.left.arrow.right") {}
                }
                Text("Disabled").chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                HStack(spacing: ChimpSize.keypadSpacing) {
                    ChimpActionTile(title: "Send", systemImage: "arrow.up.right", isPrimary: true) {}.disabled(true)
                    ChimpActionTile(title: "Receive", systemImage: "arrow.down.left") {}
                    ChimpActionTile(title: "Move", systemImage: "arrow.up.arrow.down") {}.disabled(true)
                    ChimpActionTile(title: "Swap", systemImage: "arrow.left.arrow.right") {}.disabled(true)
                }
            }

            section("Drawer card") {
                ChimpDrawerCard(label: "Main", amount: "$1,320.00", ready: "$820", growing: "$500") {}
                ChimpDrawerCard(label: "Main", amount: "$1,320.00", ready: "$820") {}
                ChimpDrawerCard(label: "Main", amount: "$1,320.00") {}
            }

            section("Pill") {
                HStack(alignment: .firstTextBaseline) {
                    Text("My cards").chimpFont(.displayS)
                    Spacer()
                    ChimpPillButton("+ Add") {}
                }
                Text("Visual height about 25 pt, touch area 44 pt.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
            }

            section("Notice banner") {
                ChimpNoticeBanner(text: "Couldn't refresh. Balances from 10:42.", marker: .error) {
                    ChimpPillButton("Retry") {}
                }
                ChimpNoticeBanner(text: "It's from Jungle's wallet, so only that card works.", marker: .card(.jungle))
                ChimpNoticeBanner(text: "Looking is free. Moving money takes a tap.")
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
        CatalogWalletPartsPage(settings: CatalogSettings())
    }
}
#endif
