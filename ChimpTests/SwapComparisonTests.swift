import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 3, étape 3 : le registre compare les vrais adaptateurs Soroswap et Aquarius (réponses du testnet du
/// 2026-10-14 rejouées) et garde le meilleur ; si l'un ne répond pas, l'autre sert et la panne est rendue.
/// Pour 10 XLM : Soroswap 1,0619368 USDC, Aquarius 4,4560433 USDC (les prix du testnet n'ont aucun sens).
struct SwapComparisonTests {
    private let config = IntegrationConfig.testnet
    private let xlm = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    private let usdc = IntegrationAsset(code: "USDC", contract: "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    private let soroswapPair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"

    /// Le testnet rejoué, par contrat : router Soroswap, sa paire XLM/USDC, router Aquarius (un seul pool, à 0,3 %).
    private final class TestnetReader: ContractReading {
        let config: IntegrationConfig
        let pair: String
        var soroswapDown = false
        var aquariusDown = false
        /// Aquarius rend le devis du défaut de Swift 6.3 (14,57 millions d'USDC pour 10 XLM).
        var aquariusCorrupted = false

        init(config: IntegrationConfig, pair: String) {
            self.config = config
            self.pair = pair
        }

        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            let i128 = { (values: [Int128]) in SCValXDR.vec(values.map { ContractArgument.i128($0) }) }
            switch (contract, function) {
            case (config.soroswap.router, _) where soroswapDown, (config.soroswap.factory, _) where soroswapDown,
                 (config.aquarius.router, _) where aquariusDown:
                throw StellarError.rpc("timeout")
            case (config.soroswap.factory, "pair_exists"): return .bool(true)
            case (config.soroswap.router, "router_get_amounts_out"): return i128([100_000_000, 10_619_368])
            case (config.soroswap.router, "router_pair_for"): return try ContractArgument.address(pair)
            case (pair, "token_0"): return try ContractArgument.address("CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
            case (pair, "get_reserves"): return i128([4_182_149_447_905, 39_264_032_674_308])
            case (config.aquarius.router, "get_pools"):
                // Le pool à 0,3 % seul (`9ac7a9cd…` → `CAYBMZYJ…`).
                return .map([SCMapEntryXDR(
                    key: .bytes(Data(hex: "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e")!),
                    val: try ContractArgument.address("CAYBMZYJCOMMOHOGOGBK7ANIKF3JPZAL4D7SWAPVPHC4WBMOUT5DJN5B")
                )])
            case (config.aquarius.router, "estimate_swap"): return ContractArgument.u128(aquariusCorrupted ? 14_571_967_060_779 : 44_560_433)
            case (config.aquarius.router, "get_info"):
                return try SCValXDR(xdr: "AAAAEQAAAAEAAAACAAAADwAAAANmZWUAAAAAAwAAAB4AAAAPAAAACXBvb2xfdHlwZQAAAAAAAA8AAAAQY29uc3RhbnRfcHJvZHVjdA==")
            case (config.aquarius.router, "get_reserves"):
                return try SCValXDR(xdr: "AAAAEAAAAAEAAAACAAAACQAAAAAAAAAAAAANQOlTCYoAAAAJAAAAAAAAAAAAAB2nUFKohA==")
            default:
                throw StellarError.rpc("no scripted reply for \(function) on \(contract.prefix(8))")
            }
        }
    }

    private func registry(_ reader: TestnetReader) -> IntegrationRegistry {
        IntegrationRegistry(swapAdapters: [
            SoroswapAdapter(contracts: config.soroswap, reader: reader),
            AquariusAdapter(contracts: config.aquarius, hub: usdc.contract, reader: reader),
        ], yieldAdapters: [])
    }

    private var request: SwapRequest { SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000) }

    @Test("Les deux répondent : Aquarius gagne (4,4560433 contre 1,0619368 USDC), les deux devis sont gardés")
    func bothAnswer() async throws {
        let comparison = await registry(TestnetReader(config: config, pair: soroswapPair)).bestQuote(request)
        #expect(comparison.best?.protocolID == "aquarius")
        #expect(comparison.best?.amountOut == 44_560_433)
        #expect(comparison.quotes.map(\.amountOut) == [10_619_368, 44_560_433])
        #expect(comparison.answered == ["soroswap", "aquarius"])
        #expect(comparison.failures.isEmpty)
        // Même tolérance pour tous : le meilleur devis est aussi le meilleur minimum reçu.
        #expect(Slippage.minimum(of: 44_560_433, basisPoints: 50) > Slippage.minimum(of: 10_619_368, basisPoints: 50))
    }

    @Test("Aquarius en panne : Soroswap sert, et la panne d'Aquarius est rendue")
    func aquariusDown() async throws {
        let reader = TestnetReader(config: config, pair: soroswapPair)
        reader.aquariusDown = true
        let comparison = await registry(reader).bestQuote(request)
        #expect(comparison.best?.protocolID == "soroswap")
        #expect(comparison.answered == ["soroswap"])
        #expect(comparison.failures.map(\.protocolID) == ["aquarius"])
    }

    @Test("Soroswap en panne : Aquarius sert ; les deux en panne : pas de devis, deux pannes")
    func soroswapDown() async throws {
        let reader = TestnetReader(config: config, pair: soroswapPair)
        reader.soroswapDown = true
        let comparison = await registry(reader).bestQuote(request)
        #expect(comparison.best?.protocolID == "aquarius")
        #expect(comparison.failures.map(\.protocolID) == ["soroswap"])

        reader.aquariusDown = true
        let none = await registry(reader).bestQuote(request)
        #expect(none.best == nil)
        #expect(none.failures.map(\.protocolID) == ["soroswap", "aquarius"])
        #expect(none.answered.isEmpty)
    }

    @Test("Devis corrompu chez Aquarius : écarté (Soroswap sert, Aquarius signalé) ; seul : aucun prix, erreur dédiée")
    func corruptedQuoteNeverShown() async throws {
        let reader = TestnetReader(config: config, pair: soroswapPair)
        reader.aquariusCorrupted = true
        let comparison = await registry(reader).bestQuote(request)
        #expect(comparison.best?.protocolID == "soroswap")
        #expect(comparison.best?.amountOut == 10_619_368)
        #expect(comparison.quotes.map(\.protocolID) == ["soroswap"], "Le devis corrompu n'est jamais un devis")
        #expect(comparison.failures.map(\.protocolID) == ["aquarius"])
        #expect((comparison.failures.first?.error as? SwapError) == .implausibleQuote)

        reader.soroswapDown = true
        let none = await registry(reader).bestQuote(request)
        #expect(none.best == nil)
        #expect(none.failures.contains { ($0.error as? SwapError) == .implausibleQuote })
    }

    @Test("Devis Aquarius → appel au minimum, bornes = écran, arbre déclaré pour le Main et pour une Pocket")
    func aquariusQuoteToTree() async throws {
        let quote = try #require(await registry(TestnetReader(config: config, pair: soroswapPair)).bestQuote(request).best)
        let adapter = AquariusAdapter(contracts: config.aquarius, hub: usdc.contract, reader: TestnetReader(config: config, pair: soroswapPair))
        let minimum = Slippage.minimum(of: quote.amountOut, basisPoints: 50)
        for authorizer in [CallAuthorizer.account("CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"),
                           .pocket("CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q")] {
            let call = try adapter.swapCall(for: quote, minimumOut: minimum, authorizer: authorizer.address, now: 0)
            let shown = SignedTerms(
                action: .swap, contract: config.aquarius.router, authorizer: authorizer.address, assetIn: xlm.contract,
                amountIn: 100_000_000, assetOut: usdc.contract, minimumOut: minimum, route: quote.route, deadline: nil
            )
            try BoundsCheck.verify(shown: shown, signed: try adapter.terms(of: call), quotedOut: quote.amountOut, now: 0)
            let trees = try DeclaredInvocations.build(root: call, authorizers: [authorizer], shape: adapter.authShape(for: quote))
            #expect(trees.count == 1)
            #expect(trees[0].invocation.subInvocations.count == 1) // pool.swap, sous lequel la prise
        }
    }
}
