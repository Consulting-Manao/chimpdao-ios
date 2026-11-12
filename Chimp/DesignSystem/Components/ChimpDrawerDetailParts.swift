import SwiftUI

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
    ChimpGroupedList(rows: [
        ChimpGroupedRow(id: "rename", title: "Rename & colour") {},
        ChimpGroupedRow(id: "remove", title: "Remove from account") {},
        ChimpGroupedRow(id: "lost", title: "I lost this card", tone: .destructive) {},
    ])
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}
