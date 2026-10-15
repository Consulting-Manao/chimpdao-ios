import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 6 : textes de F9, F10 et de la tuile CETES (maquettes du 2026-10-15).
struct SavingsTextTests {
    private let locale = Locale(identifier: "en_US")
    private let price = StablebondPrice(code: "CETES", usd: Decimal(string: "0.0547")!, currency: "MXN", fiat: 1, asOf: .now)

    @Test("Âge du prix : « just now », « 2 min ago », « 3 h ago » ; toujours dit")
    func age() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SavingsText.age(of: now.addingTimeInterval(-30), now: now) == "just now")
        #expect(SavingsText.age(of: now.addingTimeInterval(-150), now: now) == "2 min ago")
        #expect(SavingsText.age(of: now.addingTimeInterval(-3 * 3600 - 10), now: now) == "3 h ago")
    }

    @Test("« Price +0.62% », « −1.10% » ; « ≈ 99.58 USDC » au prix d'Etherfuse ; « 1 CETES ≈ 0.0547 USDC »")
    func values() {
        #expect(SavingsText.change(Decimal(string: "0.0062")!, locale: locale) == "+0.62%")
        #expect(SavingsText.change(Decimal(string: "-0.011")!, locale: locale) == "\u{2212}1.10%")
        #expect(SavingsText.value(Decimal(string: "1820.4")!, price: price, locale: locale) == "≈ 99.57 USDC")
        #expect(SavingsText.unitPrice(price, code: "CETES", locale: locale) == "1 CETES ≈ 0.0547 USDC")
    }

    @Test("Feuille des actifs (E3p) : la description sous CETES seulement")
    func description() {
        #expect(SendAsset.cetes.descriptionLine == "Mexican government bonds, by Etherfuse")
        #expect(SendAsset.xlm.descriptionLine == nil)
        #expect(SendAsset.usdc.descriptionLine == nil)
    }
}
