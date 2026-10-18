import Foundation
import Testing
@testable import ChimpDAO

/// Grow, étape 4 : les textes de la page d'un pot (G2).
struct PotTextTests {
    private let us = Locale(identifier: "en_US")

    private func pot(
        _ mark: ChimpPotProtocol, value: String?, putIn: Decimal? = nil, state: GrowPot.State = .growing,
        basis: Decimal? = nil, price: Decimal? = nil
    ) -> GrowPot {
        GrowPot(
            mark: mark, drawerID: "main", drawerAddress: "C", asset: mark == .defindex ? .xlm : (mark == .xoxno ? .usdc : .cetes),
            state: state, value: value.flatMap { Decimal(string: $0) }, putIn: putIn, since: nil, basisPriceUSD: basis,
            priceUSD: price, withdrawableNow: nil
        )
    }

    @Test("En-tête et pied du ticket : « XLM · in Main », « DEFINDEX · IN MAIN »")
    func labels() {
        #expect(PotText.subtitle("XLM", drawerName: "Main") == "XLM · in Main")
        #expect(PotText.footer(.defindex, drawerName: "Main") == "DEFINDEX · IN MAIN")
        #expect(PotText.days(26) == "26 DAYS")
        #expect(PotText.days(1) == "1 DAY")
    }

    @Test("PUT IN : la quantité et le jour ; départ de la courbe en majuscules ; rien sans date")
    func putIn() throws {
        let day = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12)))
        let label = PotText.startLabel(day, locale: us)
        #expect(label.contains("22") && label == label.uppercased())
        #expect(PotText.putIn(50, since: day, asset: .xlm, locale: us) == "50 XLM · " + label)
        #expect(PotText.putIn(50, since: nil, asset: .xlm, locale: us) == "50 XLM")
        #expect(PotText.startLabel(nil, locale: us).isEmpty)
    }

    @Test("Ligne verte : la croissance réelle depuis le dépôt ; CETES : l'évolution du prix ; rien sans base")
    func sinceLine() {
        #expect(PotText.sinceLine(pot(.defindex, value: "50.12", putIn: 50), locale: us) == "+0.12 XLM since you planted")
        #expect(PotText.sinceLine(pot(.etherfuse, value: "100", basis: 1, price: Decimal(string: "1.0062")), locale: us) == "Price +0.62% since you got them")
        #expect(PotText.sinceLine(pot(.xoxno, value: "20"), locale: us) == nil)
    }

    @Test("Chimpy : la ligne de la maquette quand ça a poussé, une ligne honnête sinon")
    func chimpy() {
        #expect(PotText.chimpyLine(pot(.defindex, value: "50.12", putIn: 50), locale: us) == "That +0.12 XLM really happened. Next week it could be more, or less.")
        #expect(PotText.chimpyLine(pot(.xoxno, value: "500.84", putIn: 500), locale: us) == "Borrowers paid that +0.84 USDC back. No promises about next week.")
        #expect(PotText.chimpyLine(pot(.xoxno, value: "500", putIn: 500), locale: us).hasPrefix("Nothing has grown yet"))
        let down = PotText.chimpyLine(pot(.defindex, value: "49.97", putIn: 50), locale: us)
        #expect(down.hasPrefix("It went down by 0.03 XLM"))
        #expect(PotText.chimpyLine(pot(.xoxno, value: nil, state: .needsRenewal), locale: us).contains("still there"))
    }

    @Test("Tampon : GROWING, TESTNET PRICES pour les CETES sur testnet, rouge pour un pot bloqué")
    func stamp() {
        #expect(PotText.stamp(pot(.defindex, value: "1"), network: nil) == ("Growing", true))
        #expect(PotText.stamp(pot(.etherfuse, value: "1"), network: .testnet) == ("Testnet prices", false))
        #expect(PotText.stamp(pot(.etherfuse, value: "1", state: .frozen), network: .testnet).positive == false)
        #expect(PotText.stamp(pot(.xoxno, value: nil, state: .needsRenewal), network: nil).positive == false)
    }

    @Test("Prix d'un CETES et sa source : « 0.0547 USDC », « ETHERFUSE · 2 MIN AGO »")
    func price() {
        #expect(PotText.unitPrice(Decimal(string: "0.05471")!, locale: us) == "0.0547 USDC")
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        let price = StablebondPrice(code: "CETES", usd: Decimal(string: "0.0547")!, currency: "MXN", fiat: 1, asOf: now.addingTimeInterval(-120))
        #expect(PotText.priceSource(price, now: now) == "ETHERFUSE · 2 MIN AGO")
        #expect(PotText.priceSource(nil) == "UNAVAILABLE RIGHT NOW")
    }

    @Test("La fiche « ? » ne parle ni de risques ni des protocoles en dessous (décision de Barth du 2026-10-18)")
    func info() {
        for mark in ChimpPotProtocol.allCases {
            let text = (PotText.info(mark) + " " + PotText.infoHonesty(mark)).lowercased()
            #expect(!text.contains("risk") && !text.contains("blend"))
        }
    }
}
