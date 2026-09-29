#if DESIGN_CATALOG
import SwiftUI
import UIKit

/// Contrastes : les deux corrections proposées (maquette ↔ proposition) et le tableau de tous les couples texte / fond.
struct CatalogContrastPage: View {
    let settings: CatalogSettings

    // Valeurs de la maquette, gardées ici uniquement pour la comparaison.
    private static let mockupPositive = UIColor(catalogHex: 0x2F7F27)
    private static let mockupStepLabel = UIColor(catalogHex: 0xFFD11E)

    var body: some View {
        CatalogPage("Contrast", settings: settings) {
            Text("Minimum for text: 4.5:1 (WCAG AA). Left: mockup. Right: proposed value, now used by the token.")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextSecondary)

            VStack(alignment: .leading, spacing: ChimpSpacing.listGap) {
                CatalogSectionTitle("Positive text · light theme")
                ForEach(Self.positiveBackdrops, id: \.name) { backdrop in
                    comparison(
                        backdropName: backdrop.name,
                        backdrop: UIColor(resource: backdrop.resource).resolved(.light),
                        before: Self.mockupPositive,
                        after: UIColor(resource: .chimpPositive).resolved(.light),
                        sample: Text(verbatim: "+$6.20").chimpFont(.monoValue),
                        caption: "this week"
                    )
                }
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.listGap) {
                CatalogSectionTitle("Step label on header · light theme")
                comparison(
                    backdropName: "chimpHeader",
                    backdrop: UIColor(resource: .chimpHeader).resolved(.light),
                    before: Self.mockupStepLabel,
                    after: UIColor(resource: .chimpOnHeaderAccent),
                    sample: Text("Step 2 of 3").chimpFont(.labelWide).textCase(.uppercase),
                    caption: nil
                )
            }

            ContrastMatrix(style: .light, title: "All text pairs · light")
            ContrastMatrix(style: .dark, title: "All text pairs · dark")
        }
    }

    private static let positiveBackdrops: [(name: String, resource: ColorResource)] = [
        ("chimpBackground", .chimpBackground),
        ("chimpSurface", .chimpSurface),
        ("chimpSurfaceSecondary", .chimpSurfaceSecondary),
    ]

    private func comparison(
        backdropName: String,
        backdrop: UIColor,
        before: UIColor,
        after: UIColor,
        sample: some View,
        caption: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text(verbatim: backdropName).chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
            HStack(spacing: ChimpSpacing.s) {
                swatch(title: "Mockup", color: before, backdrop: backdrop, sample: sample, caption: caption)
                swatch(title: "Proposed", color: after, backdrop: backdrop, sample: sample, caption: caption)
            }
        }
    }

    private func swatch(
        title: LocalizedStringKey,
        color: UIColor,
        backdrop: UIColor,
        sample: some View,
        caption: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.xs) {
                sample
                if let caption { Text(caption).chimpFont(.caption) }
            }
            .foregroundStyle(Color(uiColor: color))
            .padding(ChimpSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color(uiColor: backdrop), in: RoundedRectangle(cornerRadius: ChimpRadius.key))
            .overlay {
                RoundedRectangle(cornerRadius: ChimpRadius.key)
                    .strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular)
            }
            Text(title).chimpFont(.rowTitle)
            Text(verbatim: color.hexDescription).chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
            ContrastBadge(ratio: color.contrastRatio(with: backdrop))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Tableau des rapports de contraste de tous les couples texte / fond d'un thème.
private struct ContrastMatrix: View {
    let style: UIUserInterfaceStyle
    let title: LocalizedStringKey

    private typealias Pair = (text: String, textColor: ColorResource, background: String, backgroundColor: ColorResource)

    private static let pairs: [Pair] = {
        let texts: [(String, ColorResource)] = [
            ("chimpTextPrimary", .chimpTextPrimary),
            ("chimpTextSecondary", .chimpTextSecondary),
            ("chimpPositive", .chimpPositive),
            ("chimpNegative", .chimpNegative),
        ]
        let backgrounds: [(String, ColorResource)] = [
            ("chimpBackground", .chimpBackground),
            ("chimpSurface", .chimpSurface),
            ("chimpSurfaceSecondary", .chimpSurfaceSecondary),
        ]
        var pairs: [Pair] = []
        for text in texts {
            for background in backgrounds {
                pairs.append((text.0, text.1, background.0, background.1))
            }
        }
        return pairs + [
            ("chimpOnHeaderPrimary", .chimpOnHeaderPrimary, "chimpHeader", .chimpHeader),
            ("chimpOnHeaderSecondary", .chimpOnHeaderSecondary, "chimpHeader", .chimpHeader),
            ("chimpOnHeaderAccent", .chimpOnHeaderAccent, "chimpHeader", .chimpHeader),
            ("chimpOnAccent", .chimpOnAccent, "chimpAccent", .chimpAccent),
            ("chimpOnCardJungle", .chimpOnCardJungle, "chimpCardJungle", .chimpCardJungle),
            ("chimpOnCardBright", .chimpOnCardBright, "chimpCardBanana", .chimpCardBanana),
            ("chimpOnCardBright", .chimpOnCardBright, "chimpCardLeaf", .chimpCardLeaf),
            ("chimpOnCardBright", .chimpOnCardBright, "chimpCardPink", .chimpCardPink),
        ]
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            CatalogSectionTitle(title)
            VStack(spacing: 0) {
                ForEach(Array(Self.pairs.enumerated()), id: \.offset) { index, pair in
                    let text = UIColor(resource: pair.textColor).resolved(style)
                    let background = UIColor(resource: pair.backgroundColor).resolved(style)
                    HStack(spacing: ChimpSpacing.m) {
                        Text(verbatim: "Aa")
                            .chimpFont(.rowTitle)
                            .foregroundStyle(Color(uiColor: text))
                            .frame(width: ChimpSize.minimumTouchTarget, height: ChimpSize.minimumTouchTarget)
                            .background(Color(uiColor: background), in: RoundedRectangle(cornerRadius: ChimpRadius.segment))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: pair.text).chimpFont(.captionS)
                            Text("on \(pair.background)").chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                        }
                        Spacer(minLength: ChimpSpacing.s)
                        ContrastBadge(ratio: text.contrastRatio(with: background))
                    }
                    .padding(.vertical, ChimpSpacing.xs)
                    .padding(.horizontal, ChimpSpacing.m)
                    .accessibilityElement(children: .combine)
                    if index < Self.pairs.count - 1 {
                        Rectangle().fill(Color(.chimpSurfaceSecondary)).frame(height: ChimpBorder.thin)
                    }
                }
            }
            // Les traits s'arrêtent à l'intérieur du contour.
            .padding(ChimpBorder.regular)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurface))
        }
    }
}

#Preview {
    NavigationStack {
        CatalogContrastPage(settings: CatalogSettings())
    }
}
#endif
