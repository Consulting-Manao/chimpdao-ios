import Foundation
import Testing
@testable import ChimpDAO

/// Grow, étape 3 : les textes de l'accueil G1 (montants des pots, pastilles de croissance, total en dollars).
struct GrowTextsTests {
    private let us = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr_FR")

    private func pot(_ mark: ChimpPotProtocol, value: String, putIn: Decimal? = nil, basis: Decimal? = nil, price: Decimal? = nil) -> GrowPot {
        GrowPot(
            mark: mark, drawerID: "main", drawerAddress: "C", asset: mark == .defindex ? .xlm : (mark == .xoxno ? .usdc : .cetes),
            state: .growing, value: Decimal(string: value), putIn: putIn, since: nil, basisPriceUSD: basis, priceUSD: price,
            withdrawableNow: nil
        )
    }

    @Test("Deux décimales tronquées (jamais arrondies vers le haut), séparateur de milliers, sans espace fine")
    func twoDecimals() {
        #expect(GrowView.twoDecimals(Decimal(string: "1820.409")!, locale: us) == "1,820.40")
        #expect(GrowView.twoDecimals(Decimal(string: "0.999")!, locale: us) == "0.99")
        let french = GrowView.twoDecimals(Decimal(string: "1820.4")!, locale: fr)
        #expect(french == "1 820,40")
        #expect(!french.contains("\u{202F}") && !french.contains("\u{00A0}"), "Luckiest Guy n'a pas l'espace fine")
    }

    @Test("Montant d'un pot : avec l'unité pour DeFindex, le nombre seul pour XOXNO et Etherfuse")
    func amount() {
        let defindex = pot(.defindex, value: "50.12")
        #expect(GrowView.amount(defindex.value!, pot: defindex, locale: us) == "50.12 XLM")
        let xoxno = pot(.xoxno, value: "500.84")
        #expect(GrowView.amount(xoxno.value!, pot: xoxno, locale: us) == "500.84")
    }

    @Test("Pot Solv : six décimales pour le bitcoin (0,00046 SolvBTC n'est plus « 0,00 »), tronquées")
    func bitcoinPot() {
        let solv = GrowPot(
            mark: .solv, drawerID: "main", drawerAddress: "C", asset: .solvbtc, state: .growing,
            value: Decimal(string: "0.000462379")!, putIn: nil, since: nil, basisPriceUSD: nil, priceUSD: nil, withdrawableNow: nil
        )
        #expect(GrowView.amount(solv.value!, pot: solv, locale: us) == "0.000462")
        #expect(GrowView.potNumber(Decimal(string: "0.000462")!, asset: .solvbtc, locale: fr) == "0,000462")
        #expect(GrowView.potNumber(Decimal(string: "500.849")!, asset: .usdc, locale: us) == "500.84", "Les autres pots gardent deux décimales")
    }

    @Test("Pastille : croissance réelle en quantité, évolution du prix pour les CETES, rouge si négative, rien sans base")
    func chip() {
        let up = pot(.defindex, value: "50.12", putIn: 50)
        #expect(GrowView.chip(up, locale: us) == "+0.12 XLM")
        #expect(!GrowView.isNegative(up))
        let down = pot(.xoxno, value: "19.97", putIn: 20)
        #expect(GrowView.chip(down, locale: us)?.hasPrefix("\u{2212}") == true)
        #expect(GrowView.isNegative(down))
        let cetes = pot(.etherfuse, value: "100", basis: 1, price: Decimal(string: "1.0063"))
        #expect(GrowView.chip(cetes, locale: us) == "Price +0.63%")
        #expect(GrowView.chip(pot(.defindex, value: "50"), locale: us) == nil)
    }

    @Test("Pourcentage et dollars : signe explicite (moins typographique), tronqué au centime")
    func signs() {
        #expect(GrowView.percent(Decimal(string: "-0.001")!, locale: us) == "\u{2212}0.10%")
        #expect(GrowView.percent(0, locale: us) == "0.00%")
        #expect(GrowView.dollars(Decimal(string: "5.689")!, locale: us) == "+$5.68")
        #expect(GrowView.dollars(Decimal(string: "-0.209")!, locale: us) == "\u{2212}$0.20")
        #expect(GrowView.dollars(0, locale: us) == "$0.00")
    }
}
