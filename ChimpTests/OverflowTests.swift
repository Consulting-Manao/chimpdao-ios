import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Revue de sécurité F8 (2026-10-16) : des valeurs lues au réseau (RPC menteur) ne doivent jamais faire planter l'app par
/// un dépassement d'entier. Avant la correction, chacun de ces tests arrêtait l'app (trap).
struct OverflowTests {
    @Test("Arrivée CCTP : des frais plus grands que le montant ne font pas planter (ligne laissée sans détails)")
    func cctpFeeLargerThanAmount() throws {
        let cctp = IntegrationConfig.testnet.cctp
        let drawer = "GBCQATHVGEMQWIP3HANAMXICFDZRABAIJTGKLLJ2FX4L7VH6AXVDV5KK"
        var bytes = [UInt8](try #require(Data(hex: CCTPMessageTests.vectors[0].message)))
        // feeExecuted (corps du burn, octets 164 à 195) mis à 0xFF…FF sur 8 octets : bien plus grand que le montant.
        for index in (148 + 164 + 24)..<(148 + 196) { bytes[index] = 0xFF }
        let message = try CCTPMessage(Data(bytes))
        let arrival = ActivityRecord(
            id: "stellar:h:1", event: .bridgeArrival, hash: "h", from: cctp.forwarder, to: drawer, assetCode: "USDC", amount: 2,
            at: .now, isLocal: false
        )
        #expect(arrival.withArrivalDetails(from: message, cctp: cctp) == arrival)
    }

    @Test("Slippage : un montant immense ne fait pas planter le minimum ni l'impact de prix")
    func slippageExtremes() {
        #expect(Slippage.minimum(of: Int128.max, basisPoints: 50) > 0)
        #expect(Slippage.minimum(of: Int128.max, basisPoints: 50) <= Int128.max)
        _ = Slippage.priceImpactBasisPoints(amountIn: 1, amountOut: 1, reserveIn: 1, reserveOut: Int128.max)
    }

    @Test("XOXNO : un marché aux valeurs négatives ou extrêmes est refusé, sans planter")
    func xoxnoExtremes() {
        let state = XoxnoMarketState(
            supplied: Int128.max, borrowed: Int128.max, cash: Int128.min, maxUtilization: 1,
            paused: false, frozen: false, supplyCap: Int128.min, suppliedInSpoke: Int128.max
        )
        #expect(state.marketWithdrawable == 0)
        #expect(state.remainingCap == 0)
    }

    @Test("Ledger : un numéro de ledger absurde annoncé par le RPC est refusé (sinon « ledger + 120 » planterait)")
    func implausibleLedger() throws {
        #expect(try SorobanClient.plausibleLedger(5_223_000) == 5_223_000)
        #expect(throws: StellarError.self) { try SorobanClient.plausibleLedger(Int(UInt32.max)) }
        #expect(throws: StellarError.self) { try SorobanClient.plausibleLedger(-1) }
    }
}
