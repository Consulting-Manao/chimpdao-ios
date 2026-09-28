#if DESIGN_CATALOG
import SwiftUI

/// Espacements, rayons, contours, ombres, tailles et opacités.
struct CatalogLayoutPage: View {
    let settings: CatalogSettings

    private static let spacings: [(String, CGFloat)] = [
        ("xxs", ChimpSpacing.xxs), ("xs", ChimpSpacing.xs), ("s", ChimpSpacing.s), ("sm", ChimpSpacing.sm),
        ("m", ChimpSpacing.m), ("ml", ChimpSpacing.ml), ("l", ChimpSpacing.l), ("lg", ChimpSpacing.lg),
        ("xl", ChimpSpacing.xl), ("xxl", ChimpSpacing.xxl), ("xxxl", ChimpSpacing.xxxl),
        ("screenMargin", ChimpSpacing.screenMargin), ("fullScreenMargin", ChimpSpacing.fullScreenMargin),
        ("listGap", ChimpSpacing.listGap), ("blockGap", ChimpSpacing.blockGap), ("sectionGap", ChimpSpacing.sectionGap),
    ]

    private static let radii: [(String, CGFloat)] = [
        ("segment", ChimpRadius.segment), ("icon", ChimpRadius.icon), ("tab", ChimpRadius.tab),
        ("key", ChimpRadius.key), ("control", ChimpRadius.control), ("chimpCard", ChimpRadius.chimpCard),
        ("panel", ChimpRadius.panel), ("sheet", ChimpRadius.sheet),
    ]

    private static let borders: [(String, CGFloat)] = [
        ("thin", ChimpBorder.thin), ("regular", ChimpBorder.regular), ("thick", ChimpBorder.thick),
    ]

    private static let shadows: [(String, ChimpShadow)] = [
        ("button", .button), ("raised", .raised), ("tile", .tile), ("card", .card),
    ]

    private static let sizes: [(String, String)] = [
        ("minimumTouchTarget", "\(ChimpSize.minimumTouchTarget)"),
        ("headerButton", "\(ChimpSize.headerButton)"),
        ("headerGearButton", "\(ChimpSize.headerGearButton)"),
        ("stepSegmentHeight", "\(ChimpSize.stepSegmentHeight)"),
        ("chimpyThumbnail", "\(ChimpSize.chimpyThumbnail)"),
        ("pinDot", "\(ChimpSize.pinDot)"),
        ("pinDotSpacing", "\(ChimpSize.pinDotSpacing)"),
        ("keypadSpacing", "\(ChimpSize.keypadSpacing)"),
        ("keyVerticalPadding", "\(ChimpSize.keyVerticalPadding)"),
        ("colorSwatch", "\(ChimpSize.colorSwatch)"),
        ("sheetHeight", "\(ChimpSize.sheetHeight)"),
        ("cardTapSheetHeight", "\(ChimpSize.cardTapSheetHeight)"),
        ("nfcRingArea", "\(ChimpSize.nfcRingArea)"),
        ("cardThumbnail", "\(ChimpSize.cardThumbnail.width) × \(ChimpSize.cardThumbnail.height)"),
        ("cardThumbnailLogo", "\(ChimpSize.cardThumbnailLogo)"),
        ("signerSwatch", "\(ChimpSize.signerSwatch)"),
        ("chimpyThumbnailMaxHeight", "\(ChimpSize.chimpyThumbnailMaxHeight)"),
        ("sheetHandle", "\(ChimpSize.sheetHandle.width) × \(ChimpSize.sheetHandle.height)"),
        ("patternTile", "\(ChimpSize.patternTile)"),
        ("patternTileOnCard", "\(ChimpSize.patternTileOnCard)"),
        ("cardAspectRatio", "\(ChimpSize.cardAspectRatio)"),
        ("ChimpOpacity.pattern", "\(ChimpOpacity.pattern)"),
        ("ChimpOpacity.patternOnCard", "\(ChimpOpacity.patternOnCard)"),
        ("ChimpOpacity.disabled", "\(ChimpOpacity.disabled)"),
    ]

    var body: some View {
        CatalogPage("Spacing, radii, borders, shadows", settings: settings) {
            section("Spacing") {
                ForEach(Self.spacings, id: \.0) { name, value in
                    HStack(spacing: ChimpSpacing.m) {
                        Text(verbatim: name).chimpFont(.captionS).frame(width: 120, alignment: .leading)
                        Rectangle().fill(Color(.chimpAccent)).frame(width: value, height: ChimpSpacing.m)
                            .overlay { Rectangle().strokeBorder(Color(.chimpOutline), lineWidth: 1) }
                        Text(verbatim: "\(Int(value))").chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            section("Radii") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: ChimpSpacing.m)], spacing: ChimpSpacing.m) {
                    ForEach(Self.radii, id: \.0) { name, value in
                        VStack(spacing: ChimpSpacing.xxs) {
                            Color.clear
                                .frame(height: 72)
                                .cartoonSurface(RoundedRectangle(cornerRadius: value), fill: Color(.chimpSurface))
                            Text(verbatim: name).chimpFont(.captionS)
                            Text(verbatim: "\(Int(value))").chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    VStack(spacing: ChimpSpacing.xxs) {
                        Color.clear
                            .frame(height: 72)
                            .cartoonSurface(Capsule(), fill: Color(.chimpSurface))
                        Text(verbatim: "Capsule()").chimpFont(.captionS)
                        Text(verbatim: "pill").chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            section("Borders") {
                ForEach(Self.borders, id: \.0) { name, value in
                    HStack(spacing: ChimpSpacing.m) {
                        Text(verbatim: name).chimpFont(.captionS).frame(width: 120, alignment: .leading)
                        Color.clear
                            .frame(height: 36)
                            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.segment), fill: Color(.chimpSurface), border: value)
                        Text(verbatim: "\(Int(value))").chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            section("Shadows") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: ChimpSpacing.l)], spacing: ChimpSpacing.l) {
                    ForEach(Self.shadows, id: \.0) { name, shadow in
                        VStack(spacing: ChimpSpacing.xxs) {
                            Text(verbatim: name).chimpFont(.buttonSmall)
                            Text(verbatim: "x \(Int(shadow.x)) · y \(Int(shadow.y))").chimpFont(.mono)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpAccent), shadow: shadow)
                        .foregroundStyle(.chimpOnAccent)
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(spacing: ChimpSpacing.l) {
                    RoundedRectangle(cornerRadius: ChimpRadius.key)
                        .fill(Color(.chimpCardJungle))
                        .frame(width: ChimpSize.colorSwatch, height: ChimpSize.colorSwatch)
                        .overlay {
                            RoundedRectangle(cornerRadius: ChimpRadius.key)
                                .strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular)
                        }
                        .padding(ChimpBorder.thick)
                        .overlay {
                            RoundedRectangle(cornerRadius: ChimpRadius.key + ChimpBorder.thick)
                                .strokeBorder(Color(.chimpAccent), lineWidth: ChimpBorder.thick)
                        }
                    Text("Selection ring: 4 pt, chimpAccent").chimpFont(.caption)
                }
                .accessibilityElement(children: .combine)
            }

            section("Sizes and opacities") {
                ForEach(Self.sizes, id: \.0) { name, value in
                    HStack {
                        Text(verbatim: name).chimpFont(.captionS)
                        Spacer()
                        Text(verbatim: value).chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
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
        CatalogLayoutPage(settings: CatalogSettings())
    }
}
#endif
