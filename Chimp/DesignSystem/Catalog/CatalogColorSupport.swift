#if DESIGN_CATALOG
import SwiftUI
import UIKit

/// Un jeton de couleur tel qu'affiché dans le catalogue.
struct CatalogColorToken: Identifiable {
    let name: String
    let resource: ColorResource
    /// Fond sur lequel montrer une couleur semi-transparente.
    var backdrop: ColorResource?

    var id: String { name }
    var uiColor: UIColor { UIColor(resource: resource) }
}

enum CatalogColors {
    static let theme: [CatalogColorToken] = [
        .init(name: "chimpBackground", resource: .chimpBackground),
        .init(name: "chimpHeader", resource: .chimpHeader),
        .init(name: "chimpSurface", resource: .chimpSurface),
        .init(name: "chimpSurfaceSecondary", resource: .chimpSurfaceSecondary),
        .init(name: "chimpTextPrimary", resource: .chimpTextPrimary),
        .init(name: "chimpTextSecondary", resource: .chimpTextSecondary),
        .init(name: "chimpOutline", resource: .chimpOutline),
        .init(name: "chimpPositive", resource: .chimpPositive),
        .init(name: "chimpNegative", resource: .chimpNegative),
    ]

    static let fixed: [CatalogColorToken] = [
        .init(name: "chimpAccent", resource: .chimpAccent),
        .init(name: "chimpOnAccent", resource: .chimpOnAccent),
        .init(name: "chimpOnHeaderPrimary", resource: .chimpOnHeaderPrimary),
        .init(name: "chimpOnHeaderSecondary", resource: .chimpOnHeaderSecondary),
        .init(name: "chimpOnHeaderAccent", resource: .chimpOnHeaderAccent),
        .init(name: "chimpOutlineOnHeader", resource: .chimpOutlineOnHeader),
        .init(name: "chimpHeaderButtonFill", resource: .chimpHeaderButtonFill, backdrop: .chimpHeader),
        .init(name: "chimpStepSegmentInactive", resource: .chimpStepSegmentInactive, backdrop: .chimpHeader),
        .init(name: "chimpScrim", resource: .chimpScrim, backdrop: .chimpBackground),
        .init(name: "chimpHeaderShade", resource: .chimpHeaderShade, backdrop: .chimpHeader),
        .init(name: "chimpHeaderBannerBorder", resource: .chimpHeaderBannerBorder, backdrop: .chimpHeader),
        .init(name: "chimpIllustrationShadow", resource: .chimpIllustrationShadow, backdrop: .chimpHeader),
        .init(name: "chimpQRBackground", resource: .chimpQRBackground),
        .init(name: "chimpQRModule", resource: .chimpQRModule),
    ]

    static let cards: [CatalogColorToken] = [
        .init(name: "chimpCardJungle", resource: .chimpCardJungle),
        .init(name: "chimpCardBanana", resource: .chimpCardBanana),
        .init(name: "chimpCardLeaf", resource: .chimpCardLeaf),
        .init(name: "chimpCardPink", resource: .chimpCardPink),
        .init(name: "chimpOnCardJungle", resource: .chimpOnCardJungle),
        .init(name: "chimpOnCardBright", resource: .chimpOnCardBright),
    ]

    static let activity: [CatalogColorToken] = [
        .init(name: "chimpActivityPaid", resource: .chimpActivityPaid),
        .init(name: "chimpActivityMoved", resource: .chimpActivityMoved),
        .init(name: "chimpActivityReceived", resource: .chimpActivityReceived),
        .init(name: "chimpActivitySwap", resource: .chimpActivitySwap),
        .init(name: "chimpActivityCard", resource: .chimpActivityCard),
    ]

    static let risk: [CatalogColorToken] = [
        .init(name: "chimpRiskChill", resource: .chimpRiskChill),
        .init(name: "chimpRiskSpicy", resource: .chimpRiskSpicy),
        .init(name: "chimpRiskWild", resource: .chimpRiskWild),
    ]
}

extension UIColor {
    /// Couleur écrite en dur : réservée au catalogue, pour comparer avec les valeurs de la maquette.
    convenience init(catalogHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    /// « #F6EFE3 », suivi de l'opacité si la couleur est transparente.
    var hexDescription: String {
        let c = components
        let hex = String(
            format: "#%02X%02X%02X",
            Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded())
        )
        return c.alpha < 1 ? "\(hex) · \(Int((c.alpha * 100).rounded())) %" : hex
    }

    /// Luminance relative (WCAG 2).
    private var relativeLuminance: CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let c = components
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    /// Rapport de contraste WCAG avec une autre couleur opaque (1 à 21).
    func contrastRatio(with other: UIColor) -> CGFloat {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Rapport de contraste avec une icône « réussi » (≥ 4,5:1) ou « insuffisant ».
struct ContrastBadge: View {
    let ratio: CGFloat

    private var passes: Bool { ratio >= 4.5 }

    var body: some View {
        HStack(spacing: ChimpSpacing.xxs) {
            Image(systemName: passes ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .fontWeight(.heavy)
                .foregroundStyle(passes ? Color(.chimpPositive) : Color(.chimpNegative))
            Text(verbatim: String(format: "%.2f:1", ratio))
                .chimpFont(.monoValue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(passes ? Text("Contrast passes") : Text("Contrast below 4.5 to 1"))
        .accessibilityValue(Text(verbatim: String(format: "%.2f", ratio)))
    }
}
#endif
