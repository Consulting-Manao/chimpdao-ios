#if DESIGN_CATALOG
import SwiftUI

struct CatalogColorsPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Colors", settings: settings) {
            group("Theme (light · dark)", tokens: CatalogColors.theme, themed: true)
            group("Fixed", tokens: CatalogColors.fixed, themed: false)
            group("Cards", tokens: CatalogColors.cards, themed: false)
            group("Activity", tokens: CatalogColors.activity, themed: false)
            group("Risk", tokens: CatalogColors.risk, themed: false)
        }
    }

    private func group(_ title: LocalizedStringKey, tokens: [CatalogColorToken], themed: Bool) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.listGap) {
            CatalogSectionTitle(title)
            ForEach(tokens) { token in
                CatalogColorRow(token: token, themed: themed)
            }
        }
    }
}

private struct CatalogColorRow: View {
    let token: CatalogColorToken
    let themed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text(verbatim: token.name).chimpFont(.rowTitle)
            HStack(spacing: ChimpSpacing.s) {
                if themed {
                    swatch(.light)
                    swatch(.dark)
                } else {
                    swatch(nil)
                }
            }
        }
        .padding(ChimpSpacing.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }

    /// Pastille de couleur, forcée en clair ou en sombre, avec sa valeur hexadécimale.
    private func swatch(_ scheme: ColorScheme?) -> some View {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        return VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            ZStack {
                if let backdrop = token.backdrop {
                    Color(backdrop)
                }
                Color(token.resource)
            }
            .frame(height: ChimpSize.minimumTouchTarget)
            .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.segment))
            .overlay {
                RoundedRectangle(cornerRadius: ChimpRadius.segment)
                    .strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin)
            }
            .environment(\.colorScheme, scheme ?? .light)
            .accessibilityHidden(true)

            HStack(spacing: ChimpSpacing.xxs) {
                if let scheme {
                    Text(scheme == .dark ? "Dark" : "Light").chimpFont(.captionS)
                }
                Text(verbatim: token.uiColor.resolved(style).hexDescription).chimpFont(.mono)
            }
            .foregroundStyle(.chimpTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        CatalogColorsPage(settings: CatalogSettings())
    }
}
#endif
