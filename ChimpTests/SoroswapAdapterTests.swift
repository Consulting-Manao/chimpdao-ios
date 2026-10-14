import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 2, étape 1 : l'adaptateur Soroswap réel, avec des réponses du RPC rejouées.
/// Valeurs lues sur testnet le 2026-10-14 (simulations, rien de signé) : 10 XLM → 1,0619368 USDC, paire XLM/USDC
/// `CCBX3NZT…`, `token_0` = USDC, réserves 418 214,94 USDC / 3 926 403,27 XLM.
struct SoroswapAdapterTests {
    private let contracts = IntegrationConfig.testnet.soroswap
    private let xlm = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    private let usdc = IntegrationAsset(code: "USDC", contract: "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    private let pair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"

    /// Réponses du RPC rejouées, par fonction ; garde les lectures reçues.
    private final class ScriptedReader: ContractReading {
        var replies: [String: Result<SCValXDR, Error>] = [:]
        private(set) var calls: [String] = []

        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            calls.append(function)
            guard let reply = replies[function] else { throw StellarError.rpc("no scripted reply for \(function)") }
            return try reply.get()
        }
    }

    private func amounts(_ values: [Int128]) -> SCValXDR {
        .vec(values.map { ContractArgument.i128($0) })
    }

    private func testnetReader() throws -> ScriptedReader {
        let reader = ScriptedReader()
        reader.replies = [
            "router_get_amounts_out": .success(amounts([100_000_000, 10_619_368])),
            "router_pair_for": .success(try ContractArgument.address(pair)),
            "token_0": .success(try ContractArgument.address(usdc.contract)),
            "get_reserves": .success(amounts([4_182_149_447_905, 39_264_032_674_308])),
        ]
        return reader
    }

    private var request: SwapRequest { SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000) }

    @Test("Devis : quantité du router, route directe, paire vérifiée, impact de prix sur les réserves (30 pb, les frais)")
    func quote() async throws {
        let adapter = SoroswapAdapter(contracts: contracts, reader: try testnetReader())
        let quote = try #require(try await adapter.quote(request))
        #expect(quote.protocolID == "soroswap")
        #expect(quote.amountOut == 10_619_368)
        #expect(quote.route == [xlm.contract, usdc.contract])
        #expect(quote.firstHopVenue == pair)
        #expect(quote.priceImpactBasisPoints == 30)
    }

    @Test("Paire lue une seule fois (gardée en mémoire), le devis à chaque fois")
    func pairIsMemoized() async throws {
        let reader = try testnetReader()
        let adapter = SoroswapAdapter(contracts: contracts, reader: reader)
        _ = try await adapter.quote(request)
        _ = try await adapter.quote(SwapRequest(assetIn: usdc, assetOut: xlm, amountIn: 10_000_000))
        #expect(reader.calls.filter { $0 == "router_pair_for" }.count == 1)
        #expect(reader.calls.filter { $0 == "token_0" }.count == 1)
        #expect(reader.calls.filter { $0 == "router_get_amounts_out" }.count == 2)
    }

    @Test("Devis invraisemblable (meilleur que le prix des réserves de la paire) : refusé, jamais affiché")
    func implausibleQuote() async throws {
        let reader = try testnetReader()
        // 10 XLM → 10 000 USDC, alors que les réserves en donnent ~1,065 USDC.
        reader.replies["router_get_amounts_out"] = .success(amounts([100_000_000, 100_000_000_000]))
        await #expect(throws: SwapError.implausibleQuote) {
            _ = try await SoroswapAdapter(contracts: contracts, reader: reader).quote(request)
        }
    }

    @Test("Paire qui ne contient pas ces actifs : refusée")
    func foreignPairRefused() async throws {
        let reader = try testnetReader()
        reader.replies["token_0"] = .success(try ContractArgument.address("CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"))
        await #expect(throws: ContractArgument.ArgumentError.self) {
            _ = try await SoroswapAdapter(contracts: contracts, reader: reader).quote(request)
        }
    }

    @Test("Paire inexistante ou pool vide : pas de route (nil) ; panne réseau : l'erreur remonte")
    func noRouteAndNetwork() async throws {
        for code in [509, 409, 205, 511] {
            let reader = try testnetReader()
            reader.replies["router_get_amounts_out"] = .failure(StellarError.simulationFailed("HostError: Error(Contract, #\(code))"))
            #expect(try await SoroswapAdapter(contracts: contracts, reader: reader).quote(request) == nil)
        }
        let reader = try testnetReader()
        reader.replies["router_get_amounts_out"] = .failure(StellarError.rpc("timeout"))
        await #expect(throws: StellarError.rpc("timeout")) {
            _ = try await SoroswapAdapter(contracts: contracts, reader: reader).quote(request)
        }
    }

    @Test("Montant nul ou mêmes actifs : pas de devis, aucune lecture")
    func emptyRequests() async throws {
        let reader = try testnetReader()
        let adapter = SoroswapAdapter(contracts: contracts, reader: reader)
        #expect(try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 0)) == nil)
        #expect(try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: xlm, amountIn: 1)) == nil)
        #expect(reader.calls.isEmpty)
    }

    @Test("Appel, forme et bornes : swap_exact_tokens_for_tokens au nom de l'autorisateur, échéance + 300 s, prise vers la paire")
    func callShapeTerms() async throws {
        let adapter = SoroswapAdapter(contracts: contracts, reader: try testnetReader())
        let quote = try #require(try await adapter.quote(request))
        let call = try adapter.swapCall(for: quote, minimumOut: 10_566_271, authorizer: account, now: 1_000)
        #expect(call == (try SoroswapCalls.swap(
            router: contracts.router, amountIn: 100_000_000, minimumOut: 10_566_271, path: [xlm.contract, usdc.contract], to: account, deadline: 1_300
        )))
        let terms = try adapter.terms(of: call)
        #expect(terms.minimumOut == 10_566_271)
        #expect(terms.deadline == 1_300)
        let invocation = try IntegrationCallClient.declaredInvocation(call: call, authorizer: .account(account), shape: adapter.authShape(for: quote))
        #expect(try XDREncoder.encode(invocation.subInvocations[0])
                == XDREncoder.encode(try TokenShape.transfer(token: xlm.contract, from: account, to: pair, units: 100_000_000).invocation()))
    }

    @Test("Refus des contrats Soroswap traduits : minimum non atteint, échéance passée, pas de paire, liquidité ; le reste remonte tel quel")
    func errorMapping() {
        #expect(SoroswapAdapter.swapError(for: StellarError.simulationFailed("Error(Contract, #507)")) == .slippageExceeded)
        #expect(SoroswapAdapter.swapError(for: StellarError.submitFailed("Error(Contract, #407)")) == .slippageExceeded)
        #expect(SoroswapAdapter.swapError(for: StellarError.simulationFailed("HostError: Error(Contract, #503)")) == .deadlineExpired)
        #expect(SoroswapAdapter.swapError(for: StellarError.transactionFailed(hash: "h", detail: "Error(Contract, #509)")) == .noRoute)
        #expect(SoroswapAdapter.swapError(for: StellarError.simulationFailed("Error(Contract, #302)")) == .insufficientLiquidity)
        #expect(SoroswapAdapter.swapError(for: StellarError.simulationFailed("Error(Contract, #301)")) == nil)
        #expect(SoroswapAdapter.swapError(for: StellarError.simulationFailed("Error(Contract, #5070)")) == nil)
        #expect(SoroswapAdapter.swapError(for: URLError(.timedOut)) == nil)
    }
}
