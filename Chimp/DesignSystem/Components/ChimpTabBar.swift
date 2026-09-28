import SwiftUI

/// Onglets de l'app (B1, F1, I1).
enum ChimpTab: String, CaseIterable, Identifiable {
    case wallet
    case grow
    case activity

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wallet: "Wallet"
        case .grow: "Grow"
        case .activity: "Activity"
        }
    }
}

/// Barre d'onglets (« Chimp Nav » dans la maquette) : fond `chimpHeader` + motif,
/// onglet actif en pilule jaune. À placer tout en bas de l'écran : son fond passe sous la barre d'accueil.
struct ChimpTabBar: View {
    @Binding var selection: ChimpTab
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        HStack(spacing: ChimpSpacing.sm) {
            ForEach(ChimpTab.allCases) { tab in
                ChimpTabButton(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
        }
        .padding(ChimpSpacing.tabBar(for: screenInsets))
        .frame(maxWidth: .infinity)
        .background {
            Color(.chimpHeader)
                .overlay { ChimpPattern() }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.chimpOutline))
                        .frame(height: ChimpBorder.regular)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tab bar"))
    }
}

private struct ChimpTabButton: View {
    let tab: ChimpTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.tab)
        Button(action: action) {
            Text(tab.title)
                .chimpFont(.tab)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpOnHeaderSecondary))
                // Rembourrage de la maquette + contour de 3 pt (transparent sur les onglets inactifs).
                .padding(.top, 10 + ChimpBorder.regular)
                .padding(.bottom, 9 + ChimpBorder.regular)
                .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
                .background {
                    if isSelected {
                        shape.fill(Color(.chimpOutlineOnHeader))
                            .offset(x: ChimpShadow.raised.x, y: ChimpShadow.raised.y)
                        shape.fill(Color(.chimpAccent))
                        shape.strokeBorder(Color(.chimpOutlineOnHeader), lineWidth: ChimpBorder.regular)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChimpTabBarPreview: View {
    @State private var selection = ChimpTab.wallet

    var body: some View {
        VStack {
            Spacer()
            Text(selection.title).chimpFont(.displayL)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpTabBar(selection: $selection)
        }
    }
}

#Preview("Light") {
    ChimpTabBarPreview()
}

#Preview("Dark") {
    ChimpTabBarPreview()
        .preferredColorScheme(.dark)
}
