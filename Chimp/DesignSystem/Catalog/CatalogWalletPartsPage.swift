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

            section("Drawer page (B1)") {
                VStack(spacing: 0) {
                    ChimpDrawerBanner(scene: .main, title: Text(verbatim: "Main")) {}
                    ChimpSplitPanel(
                        kind: "MAIN · SHARED", total: "$1,320.00", ready: "$820", growing: "$500",
                        readyWeight: 820, growingWeight: 500, address: "CAIO2SJ6…VOX2QF"
                    )
                    .padding(.horizontal, ChimpSpacing.m)
                    .padding(.top, -ChimpDrawerBanner.panelOverlap)
                    .padding(.bottom, ChimpSpacing.l)
                }
                .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                ForEach(ChimpCardColor.allCases) { color in
                    VStack(spacing: 0) {
                        ChimpDrawerBanner(
                            scene: .card(name: color.rawValue.capitalized, color: color, number: "0421"),
                            title: Text(verbatim: "\(color.rawValue.capitalized) card")
                        ) {}
                        ChimpSplitPanel(
                            kind: "N°0421 · ONLY THIS CARD SIGNS", total: "$62.50", ready: "$62.50", growing: nil,
                            readyWeight: 1, growingWeight: 0
                        )
                        .padding(.horizontal, ChimpSpacing.m)
                        .padding(.top, -ChimpDrawerBanner.panelOverlap)
                        .padding(.bottom, ChimpSpacing.l)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                }
                // Une carte qui affiche le dessin de son NFT : le bandeau reprend le fond du dessin, sans sticker.
                VStack(spacing: 0) {
                    ChimpDrawerBanner(
                        scene: .card(name: "Jungle", color: .pink, number: "0011", key: "art"),
                        title: Text(verbatim: "Jungle card")
                    ) {}
                    ChimpSplitPanel(
                        kind: "N°0011 · ONLY THIS CARD SIGNS", total: "$5.51", ready: "$5.51", growing: nil,
                        readyWeight: 1, growingWeight: 0
                    )
                    .padding(.horizontal, ChimpSpacing.m)
                    .padding(.top, -ChimpDrawerBanner.panelOverlap)
                    .padding(.bottom, ChimpSpacing.l)
                }
                .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                .environment(\.chimpCardArt) { key in
                    guard key == "art", let image = UIImage(named: "CardArtSample") else { return nil }
                    return CardArt(
                        image: image, design: "Hamac",
                        background: CardArtGateway.backgroundColor(of: image).map(Color.init(uiColor:))
                    )
                }

                Text("Empty drawer").chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                ChimpSplitPanel(kind: "MAIN · SHARED", total: "$0.00", ready: "$0", growing: nil, readyWeight: 0, growingWeight: 0)
                ChimpDrawerListTitle(title: "Ready to spend", amount: "$820.00")
                ChimpHoldingRow(name: "US Dollar", detail: "620 USDC", amount: "$620.00") { ChimpAssetIcon(glyph: .usdc, size: 38) }
                ChimpDrawerListTitle(title: "Growing", amount: "$500.00", tint: Color(.chimpPositive))
                ChimpHoldingRow(name: "XLM vault", detail: "+0.48 XLM since 22 Sep", detailColor: Color(.chimpPositive), amount: "2,000.48 XLM") {
                    ChimpProtocolLogo(mark: .defindex, size: 38)
                }
                HStack(spacing: ChimpSize.keypadSpacing) {
                    ChimpActionTile(title: "Send", systemImage: "arrow.up.right", isPrimary: true) {}
                    ChimpActionTile(title: "Move", systemImage: "arrow.up.arrow.down") {}
                    ChimpActionTile(title: "Swap", systemImage: "arrow.left.arrow.right") {}
                    ChimpActionTile(title: "Grow", systemImage: "leaf", image: .tileBanana) {}
                }
            }
            .environment(\.chimpScreenInsets, EdgeInsets())

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
