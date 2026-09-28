import SwiftUI

/// Icône d'un actif (DESIGN_NOTES §2.4) : USDC = carré vert avec « $ », XLM = logo Chimp (`tile-logo`).
enum ChimpAssetGlyph: Equatable {
    case usdc
    case xlm
}

/// Dessin de l'icône d'un actif dans un carré de la taille demandée, contour compris.
struct ChimpAssetIcon: View {
    let glyph: ChimpAssetGlyph
    let size: CGFloat
    var border: CGFloat = ChimpBorder.regular

    var body: some View {
        Group {
            switch glyph {
            case .usdc:
                let shape = RoundedRectangle(cornerRadius: size / 3)
                shape
                    .fill(Color(.chimpCardLeaf))
                    .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: border) }
                    .overlay {
                        Text(verbatim: "$")
                            .font(Font(ChimpFontFamily.luckiestGuy.uiFont(size: size * 0.5)))
                            .foregroundStyle(Color(.chimpOnCardBright))
                            .offset(y: size * 0.04)
                    }
            case .xlm:
                Image(.tileLogo)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pilule de choix de l'actif sous le montant (« paid in USDC ▾ », C2) : fond `chimpSurface`, contour 3,
/// icône de l'actif, libellé, flèche. Zone tactile agrandie à 44 pt sans changer la mise en page.
struct ChimpAssetPill: View {
    let glyph: ChimpAssetGlyph
    /// Code de l'actif (« USDC »), affiché tel quel.
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.s) {
                ChimpAssetIcon(glyph: glyph, size: 18 + ChimpBorder.thin, border: ChimpBorder.thin)
                Text(verbatim: title)
                    .chimpFont(.pill)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .black))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.chimpTextPrimary)
            .padding(.vertical, ChimpSpacing.xs + ChimpBorder.regular)
            .padding(.horizontal, 13 + ChimpBorder.regular)
            .cartoonSurface(Capsule(), fill: Color(.chimpSurface))
            .contentShape(Rectangle().inset(by: -ChimpSpacing.xs))
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityHint(Text("Choose what to send"))
    }
}

/// Pastille de choix rapide (« $10 », « $25 », « All », C2) : Luckiest Guy 13, contour 3.
/// La pastille choisie est jaune. Désactivée : opacité 45 %.
struct ChimpChoiceChip: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.isSelected = isSelected
        self.action = action
    }

    /// Libellé affiché tel quel, sans traduction (un montant déjà formaté : « 25 »).
    init(verbatim title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .chimpFont(.pill)
                .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
                .padding(.vertical, ChimpSpacing.xs + ChimpBorder.regular)
                .padding(.horizontal, 13 + ChimpBorder.regular)
                .cartoonSurface(Capsule(), fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface))
                .contentShape(Rectangle().inset(by: -ChimpSpacing.xs))
                .opacity(isEnabled ? 1 : ChimpOpacity.disabled)
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChimpAssetViewsPreview: View {
    @State private var selection = 25

    var body: some View {
        VStack(spacing: ChimpSpacing.xl) {
            HStack(spacing: ChimpSpacing.l) {
                ChimpAssetIcon(glyph: .usdc, size: 38)
                ChimpAssetIcon(glyph: .xlm, size: 38)
            }
            ChimpAssetPill(glyph: .usdc, title: "USDC") {}
            HStack(spacing: ChimpSpacing.s) {
                ForEach([10, 25, 50], id: \.self) { value in
                    ChimpChoiceChip(verbatim: "\(value)", isSelected: selection == value) { selection = value }
                }
                ChimpChoiceChip("Max", isSelected: false) {}
                    .disabled(true)
            }
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpAssetViewsPreview()
}

#Preview("Dark") {
    ChimpAssetViewsPreview()
        .preferredColorScheme(.dark)
}
