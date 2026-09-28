import Foundation

/// Montant tapé au pavé (C2), gardé comme les touches appuyées : des chiffres, et peut-être un séparateur.
///
/// **Indépendant de la langue du téléphone.** Le pavé annonce la touche « décimale » sans dire si c'est
/// « , » ou « . » ; ici, on ne stocke que des chiffres. La valeur (`value`) est lue avec une locale fixe
/// (`en_US_POSIX`), jamais avec celle du téléphone. Seul l'affichage (`displayText`) suit la langue.
/// Exemple : « 1,5 » tapé en français et « 1.5 » tapé en anglais donnent tous les deux `Decimal` 1.5.
///
/// Règles reprises du terminal (`lib/amount.ts`, `appendAmount`) : 12 chiffres au plus, décimales
/// limitées par l'actif, pas de zéro inutile en tête.
/// Tests unitaires : à écrire au jalon 5, avec la première cible de tests (ROADMAP, points ouverts).
struct AmountEntry: Equatable {
    /// Nombre maximal de chiffres (partie entière + décimales), comme `MAX_DIGITS` du terminal.
    static let maxDigits = 12

    /// Partie entière tapée (« » si rien n'est tapé, jamais de zéro en tête sauf « 0 »).
    private(set) var integerDigits = ""
    /// Décimales tapées ; `nil` tant que la touche décimale n'a pas été appuyée.
    private(set) var fractionDigits: String?

    private static let posix = Locale(identifier: "en_US_POSIX")

    init() {}

    /// Montant exact repris d'une valeur (pastille rapide, « Max »), tronqué à `maxFractionDigits`.
    /// `minFractionDigits` complète les décimales avec des zéros quand il y en a (« 62.5 » → « 62.50 » en USDC).
    init(_ value: Decimal, maxFractionDigits: Int, minFractionDigits: Int = 0) {
        let truncated = value.truncated(to: maxFractionDigits)
        // `description` d'un Decimal n'utilise jamais la langue du téléphone : toujours « 62.5 ».
        let parts = truncated.description.split(separator: ".", omittingEmptySubsequences: false)
        integerDigits = String(parts.first ?? "0")
        if parts.count > 1 {
            var fraction = String(parts[1])
            if fraction.count < minFractionDigits {
                fraction += String(repeating: "0", count: minFractionDigits - fraction.count)
            }
            fractionDigits = fraction
        }
    }

    /// Rien n'a été tapé.
    var isEmpty: Bool { integerDigits.isEmpty && fractionDigits == nil }

    /// Forme canonique, toujours avec un point : « 12.5 », « 0 ».
    var canonicalText: String {
        let integer = integerDigits.isEmpty ? "0" : integerDigits
        guard let fractionDigits, !fractionDigits.isEmpty else { return integer }
        return "\(integer).\(fractionDigits)"
    }

    /// Valeur exacte du montant, sans passer par un `Double`.
    var value: Decimal {
        Decimal(string: canonicalText, locale: Self.posix) ?? 0
    }

    private var digitCount: Int { integerDigits.count + (fractionDigits?.count ?? 0) }

    /// Applique une touche du pavé. Renvoie `false` si la touche est refusée (rien ne change).
    @discardableResult
    mutating func apply(_ key: ChimpKeypadKey, maxFractionDigits: Int) -> Bool {
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return false }
            if let fraction = fractionDigits {
                guard fraction.count < maxFractionDigits, digitCount < Self.maxDigits else { return false }
                fractionDigits = fraction + String(digit)
            } else if integerDigits == "0" {
                // « 0 » puis « 7 » donne « 7 », pas « 07 ».
                guard digit != 0 else { return false }
                integerDigits = String(digit)
            } else {
                guard digitCount < Self.maxDigits else { return false }
                integerDigits += String(digit)
            }
            return true
        case .decimal:
            guard maxFractionDigits > 0, fractionDigits == nil else { return false }
            if integerDigits.isEmpty { integerDigits = "0" }
            fractionDigits = ""
            return true
        case .delete:
            if let fraction = fractionDigits {
                fractionDigits = fraction.isEmpty ? nil : String(fraction.dropLast())
                return true
            }
            guard !integerDigits.isEmpty else { return false }
            integerDigits.removeLast()
            return true
        }
    }

    /// Même montant, décimales coupées à `maxFractionDigits` (changement d'actif, comme `clampAmount` du terminal).
    func clamped(toFractionDigits maxFractionDigits: Int) -> AmountEntry {
        guard let fraction = fractionDigits else { return self }
        var copy = self
        if maxFractionDigits == 0 {
            copy.fractionDigits = nil
        } else if fraction.count > maxFractionDigits {
            copy.fractionDigits = String(fraction.prefix(maxFractionDigits))
        }
        return copy
    }

    /// Texte affiché, selon la langue du téléphone : séparateurs de milliers et décimal de la région,
    /// décimales telles que tapées (« 1 250,50 » en français, « 1,250.50 » en anglais). « 0 » si rien n'est tapé.
    func displayText(locale: Locale) -> String {
        let integer = Decimal(string: integerDigits.isEmpty ? "0" : integerDigits, locale: Self.posix) ?? 0
        let integerText = integer.formatted(.number.locale(locale).precision(.fractionLength(0)))
        guard let fractionDigits else { return integerText }
        return integerText + (locale.decimalSeparator ?? ".") + fractionDigits
    }
}
