import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 2 : swap USDC ↔ CETES sur la paire Soroswap `CD2TAYCQ…`, liquidité minuscule. Vecteurs lus
/// sur testnet le 2026-10-15 : réserves 50,0478335 USDC (`token_0`) / 6 724,4938573 CETES ; le router rend 131,3418012
/// CETES pour 1 USDC et 609,1200424 CETES pour 5 USDC.
struct CetesSwapTests {
    private let usdc = IntegrationAsset(code: "USDC", contract: "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    private let cetes = IntegrationAsset(code: "CETES", contract: CetesAssetTests.cetes)
    private let pair = "CD2TAYCQZEY7U5CTUOV5QSGWHJNN4ZRPRUSMN2KRM2ZE6ZGX5TNU76H2"

    private final class Reader: ContractReading {
        let pair: String, usdc: String
        init(pair: String, usdc: String) { self.pair = pair; self.usdc = usdc }
        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            let i128 = { (values: [Int128]) in SCValXDR.vec(values.map { ContractArgument.i128($0) }) }
            switch function {
            case "pair_exists": return .bool(true)
            case "router_pair_for": return try ContractArgument.address(pair)
            case "token_0": return try ContractArgument.address(usdc)
            case "get_reserves": return i128([500_478_335, 67_244_938_573])
            case "router_get_amounts_out":
                let amountIn = arguments.first.flatMap(ContractArgument.int128) ?? 0
                switch amountIn {
                case 10_000_000: return i128([10_000_000, 1_313_418_012])
                case 50_000_000: return i128([50_000_000, 6_091_200_424])
                default: throw StellarError.rpc("unscripted amount \(amountIn)")
                }
            default: throw StellarError.rpc("unscripted \(function)")
            }
        }
    }

    private func quote(_ units: Int128) async throws -> SwapQuote {
        let adapter = SoroswapAdapter(contracts: IntegrationConfig.testnet.soroswap, reader: Reader(pair: pair, usdc: usdc.contract))
        return try #require(try await adapter.quote(SwapRequest(assetIn: usdc, assetOut: cetes, amountIn: units)))
    }

    @Test("1 USDC → 131,34 CETES : impact 2,24 % (frais compris), sous le seuil de 5 % : pas d'avertissement fort")
    func oneUSDC() async throws {
        let quote = try await quote(10_000_000)
        #expect(quote.amountOut == 1_313_418_012)
        #expect(quote.priceImpactBasisPoints == 224)
        #expect(!Slippage.needsPriceImpactWarning(224))
    }

    @Test("5 USDC → 609,12 CETES : impact 9,33 %, l'avertissement fort se déclenche (E3e, E4i)")
    func fiveUSDC() async throws {
        let quote = try await quote(50_000_000)
        #expect(quote.amountOut == 6_091_200_424)
        #expect(quote.priceImpactBasisPoints == 933)
        #expect(Slippage.needsPriceImpactWarning(933))
    }

    @Test("Écran : un devis à 9,33 % d'impact demande l'avertissement, comme pour XLM/USDC")
    func flowWarns() async throws {
        let service = MockSwapService(quoteScenario: .bigImpact, delay: .zero)
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        model.choose(.usdc, for: .given)
        model.choose(.cetes, for: .received)
        model.setAmount(5)
        await model.refreshQuote()
        let quote = try #require(model.currentQuote)
        #expect((quote.given, quote.received) == (.usdc, .cetes))
        #expect(quote.needsPriceImpactWarning)
    }
}
