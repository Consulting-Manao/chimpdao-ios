import Foundation
import SwiftUI

/// Actif de l'app. Leurs contrats (SAC) viennent de `Config/` (`SACClient.stellarAssets`), **par adresse exacte** :
/// un code n'identifie jamais un actif (il existe d'autres « CETES » sur testnet).
///
/// Décimales saisissables au pavé reprises du terminal (`chain/assets.ts`) : USDC 2, XLM 7. CETES : 7, pour que « Max »
/// rende tout le solde (aucune poussière laissée au retour d'un swap). On-chain, tous ont 7 décimales.
///
/// CETES (Etherfuse, tranche 2, D3) ne s'obtient et ne se rend que par un swap : ni Envoyer, ni Move, ni Recevoir
/// (`sendable`).
enum SendAsset: String, CaseIterable, Identifiable, Hashable {
    case usdc
    case xlm
    case cetes
    /// USDY d'Ondo (bons du Trésor américain), décision de Barth du 2026-11-05.
    case usdy
    /// SolvBTC (du bitcoin sur Stellar, adossé 1:1) et xSolvBTC (SolvBTC qui rapporte), de Solv, 2026-11-05. Jetons SEP-41
    /// à **8 décimales** (pas des SAC).
    case solvbtc
    case xsolvbtc

    /// Ce qu'Envoyer, Move et les préremplissages d'un envoi proposent.
    static let sendable: [SendAsset] = [.usdc, .xlm]

    var isSendable: Bool { Self.sendable.contains(self) }

    /// Ce que propose le swap (maquette E3p), dans cet ordre.
    static let swappable: [SendAsset] = [.xlm, .usdc, .cetes, .usdy, .solvbtc, .xsolvbtc]

    var id: String { rawValue }

    /// Code affiché (« USDC »), identique dans toutes les langues.
    var code: String {
        switch self {
        case .usdc: "USDC"
        case .xlm: "XLM"
        case .cetes: "CETES"
        case .usdy: "USDY"
        case .solvbtc: "SolvBTC"
        case .xsolvbtc: "xSolvBTC"
        }
    }

    /// Ce que c'est, en une ligne (feuille des actifs du swap, maquette E3p).
    var summary: LocalizedStringKey {
        switch self {
        case .usdc: "Digital dollar, by Circle"
        case .xlm: "Stellar Lumens"
        case .cetes: "Mexican government bonds, by Etherfuse"
        case .usdy: "US Treasuries, by Ondo"
        case .solvbtc: "Bitcoin on Stellar, by Solv"
        case .xsolvbtc: "SolvBTC that earns, by Solv"
        }
    }

    /// La ligne de description sous l'actif, seulement quand elle aide (maquette E3p, décision de Barth du 2026-10-15).
    var descriptionLine: String? {
        switch self {
        case .cetes: String(localized: "Mexican government bonds, by Etherfuse")
        case .usdy: String(localized: "US Treasuries, by Ondo")
        case .solvbtc: String(localized: "Bitcoin on Stellar, by Solv")
        case .xsolvbtc: String(localized: "SolvBTC that earns, by Solv")
        case .usdc, .xlm: nil
        }
    }

    /// Qui émet l'actif et peut le geler, quand ce n'est pas un actif « de base » (XLM, USDC de Circle).
    var issuerName: String? {
        switch self {
        case .cetes: "Etherfuse"
        case .usdy: "Ondo"
        case .solvbtc, .xsolvbtc: "Solv"
        case .usdc, .xlm: nil
        }
    }

    var glyph: ChimpAssetGlyph {
        switch self {
        case .usdc: .usdc
        case .xlm: .xlm
        case .cetes: .cetes
        case .usdy: .usdy
        case .solvbtc: .solvbtc
        case .xsolvbtc: .xsolvbtc
        }
    }

    /// Nombre maximal de décimales qu'on peut taper.
    var maxFractionDigits: Int {
        switch self {
        case .usdc: 2
        case .xlm, .cetes, .usdy: 7
        case .solvbtc, .xsolvbtc: 8
        }
    }

