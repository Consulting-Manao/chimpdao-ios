import SwiftUI

/// Textes partagés de F9, F10 et de la tuile CETES (B2/B3).
enum SavingsText {
    /// « 2 min ago », « just now », « 3 h ago » : l'âge du prix, toujours dit.
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return String(localized: "just now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(localized: "\(minutes) min ago") }
        return String(localized: "\(minutes / 60) h ago")
    }

    /// « +0.62% », « −1.10% ».
    static func change(_ fraction: Decimal, locale: Locale) -> String {
        let sign = fraction > 0 ? "+" : (fraction < 0 ? "\u{2212}" : "")
        return sign + abs(fraction).formatted(.percent.locale(locale).precision(.fractionLength(2)))
    }

    /// « ≈ 99.58 USDC » : la valeur indicative, au prix d'Etherfuse (USD, affiché en USDC comme la maquette).
    static func value(_ amount: Decimal, price: StablebondPrice, locale: Locale) -> String {
        "≈ " + SendAsset.usdc.displayedWithCode(price.value(of: amount), locale: locale)
    }

    /// « 1 CETES ≈ 0.0547 USDC ».
    static func unitPrice(_ price: StablebondPrice, code: String, locale: Locale) -> String {
        "1 \(code) ≈ " + price.usd.formatted(.number.locale(locale).precision(.significantDigits(1...3))) + " USDC"
    }
}

/// Builds de test seulement (Debug et Testing, testnet) : « Testnet: pool prices don't match real prices » (décision de
/// Barth du 2026-10-15), sur le swap et les écrans du CETES.
struct ChimpTestnetPriceNote: View {
    let network: StellarNetwork?

    var body: some View {
        #if DESIGN_CATALOG
        if network == .testnet {
            Label {
                Text("Testnet: pool prices don't match real prices")
            } icon: {
                Image(systemName: "flask.fill")
            }
            .chimpFont(.captionS)
            .fontWeight(.heavy)
            .foregroundStyle(.chimpTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }
}

/// Bandeau rouge d'un tiroir dont les CETES sont gelés (texte validé par Barth le 2026-10-15, F9 et F10).
struct SavingsFrozenBanner: View {
    let asset: SendAsset
    let drawerName: String

    var body: some View {
        let issuer = asset.issuerName ?? String(localized: "The issuer")
        VStack(alignment: .leading, spacing: 2) {
            Text("\(issuer) froze the \(asset.code) in \(drawerName)").chimpFont(.rowTitle)
            Text("They can't be swapped until \(issuer) unfreezes them. Nothing moved.").chimpFont(.caption)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .padding(.horizontal, 13)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpNegative))
        .accessibilityElement(children: .combine)
    }
}
