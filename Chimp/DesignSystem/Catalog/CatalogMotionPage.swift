#if DESIGN_CATALOG
import SwiftUI

/// Valeurs des animations. Les démonstrations animées arrivent avec les composants qui les utilisent.
struct CatalogMotionPage: View {
    let settings: CatalogSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rows: [(String, [(String, String)])] = [
        ("ChimpMotion.Ring", [
            ("scale", "\(ChimpMotion.Ring.startScale) → \(ChimpMotion.Ring.endScale)"),
            ("opacity", "\(ChimpMotion.Ring.startOpacity) → \(ChimpMotion.Ring.endOpacity)"),
            ("lineWidth", "\(ChimpMotion.Ring.lineWidth)"),
            ("fullScreen", ring(ChimpMotion.Ring.fullScreen)),
            ("sheet", ring(ChimpMotion.Ring.sheet)),
        ]),
        ("ChimpMotion.Bob", [
            ("amplitude", "\(ChimpMotion.Bob.amplitude) pt"),
            ("calm", "\(ChimpMotion.Bob.calm.lowerBound)–\(ChimpMotion.Bob.calm.upperBound) s"),
            ("nervous", "\(ChimpMotion.Bob.nervous.lowerBound)–\(ChimpMotion.Bob.nervous.upperBound) s"),
            ("tiltedCardAngle", "\(ChimpMotion.Bob.tiltedCardAngle.degrees)°"),
        ]),
        ("ChimpMotion.Ripen", [
            ("duration", "\(ChimpMotion.Ripen.duration) s"),
            ("unripeHueRotation", "\(ChimpMotion.Ripen.unripeHueRotation.degrees)°"),
            ("unripeSaturation", "\(ChimpMotion.Ripen.unripeSaturation)"),
        ]),
        ("ChimpMotion.Press", [
            ("duration", "\(ChimpMotion.Press.duration) s"),
        ]),
    ]

    private static func ring(_ config: ChimpMotion.Ring.Config) -> String {
        "\(config.count) × \(config.duration) s, stagger \(config.stagger) s"
    }

    var body: some View {
        CatalogPage("Motion", settings: settings) {
            HStack {
                Text("Reduce Motion").chimpFont(.rowTitle)
                Spacer()
                Text(reduceMotion ? "On" : "Off").chimpFont(.monoValue).foregroundStyle(.chimpTextSecondary)
            }
            .accessibilityElement(children: .combine)

            ForEach(Self.rows, id: \.0) { group, values in
                VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                    Text(verbatim: group).chimpFont(.label).foregroundStyle(.chimpTextSecondary)
                    ForEach(values, id: \.0) { name, value in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: name).chimpFont(.captionS)
                            Spacer()
                            Text(verbatim: value).chimpFont(.mono).multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(ChimpSpacing.ml)
                .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
            }
        }
    }
}

#Preview {
    NavigationStack {
        CatalogMotionPage(settings: CatalogSettings())
    }
}
#endif