    /// Décimales on-chain : 7 pour un SAC (XLM, USDC, CETES, USDY), 8 pour les jetons de Solv.
    var decimals: Int {
        switch self {
        case .solvbtc, .xsolvbtc: 8
        case .usdc, .xlm, .cetes, .usdy: SACClient.decimals
        }
    }

    /// Les décimales on-chain d'un actif de l'app désigné par son code (7 si l'app ne le connaît pas).
    static func decimals(code: String) -> Int {
        SendAsset(code: code)?.decimals ?? SACClient.decimals
    }

    /// Prix variable en dollars : on affiche alors l'équivalent « ≈ $ » (décision du 2026-09-28).
    /// L'USDC vaut un dollar : pas d'équivalent.
    var hasVariablePrice: Bool { self == .xlm }

    /// Pastilles de montant rapide (C2), dans l'unité de l'actif.
    var quickAmounts: [Decimal] {
        switch self {
        case .usdc: [10, 25, 50]
        case .xlm: [50, 100, 250]
        case .cetes: [100, 500, 1000]
        case .usdy: [10, 25, 50]
        case .solvbtc, .xsolvbtc: [Decimal(string: "0.0001")!, Decimal(string: "0.0005")!, Decimal(string: "0.001")!]
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
        case .xlm, .cetes, .usdy, .solvbtc, .xsolvbtc:
            fractionLength = 0...maxFractionDigits
            return amount.truncated(to: maxFractionDigits)
                .formatted(.number.locale(locale).precision(.fractionLength(fractionLength)))
        }
    }

    /// Montant avec le code : « 62.50 USDC ».
    func formattedWithCode(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        "\(formatted(amount, locale: locale)) \(code)"
    }

    // MARK: Soldes affichés

    /// Solde **affiché** (décision de Barth du 2026-10-01) : 2 décimales au plus, toujours tronquées vers zéro, jamais
    /// arrondies au-dessus (« 999.6196784 » → « 999.61 ») ; « < 0.01 » pour un montant non nul plus petit, pour ne jamais
    /// faire croire à un solde vide. USDC : 0 ou 2 décimales (« 720 », « 62.50 »).
    /// Affichage seulement : Max, montant saisi, montant signé et reçus gardent la valeur exacte (`formatted`).
    func displayed(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        Self.displayed(amount, code: code, locale: locale)
    }

    /// Solde affiché avec le code : « 994.61 XLM ».
    func displayedWithCode(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        "\(displayed(amount, locale: locale)) \(code)"
    }

    /// Plus petit montant affiché : 0.01.
    static let smallestDisplayed = Decimal(sign: .plus, exponent: -2, significand: 1)

    /// Décimales affichées d'un solde : 2, sauf les jetons de bitcoin (6 : un centième de bitcoin vaut des centaines de
    /// dollars, 2026-11-05).
    static func displayedDigits(code: String) -> Int {
        code == SendAsset.solvbtc.code || code == SendAsset.xsolvbtc.code ? 6 : 2
    }

    /// Même règle pour un actif désigné par son code (actifs hors `SendAsset` : 0 à 2 décimales).
    static func displayed(_ amount: Decimal, code: String, locale: Locale = .autoupdatingCurrent) -> String {
        let digits = displayedDigits(code: code)
        let smallest = Decimal(sign: .plus, exponent: -digits, significand: 1)
        let magnitude = abs(amount)
        if magnitude > 0, magnitude < smallest {
            let floor = smallest.formatted(.number.locale(locale).precision(.fractionLength(digits)))
            return "< \(floor)"
        }
        let cents = amount.truncated(to: digits)
        let fraction: ClosedRange<Int> = code == SendAsset.usdc.code ? (cents.isWhole ? 0...0 : 2...2) : 0...digits
        return cents.formatted(.number.locale(locale).precision(.fractionLength(fraction)))
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
