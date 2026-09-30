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
                .padding(.vertical, ChimpSpacing.xs)
                .padding(.horizontal, ChimpSpacing.m)
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
            .padding(.bottom, 11)
            .padding(.horizontal, ChimpSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpSurface))
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
        .background { shape.fill(Color(.chimpOutline)).offset(x: ChimpShadow.tile.x, y: ChimpShadow.tile.y) }
        .accessibilityElement(children: .combine)
    }
}

/// Plateau des cartes qui peuvent signer pour Main (B2e « key tray ») : fond brun à motif, ombre intérieure, les cartes
/// en éventail, une phrase dessous. Une carte : au centre ; deux : comme la maquette ; au-delà : réparties et superposées.
struct ChimpKeyTray: View {
    struct Card: Identifiable {
        let id: String
        let name: String
        let color: ChimpCardColor
        let number: String
    }

    let cards: [Card]
    let caption: Text

    private let cardWidth: CGFloat = 170
    private let trayHeight: CGFloat = 118

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.panel)
        VStack(spacing: ChimpSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        ChimpCard(name: card.name, color: card.color, number: card.number)
                            .frame(width: cardWidth)
                            .rotationEffect(.degrees(angle(index)))
                            .offset(x: x(index, width: proxy.size.width), y: index.isMultiple(of: 2) ? 6 : 0)
                    }
                }
            }
            .frame(height: trayHeight)
            caption
                .chimpFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpOnHeaderSecondary)
        }
        .padding(.top, ChimpSpacing.lg)
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.bottom, ChimpSpacing.m)
        .background {
            Color(.chimpCardJungle)
                .overlay { ChimpPattern(tileWidth: 360) }
                .overlay(alignment: .top) {
                    // Ombre intérieure du haut (maquette : `inset 0 6px 0 rgba(0,0,0,.25)`).
                    Color.black.opacity(0.25).frame(height: 6)
                }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
        .accessibilityElement(children: .combine)
    }

    /// Inclinaison : −7° à gauche, +6° à droite (maquette), −4° pour une carte seule.
    private func angle(_ index: Int) -> Double {
        guard cards.count > 1 else { return -4 }
        return -7 + 13 * Double(index) / Double(cards.count - 1)
    }

    /// Position : 4 pt des bords pour les cartes extrêmes, les autres réparties entre elles ; au centre pour une seule.
    private func x(_ index: Int, width: CGFloat) -> CGFloat {
        let free = max(width - cardWidth - 8, 0)
        guard cards.count > 1 else { return 4 + free / 2 }
        return 4 + free * CGFloat(index) / CGFloat(cards.count - 1)
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
        ChimpKeyTray(cards: [
            .init(id: "j", name: "Jungle", color: .jungle, number: "0421"),
            .init(id: "b", name: "Banana", color: .banana, number: "0688"),
        ], caption: Text("Tap either one to sign for Main"))
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
