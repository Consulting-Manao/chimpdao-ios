import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Prix de l'USDY par l'oracle RedStone (SEP-40, mainnet). Vecteur : la réponse réelle de `lastprice` relevée le
/// 2026-11-05 (`CBMGLKUQ…`, `Asset::Stellar(CB3YA656…)`) : `{ price: 115204120, timestamp: 1793847360 }`, 8 décimales.
struct RedStonePriceTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_793_847_360)

    private func priceData(_ price: Int64, timestamp: UInt64) -> SCValXDR {
        .map([
            SCMapEntryXDR(key: .symbol("price"), val: .i128(Int128PartsXDR(hi: 0, lo: UInt64(price)))),
            SCMapEntryXDR(key: .symbol("timestamp"), val: .u64(timestamp)),
        ])
    }

    @Test("La réponse relevée sur le mainnet : 1 USDY = 1,1520412 $, source RedStone, heure du flux")
    func observedPrice() throws {
        let result = RedStonePriceClient.result(
            from: priceData(115_204_120, timestamp: 1_793_847_360), code: "USDY", decimals: 8,
            now: Self.observedAt.addingTimeInterval(3600), maximumAge: 36 * 3600
        )
        let price = try #require(result.price)
        #expect(price.usd == Decimal(string: "1.1520412"))
        #expect(price.source == "RedStone")
        #expect(price.currency == "USD")
        #expect(price.asOf == Self.observedAt)
        #expect(price.value(of: 100) == Decimal(string: "115.20412"))
    }

    @Test("Trop vieux, absent ou nul : aucun prix (jamais un prix inventé)")
    func noPrice() {
        let old = RedStonePriceClient.result(
            from: priceData(115_204_120, timestamp: 1_793_847_360), code: "USDY", decimals: 8,
            now: Self.observedAt.addingTimeInterval(37 * 3600), maximumAge: 36 * 3600
        )
        #expect(old.price == nil)
        #expect(RedStonePriceClient.result(from: .void, code: "USDY", decimals: 8, now: Self.observedAt, maximumAge: 3600).price == nil)
        #expect(RedStonePriceClient.result(from: priceData(0, timestamp: 1_793_847_360), code: "USDY", decimals: 8, now: Self.observedAt, maximumAge: 3600).price == nil)
    }

    @Test("SEP-40 : l'actif est désigné par son contrat (Asset::Stellar)")
    func assetArgument() throws {
        let argument = try RedStonePriceClient.assetArgument("CB3YA656OYIHU57657I5KGSBRHE5I3OZU4VFC22PYAOANFZHEWNYGAGP")
        guard case .vec(let items?) = argument, items.count == 2, case .symbol("Stellar") = items[0], case .address(let address) = items[1] else {
            Issue.record("unexpected shape \(argument)")
            return
        }
        #expect(address.contractId?.uppercased().isEmpty == false)
    }

    @Test("Testnet : l'USDY est un actif du réseau (SAC de la copie de test), prix par RedStone seulement, jamais par Reflector")
    func usdyIsKnown() throws {
        let config = ChimpNetworkConfig.testnet
        let assets = try SACClient.stellarAssets(config: config)
        #expect(assets.contains { $0.code == "USDY" && $0.contract == config.ondo?.usdy.contract })
        #expect(config.issuedAssets.map(\.code) == ["CETES", "USDY"])
        #expect(PriceOracleConfig.reflector.neverPriced.contains("USDY"))
        #expect(StablebondWalletPrices(config: config)?.entries.map(\.bond.code).prefix(2) == ["CETES", "USDY"])
    }
}
