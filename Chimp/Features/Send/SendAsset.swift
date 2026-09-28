import Foundation

/// Actif qu'on peut envoyer. Au jalon 5, la liste viendra de `Config/` (SAC de chaque réseau).
///
/// Décimales saisissables au pavé reprises du terminal (`chain/assets.ts`) : USDC 2, XLM 7.
/// On-chain, les deux actifs ont 7 décimales (conversion en unités au jalon 5, avec tests).
enum SendAsset: String, CaseIterable, Identifiable, Hashable {
    case usdc
    case xlm

    var id: String { rawValue }

    /// Code affiché (« USDC »), identique dans toutes les langues.
    var code: String {
        switch self {
        case .usdc: "USDC"
        case .xlm: "XLM"
        }
    }

    var glyph: ChimpAssetGlyph {
        switch self {
        case .usdc: .usdc
        case .xlm: .xlm
        }
    }

    /// Nombre maximal de décimales qu'on peut taper.
    var maxFractionDigits: Int {
        switch self {
        case .usdc: 2
        case .xlm: 7
        }
    }

    /// Prix variable en dollars : on affiche alors l'équivalent « ≈ $ » (décision du 2026-09-28).
    /// L'USDC vaut un dollar : pas d'équivalent.
    var hasVariablePrice: Bool { self == .xlm }

    /// Pastilles de montant rapide (C2), dans l'unité de l'actif.
    var quickAmounts: [Decimal] {
        switch self {
        case .usdc: [10, 25, 50]
        case .xlm: [50, 100, 250]
        }
    }

    /// Montant sans le code, selon la région du téléphone : « 720 », « 62.50 » (USDC : 0 ou 2 décimales),
    /// « 1,250.5 » (XLM : décimales utiles seulement). Tronqué, jamais arrondi au-dessus.
    func formatted(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        let fractionLength: ClosedRange<Int>
        switch self {
        case .usdc:
            let cents = amount.truncated(to: 2)
            fractionLength = cents.isWhole ? 0...0 : 2...2
            return cents.formatted(.number.locale(locale).precision(.fractionLength(fractionLength)))
        case .xlm:
            fractionLength = 0...maxFractionDigits
            return amount.truncated(to: maxFractionDigits)
                .formatted(.number.locale(locale).precision(.fractionLength(fractionLength)))
        }
    }

    /// Montant avec le code : « 62.50 USDC ».
    func formattedWithCode(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        "\(formatted(amount, locale: locale)) \(code)"
    }
}

extension Decimal {
    /// Coupe les décimales au-delà de `digits`, vers zéro (jamais d'arrondi au-dessus : on ne propose
    /// jamais plus que ce qu'on a, comme `fromUnits` du terminal).
    func truncated(to digits: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, digits, self < 0 ? .up : .down)
        return result
    }

    /// Vrai si le nombre n'a pas de partie décimale.
    var isWhole: Bool { self == truncated(to: 0) }
}
