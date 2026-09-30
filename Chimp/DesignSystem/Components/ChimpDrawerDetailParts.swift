import SwiftUI

/// Ligne d'un actif dans le détail d'un tiroir (B2, B3 « READY TO SPEND ») : icône de 38 pt, nom (« US Dollar »),
/// montant dans l'actif (« 620.00 USDC »), valeur en dollars à droite (Space Mono). Fond `chimpSurface`, contour 3,
/// rayon 18, sans ombre.
struct ChimpAssetRow: View {
    let glyph: ChimpAssetGlyph
    let title: String
    /// Montant dans l'actif, déjà formaté.
    let subtitle: String
    /// Valeur en dollars ; masquée si `nil` (prix inconnu).
    var value: String?

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            ChimpAssetIcon(glyph: glyph, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                Text(verbatim: subtitle)
                    .chimpFont(.captionS)
                    .foregroundStyle(.chimpTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(verbatim: value)
                    .chimpFont(.monoValue)
                    .foregroundStyle(.chimpTextPrimary)
            }
        }
        .padding(.vertical, 11 + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }
}

/// Pastille d'une carte qui peut signer (B2, B3) : carré de sa couleur, nom. Fond `chimpSurface`, contour 2.
struct ChimpSignerChip: View {
    let name: String
    let color: ChimpCardColor

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.fill)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                .frame(width: 12 + 2 * ChimpBorder.thin, height: 12 + 2 * ChimpBorder.thin)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextPrimary)
        }
        .padding(.vertical, 5 + ChimpBorder.thin)
        .padding(.horizontal, 11 + ChimpBorder.thin)
        .background(Capsule().fill(Color(.chimpSurface)))
        .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
    }
}

/// Une ligne de `ChimpGroupedList` : titre, valeur facultative, chevron « > ».
struct ChimpGroupedRow: Identifiable {
    enum Tone {
        case normal
        /// Texte `chimpNegative` (« I lost this card »).
        case destructive
    }

    let id: String
    let title: LocalizedStringKey
    var value: String?
    var tone: Tone = .normal
    let action: () -> Void
}

/// Liste groupée de lignes cliquables (B3 « THIS CARD », réglages I2) : fond `chimpSurface`, contour 3, rayon 18,
/// lignes séparées par un trait `chimpSurfaceSecondary` de 2 pt.
struct ChimpGroupedList: View {
    let rows: [ChimpGroupedRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.chimpSurfaceSecondary))
                        .frame(height: ChimpBorder.thin)
                        .accessibilityHidden(true)
                }
                Button(action: row.action) {
                    HStack(spacing: ChimpSpacing.sm) {
                        Text(row.title)
                            .chimpFont(.rowTitle)
                            .foregroundStyle(row.tone == .destructive ? Color(.chimpNegative) : Color(.chimpTextPrimary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let value = row.value {
                            Text(verbatim: value)
                                .chimpFont(.captionS)
                                .foregroundStyle(.chimpTextSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.chimpTextSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 15)
                    .frame(minHeight: ChimpSize.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityElement(children: .combine)
            }
        }
        .padding(ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: ChimpSpacing.m) {
        HStack(spacing: ChimpSpacing.s) {
            ChimpSignerChip(name: "Jungle", color: .jungle)
            ChimpSignerChip(name: "Banana", color: .banana)
        }
        ChimpAssetRow(glyph: .usdc, title: "US Dollar", subtitle: "620.00 USDC", value: "$620.00")
        ChimpAssetRow(glyph: .xlm, title: "Stellar", subtitle: "800 XLM", value: "$200.00")
        ChimpGroupedList(rows: [
            ChimpGroupedRow(id: "rename", title: "Rename & colour") {},
            ChimpGroupedRow(id: "remove", title: "Remove from account") {},
            ChimpGroupedRow(id: "lost", title: "I lost this card", tone: .destructive) {},
        ])
    }
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}
