import Foundation

/// Devise d'affichage du Wallet et des pages de tiroir (I3 « Show amounts in »). **Ne change que l'affichage** : les
/// montants signés, envoyés et ceux de l'Activity restent ceux des actifs réellement bougés.
/// Liste de la maquette I3, **limitée aux devises cotées par Reflector** comme `listDenominations` du terminal : le franc
/// suisse de la maquette est retiré, le flux FX ne le cote pas (vérifié le 2026-09-30, DESIGN_NOTES §13).
enum DisplayCurrency: String, CaseIterable, Identifiable, Sendable, Codable {
    case usd, eur, gbp, jpy
    /// « Show everything in XLM ».
    case xlm

    var id: String { rawValue }

    /// Code demandé à l'oracle Reflector (flux FX pour les devises, CEX & DEX pour XLM) et code ISO 4217 des devises.
    var code: String { rawValue.uppercased() }

    var isFiat: Bool { self != .xlm }

    /// Valeur de la ligne « Currency » des réglages (maquette : « USD $ »).
    var settingsValue: String {
        switch self {
        case .usd: "USD $"
        case .eur: "EUR €"
        case .gbp: "GBP £"
        case .jpy: "JPY ¥"
        case .xlm: "XLM"
        }
    }

    /// Pastille de la feuille I3 (« $ », « € », « XLM »…).
    var badge: String {
        switch self {
        case .usd: "$"
        case .eur: "€"
        case .gbp: "£"
        case .jpy: "¥"
        case .xlm: "XLM"
        }
    }

    /// Nom affiché dans la feuille I3.
    var title: String {
        switch self {
        case .usd: String(localized: "US Dollar")
        case .eur: String(localized: "Euro")
        case .gbp: String(localized: "British Pound")
        case .jpy: String(localized: "Japanese Yen")
        case .xlm: String(localized: "Show everything in XLM")
        }
    }

    /// Décimales affichées, **toujours coupées, jamais arrondies** (comme `fromUnits` du terminal). Le terminal en montre
    /// 2 partout ; le yen n'en a pas (adaptation, DESIGN_NOTES §13).
    var fractionDigits: Int { self == .jpy ? 0 : 2 }
}

/// Montants convertis dans la devise d'affichage : portage de `netWorthIn` (`reference/terminal/src/chain/prices.ts`),
/// sans les dettes (l'app n'emprunte pas). Somme exacte des avoirs × prix en dollars, divisée par le prix en dollars de
/// la devise, coupée à 7 décimales (`in7`) puis aux décimales de la devise (`fromUnits(…, 2)`), vers zéro. Un avoir non
/// nul sans prix, ou une devise sans prix : **pas de montant** (« a total that quietly skips a holding is a lie ») ; l'écran affiche alors les montants par actif.
struct DisplayMoney: Equatable {
    let currency: DisplayCurrency
    /// Prix en dollars par code (USDC = 1), dont celui de la devise (`EUR`, `XLM`…) s'il a pu être lu.
    let usdPrices: [String: Decimal]
    /// Région des séparateurs (celle du téléphone ; fixée dans les tests).
    var locale: Locale = .autoupdatingCurrent

    /// Prix en dollars d'une unité de la devise (USD = 1). `nil` ou nul : la devise ne peut pas être affichée.
    var rate: Decimal? {
        if currency == .usd { return 1 }
        guard let rate = usdPrices[currency.code], rate > 0 else { return nil }
        return rate
    }

    /// Codes dont il faut le prix pour afficher ces actifs dans la devise (les actifs détenus, plus la devise).
    static func priceCodes(held: Set<String>, currency: DisplayCurrency) -> Set<String> {
        currency == .usd ? held : held.union([currency.code])
    }

    /// Valeur des avoirs dans la devise, coupée à ses décimales ; `nil` si un avoir non nul ou la devise n'a pas de prix.
    func value(_ holdings: [AssetAmount]) -> Decimal? {
        guard let rate else { return nil }
        var usd = Decimal(0)
        for holding in holdings where holding.amount != 0 {
            guard let price = usdPrices[holding.code.uppercased()] else { return nil }
            usd += holding.amount * price
        }
        return (usd / rate).truncated(to: 7).truncated(to: currency.fractionDigits)
    }

    /// Un montant déjà en dollars (épargne Grow, variation hebdomadaire des données factices) dans la devise.
    func value(usd amount: Decimal) -> Decimal? {
        guard let rate else { return nil }
        return (amount / rate).truncated(to: 7).truncated(to: currency.fractionDigits)
    }

    // MARK: Texte

    enum Style {
        /// « $1,554.45 », « ¥243,210 », « 6,758.92 XLM ».
        case standard
        /// Sans décimales quand le montant est rond (« $620 », tuiles des tiroirs).
        case wholeWhenRound
        /// Au plus les décimales utiles (« $1,200 », « $1,200.5 ») : parts « ready » et « growing » de Main.
        case upToDigits
        /// Signe toujours affiché (« +$6.20 »).
        case signed
    }

    /// Texte d'un montant déjà converti. Devises : symbole court (« $ » et non « US$ »), séparateurs de la région du
    /// téléphone. XLM : nombre suivi de « XLM », sans zéros inutiles, comme les montants par actif (`assetText`).
    func text(_ value: Decimal, style: Style = .standard) -> String {
        let digits = currency.fractionDigits
        let fraction: ClosedRange<Int> = switch style {
        case .standard, .signed: digits...digits
        case .wholeWhenRound: value.isWhole ? 0...0 : digits...digits
        case .upToDigits: 0...digits
        }
        if currency.isFiat {
            var format = Decimal.FormatStyle.Currency(code: currency.code, locale: locale).presentation(.narrow).precision(.fractionLength(fraction))
            if style == .signed { format = format.sign(strategy: .always()) }
            return value.formatted(format)
        }
        var format = Decimal.FormatStyle(locale: locale).precision(.fractionLength(0...digits))
        if style == .signed { format = format.sign(strategy: .always()) }
        return "\(value.formatted(format)) XLM"
    }
}
