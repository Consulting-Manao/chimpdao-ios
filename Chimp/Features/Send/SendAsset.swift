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

    /// Ce qu'Envoyer, Move et les préremplissages d'un envoi proposent.
    static let sendable: [SendAsset] = [.usdc, .xlm]

    var isSendable: Bool { Self.sendable.contains(self) }

    /// Ce que propose le swap (maquette E3p), dans cet ordre.
    static let swappable: [SendAsset] = [.xlm, .usdc, .cetes]

    var id: String { rawValue }

    /// Code affiché (« USDC »), identique dans toutes les langues.
    var code: String {
        switch self {
        case .usdc: "USDC"
        case .xlm: "XLM"
        case .cetes: "CETES"
        }
    }

    /// Ce que c'est, en une ligne (feuille des actifs du swap, maquette E3p).
    var summary: LocalizedStringKey {
        switch self {
        case .usdc: "Digital dollar, by Circle"
        case .xlm: "Stellar Lumens"
        case .cetes: "Mexican government bonds, by Etherfuse"
        }
    }

    /// Qui émet l'actif et peut le geler, quand ce n'est pas un actif « de base » (XLM, USDC de Circle).
    var issuerName: String? { self == .cetes ? "Etherfuse" : nil }

    var glyph: ChimpAssetGlyph {
        switch self {
        case .usdc: .usdc
        case .xlm: .xlm
        case .cetes: .cetes
        }
    }

    /// Nombre maximal de décimales qu'on peut taper.
    var maxFractionDigits: Int {
        switch self {
        case .usdc: 2
        case .xlm, .cetes: 7
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
        case .cetes: [100, 500, 1000]
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
        case .xlm, .cetes:
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

    /// Même règle pour un actif désigné par son code (actifs hors `SendAsset` : 0 à 2 décimales).
    static func displayed(_ amount: Decimal, code: String, locale: Locale = .autoupdatingCurrent) -> String {
        let magnitude = abs(amount)
        if magnitude > 0, magnitude < smallestDisplayed {
            let floor = smallestDisplayed.formatted(.number.locale(locale).precision(.fractionLength(2)))
            return "< \(floor)"
        }
        let cents = amount.truncated(to: 2)
        let fraction: ClosedRange<Int> = code == SendAsset.usdc.code ? (cents.isWhole ? 0...0 : 2...2) : 0...2
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
