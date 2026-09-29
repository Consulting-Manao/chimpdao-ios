import SwiftUI

/// Carte « What happens » (C4, réutilisée par Move, Grow, G4 à G7) : étapes numérotées dans des pastilles
/// jaunes de 30 pt, reliées par un trait `chimpSurfaceSecondary`. Fond `chimpSurface`, contour 3, rayon 22, ombre `4 4`.
struct ChimpReviewSteps: View {
    let steps: [Text]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.chimpSurfaceSecondary))
                        .frame(width: ChimpBorder.regular, height: ChimpSpacing.ml)
                        .padding(.vertical, ChimpSpacing.xxs)
                        .padding(.leading, (ChimpSize.reviewStepBadge - ChimpBorder.regular) / 2)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: ChimpSpacing.m) {
                    Text(verbatim: "\(index + 1)")
                        .chimpFont(.buttonSmall)
                        .foregroundStyle(.chimpOnAccent)
                        .frame(width: ChimpSize.reviewStepBadge, height: ChimpSize.reviewStepBadge)
                        .background(Circle().fill(Color(.chimpAccent)))
                        .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                        .accessibilityHidden(true)
                    step
                        .chimpFont(.reviewStep)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 7)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(.chimpTextPrimary)
        .padding(ChimpSpacing.lg + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
    }
}

/// Une ligne de `ChimpDetailList` : libellé en majuscules, valeur en dessous.
struct ChimpDetailItem: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
    /// Valeur technique (adresse) : Space Mono, et sélectionnable.
    var isMonospaced = false
}

/// Liste groupée de détails (C4 « ce qui sera signé ») : fond `chimpSurface`, contour 3, rayon 16,
/// lignes séparées par un trait `chimpSurfaceSecondary` de 2 pt (comme la liste groupée des réglages, I2).
/// Non dessinée dans la maquette.
struct ChimpDetailList: View {
    let items: [ChimpDetailItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.chimpSurfaceSecondary))
                        .frame(height: ChimpBorder.thin)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: item.value)
                        .chimpFont(item.isMonospaced ? .monoValue : .rowTitle)
                        .foregroundStyle(.chimpTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ChimpSpacing.sm)
                .padding(.horizontal, 13 + ChimpBorder.regular)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurface))
    }
}

private struct ChimpReviewViewsPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.l) {
                ChimpReviewSteps(steps: [
                    Text("25 USDC leaves Jungle's wallet"),
                    Text("Maya gets it in about 5 seconds"),
                    Text("Network fees paid by ChimpDAO"),
                ])
                ChimpDetailList(items: [
                    ChimpDetailItem(id: "to", label: "To", value: "GCQF 355R QFN7 7CHM 5DHE GK75 FWVF 26PU ES6J 6EMQ 4U7B AD3E 7ORD GXPO", isMonospaced: true),
                    ChimpDetailItem(id: "from", label: "From", value: "Jungle's wallet"),
                    ChimpDetailItem(id: "network", label: "Network", value: "Stellar Testnet"),
                ])
            }
            .padding(ChimpSpacing.screenMargin)
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpReviewViewsPreview()
}

#Preview("Dark") {
    ChimpReviewViewsPreview()
        .preferredColorScheme(.dark)
}
