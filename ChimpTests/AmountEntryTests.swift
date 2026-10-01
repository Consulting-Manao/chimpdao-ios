import Foundation
import Testing
@testable import ChimpDAO

/// Saisie d'un montant au pavé (C2) : la valeur envoyée ne dépend jamais de la langue du téléphone.
struct AmountEntryTests {
    private let french = Locale(identifier: "fr_FR")
    private let english = Locale(identifier: "en_US")

    /// Tape une suite de touches ; `"."` = touche décimale (« , » ou « . » selon la langue, peu importe ici).
    private func typed(_ keys: String, maxFractionDigits: Int = 7) -> AmountEntry {
        var entry = AmountEntry()
        for character in keys {
            if character == "." {
                entry.apply(.decimal, maxFractionDigits: maxFractionDigits)
            } else if let digit = character.wholeNumberValue {
                entry.apply(.digit(digit), maxFractionDigits: maxFractionDigits)
            }
        }
        return entry
    }

    // MARK: Indépendance vis-à-vis de la langue

    @Test("« 25,5 » tapé en français vaut 25.5")
    func frenchCommaIsDecimalSeparator() {
        let entry = typed("25.5")
        #expect(entry.displayText(locale: french) == "25,5")
        #expect(entry.value == Decimal(string: "25.5", locale: Locale(identifier: "en_US_POSIX")))
        #expect(entry.canonicalText == "25.5")
    }

    @Test("Les mêmes touches donnent la même valeur en anglais et en français")
    func sameValueInEveryLanguage() {
        let entry = typed("25.5")
        #expect(entry.displayText(locale: english) == "25.5")
        #expect(entry.displayText(locale: french) == "25,5")
        #expect(entry.value == Decimal(255) / 10)
    }

    @Test("Séparateur de milliers de la région à l'affichage, jamais dans la valeur")
    func groupingSeparatorOnlyInDisplay() {
        let entry = typed("4001")
        #expect(entry.displayText(locale: english) == "4,001")
        let frenchText = entry.displayText(locale: french)
        #expect(frenchText.filter(\.isNumber) == "4001")
        #expect(!frenchText.contains(","))
        #expect(entry.value == 4001)
        #expect(entry.canonicalText == "4001")
    }

    // MARK: Décimales maximales par actif

    @Test("USDC : 2 décimales au plus")
    func usdcAllowsTwoDecimals() {
        var entry = typed("1.23", maxFractionDigits: SendAsset.usdc.maxFractionDigits)
        #expect(entry.canonicalText == "1.23")
        #expect(entry.apply(.digit(4), maxFractionDigits: SendAsset.usdc.maxFractionDigits) == false)
        #expect(entry.canonicalText == "1.23")
    }

