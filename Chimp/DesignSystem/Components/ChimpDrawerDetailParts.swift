import SwiftUI

/// Tuile d'un actif dans le détail d'un tiroir (B2e, B3 : « USDC · READY ») : bandeau coloré en Space Mono, valeur en
/// Luckiest Guy 26, détail dessous. Fond `chimpSurface`, contour 3, rayon 20, ombre `3 3`.
struct ChimpAssetTile: View {
    /// Texte du bandeau, déjà en majuscules (« USDC · READY »).
    let band: String
    let bandFill: Color
    var bandInk: Color = Color(.chimpOnCardBright)
    /// Valeur principale (« $620 », ou « 800 XLM » sans prix).
    let value: String
    /// Détail (« 620 USDC ») ; masqué si `nil`.
    var detail: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: band)
                .chimpFont(.labelS)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(bandInk)
                // Le contour (3 pt) est dessiné par-dessus : il s'ajoute aux marges de la maquette (6 et 12 pt).
                .padding(.top, ChimpSpacing.xs + ChimpBorder.regular)
                .padding(.bottom, ChimpSpacing.xs)
                .padding(.horizontal, ChimpSpacing.m + ChimpBorder.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bandFill)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.chimpOutline)).frame(height: ChimpBorder.regular)
                }
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                Text(verbatim: value)
                    .chimpFont(.amountM)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.chimpTextPrimary)
                if let detail {
                    Text(verbatim: detail)
                        .chimpFont(.captionStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.chimpTextSecondary)
                }
            }
            .padding(.top, 9)
            .padding(.bottom, 11 + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.m + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpSurface))
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
        .background { shape.fill(Color(.chimpOutline)).offset(x: ChimpShadow.tile.x, y: ChimpShadow.tile.y) }
        .accessibilityElement(children: .combine)
    }
}

/// Une ligne de « LATELY » (B2r) : titre, heure et jour, montant en Space Mono (vert s'il entre). Séparées par un trait
/// `chimpSurfaceSecondary` de 2 pt, sans fond.
struct ChimpRecentRow: View {
    let title: String
    /// « 11:20 · today ».
    let meta: String
    let amount: String?
    var isIncoming = false

    var body: some View {
        HStack(spacing: ChimpSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .chimpFont(.ticketTitle)
                    .foregroundStyle(.chimpTextPrimary)
                    .lineLimit(2)
                Text(verbatim: meta)
                    .chimpFont(.captionS)
                    .foregroundStyle(.chimpTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let amount {
                Text(verbatim: amount)
                    .chimpFont(.ticketAmount)
                    .foregroundStyle(isIncoming ? Color(.chimpPositive) : Color(.chimpTextPrimary))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
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
        ChimpRecentRow(title: "Moved to Jungle", meta: "11:20 · today", amount: "−$50.00")
        ChimpRecentRow(title: "Shop sale", meta: "16:05 · yesterday", amount: "+$12.50", isIncoming: true)
        HStack(spacing: ChimpSpacing.m) {
            ChimpAssetTile(band: "USDC · READY", bandFill: Color(.chimpCardLeaf), value: "$620", detail: "620 USDC")
            ChimpAssetTile(band: "XLM · READY", bandFill: Color(.chimpCardBanana), value: "$200", detail: "800 XLM")
        }
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