    @Test("XLM : 7 décimales au plus")
    func xlmAllowsSevenDecimals() {
        var entry = typed("1.1234567", maxFractionDigits: SendAsset.xlm.maxFractionDigits)
        #expect(entry.canonicalText == "1.1234567")
        #expect(entry.apply(.digit(8), maxFractionDigits: SendAsset.xlm.maxFractionDigits) == false)
        #expect(entry.value == Decimal(string: "1.1234567", locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test("Pas de touche décimale pour un actif sans décimales")
    func noDecimalWhenAssetHasNone() {
        var entry = typed("5", maxFractionDigits: 0)
        #expect(entry.apply(.decimal, maxFractionDigits: 0) == false)
        #expect(entry.canonicalText == "5")
    }

    @Test("Une seule touche décimale")
    func singleDecimalSeparator() {
        var entry = typed("1.5")
        #expect(entry.apply(.decimal, maxFractionDigits: 7) == false)
        #expect(entry.canonicalText == "1.5")
    }

    // MARK: 12 chiffres au plus

    @Test("12 chiffres acceptés, le 13ᵉ refusé")
    func twelveDigitsMaximum() {
        var entry = typed("123456789012")
        #expect(entry.canonicalText == "123456789012")
        #expect(entry.apply(.digit(3), maxFractionDigits: 7) == false)
        #expect(entry.canonicalText == "123456789012")
    }

    @Test("Les décimales comptent dans les 12 chiffres")
    func fractionDigitsCountTowardsMaximum() {
        var entry = typed("1234567890.12")
        #expect(entry.canonicalText == "1234567890.12")
        #expect(entry.apply(.digit(3), maxFractionDigits: 7) == false)
    }

    // MARK: Zéros, séparateur, effacement

    @Test("Pas de zéro inutile en tête")
    func noLeadingZero() {
        var entry = typed("0")
        #expect(entry.apply(.digit(0), maxFractionDigits: 7) == false)
        entry.apply(.digit(7), maxFractionDigits: 7)
        #expect(entry.canonicalText == "7")
    }

    @Test("Séparateur tapé en premier : « 0, »")
    func decimalFirstAddsZero() {
        let entry = typed(".")
        #expect(entry.displayText(locale: french) == "0,")
        #expect(entry.value == 0)
        #expect(!entry.isEmpty)
    }

    @Test("Effacer retire une décimale, puis le séparateur, puis la partie entière")
    func deleteOrder() {
        var entry = typed("12.3")
        entry.apply(.delete, maxFractionDigits: 7)
        #expect(entry.displayText(locale: english) == "12.")
        entry.apply(.delete, maxFractionDigits: 7)
        #expect(entry.displayText(locale: english) == "12")
        entry.apply(.delete, maxFractionDigits: 7)
        entry.apply(.delete, maxFractionDigits: 7)
        #expect(entry.isEmpty)
        #expect(entry.apply(.delete, maxFractionDigits: 7) == false)
        #expect(entry.displayText(locale: english) == "0")
    }

    // MARK: Changement d'actif et montant repris d'un solde

    @Test("Passer à un actif moins précis coupe les décimales en trop")
    func clampingToFewerDecimals() {
        let entry = typed("1.2345678")
        #expect(entry.clamped(toFractionDigits: 2).canonicalText == "1.23")
        #expect(entry.clamped(toFractionDigits: 0).canonicalText == "1")
        #expect(entry.clamped(toFractionDigits: 7).canonicalText == "1.2345678")
    }

    @Test("Montant repris d'un solde : tronqué, jamais arrondi au-dessus")
    func entryFromBalanceTruncates() {
        let balance = Decimal(string: "1.239", locale: Locale(identifier: "en_US_POSIX"))!
        let entry = AmountEntry(balance, maxFractionDigits: 2)
        #expect(entry.canonicalText == "1.23")
        #expect(entry.value <= balance)
    }

    @Test("« Max » en USDC : « 62,50 » affiché, 62.5 envoyé")
    func maxInUSDCKeepsCents() {
        let entry = AmountEntry(Decimal(string: "62.5", locale: Locale(identifier: "en_US_POSIX"))!, maxFractionDigits: 2, minFractionDigits: 2)
        #expect(entry.displayText(locale: french) == "62,50")
        #expect(entry.value == Decimal(625) / 10)
        #expect(AmountEntry(720, maxFractionDigits: 2, minFractionDigits: 2).canonicalText == "720")
    }

    // MARK: Formatage des soldes

    @Test("Troncature d'un Decimal")
    func decimalTruncation() {
        let value = Decimal(string: "6.375", locale: Locale(identifier: "en_US_POSIX"))!
        #expect(value.truncated(to: 2) == Decimal(637) / 100)
        #expect(Decimal(720).isWhole)
        #expect(!value.isWhole)
    }

    @Test("Soldes affichés : USDC en 0 ou 2 décimales, XLM avec les décimales utiles")
    func assetFormatting() {
        #expect(SendAsset.usdc.formatted(720, locale: english) == "720")
        #expect(SendAsset.usdc.formatted(Decimal(string: "62.5", locale: Locale(identifier: "en_US_POSIX"))!, locale: english) == "62.50")
        #expect(SendAsset.xlm.formatted(Decimal(string: "1250.5", locale: Locale(identifier: "en_US_POSIX"))!, locale: english) == "1,250.5")
        #expect(SendAsset.usdc.formattedWithCode(Decimal(string: "62.5", locale: Locale(identifier: "en_US_POSIX"))!, locale: french) == "62,50 USDC")
    }

    @Test("Soldes affichés : 2 décimales au plus, tronquées vers le bas, « < 0.01 » pour un solde minuscule")
    func displayedBalances() {
        let posix = Locale(identifier: "en_US_POSIX")
        let value = { (text: String) in Decimal(string: text, locale: posix)! }
        // Capture de Barth : « 999,6196784 » illisible.
        #expect(SendAsset.xlm.displayed(value("999.6196784"), locale: french) == "999,61")
        #expect(SendAsset.xlm.displayedWithCode(value("994.6196784"), locale: english) == "994.61 XLM")
        // Jamais arrondi au-dessus.
        #expect(SendAsset.xlm.displayed(value("0.0199999"), locale: english) == "0.01")
        #expect(SendAsset.xlm.displayed(value("1999.9999999"), locale: english) == "1,999.99")
        // Décimales utiles seulement pour XLM, 0 ou 2 pour USDC.
        #expect(SendAsset.xlm.displayed(value("1250.5"), locale: english) == "1,250.5")
        #expect(SendAsset.xlm.displayed(1000, locale: english) == "1,000")
        #expect(SendAsset.usdc.displayed(720, locale: english) == "720")
        #expect(SendAsset.usdc.displayed(value("62.5"), locale: english) == "62.50")
        #expect(SendAsset.usdc.displayed(value("62.509"), locale: english) == "62.50")
        // Non nul mais sous 0,01 : jamais « 0 ».
        #expect(SendAsset.xlm.displayedWithCode(value("0.0000001"), locale: french) == "< 0,01 XLM")
        #expect(SendAsset.usdc.displayed(value("0.009"), locale: english) == "< 0.01")
        #expect(SendAsset.xlm.displayed(0, locale: english) == "0")
        // Actif hors liste : même règle.
        #expect(SendAsset.displayed(value("3.14159"), code: "EURC", locale: english) == "3.14")
        // La valeur exacte reste disponible (Max, montant signé, reçus).
        #expect(SendAsset.xlm.formatted(value("999.6196784"), locale: english) == "999.6196784")
    }
}
