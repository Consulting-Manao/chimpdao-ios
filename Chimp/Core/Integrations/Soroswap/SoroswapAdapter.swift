import Foundation
import stellarsdk

/// Soroswap comme protocole d'échange : portage du chemin de lecture et de `runSwap`
/// (`reference/terminal/src/modules/earn/soroswap/view.ts` et `soroswap.ts`).
///
/// - Devis : `router.router_get_amounts_out(montant, chemin)`, l'arithmétique du router lui-même (jamais recalculée ici).
/// - Paire : `router.router_pair_for(a, b)`, vérifiée (`token_0` est l'un des deux actifs) et gardée en mémoire, comme
///   `pairAddrMemo` ; ses réserves donnent l'impact de prix.
/// - Route : directe (une paire). Les deux actifs de la phase 2 (XLM, USDC de Circle) ont une paire sur testnet.
/// - Appel : `swap_exact_tokens_for_tokens(montant, minimum, chemin, to = autorisateur, échéance = maintenant + 300 s)`,
///   forme `SoroswapAuthShape` (la prise va à la paire).
final class SoroswapAdapter: SwapAdapter {
    let id = "soroswap"
    let name = "Soroswap"
    let contracts: IntegrationConfig.Soroswap
    private let reader: ContractReading

    /// Paire vérifiée de chaque couple d'actifs (`pairAddrMemo`, `token0Memo`) : ne change jamais pour un déploiement.
    private var pairs: [String: (pair: String, token0: String)] = [:]

    init(contracts: IntegrationConfig.Soroswap, reader: ContractReading) {
        self.contracts = contracts
        self.reader = reader
    }

    // MARK: Devis

    func quote(_ request: SwapRequest) async throws -> SwapQuote? {
        let tokenIn = request.assetIn.contract, tokenOut = request.assetOut.contract
        guard request.amountIn > 0, tokenIn != tokenOut else { return nil }
        let path = [tokenIn, tokenOut]
        let amounts: [Int128]
        do {
            amounts = try Self.amounts(try await reader.readValue(
                contract: contracts.router, function: "router_get_amounts_out",
                arguments: [ContractArgument.i128(request.amountIn), .vec(try path.map { try ContractArgument.address($0) })]
            ))
        } catch {
            // Paire absente ou pool vide : pas de route chez Soroswap (le registre essaiera les autres protocoles).
            switch Self.swapError(for: error) {
            case .noRoute?, .insufficientLiquidity?: return nil
            default: throw error
            }
        }
        guard amounts.count == path.count, let out = amounts.last, out > 0 else { return nil }
        let pair = try await verifiedPair(tokenIn, tokenOut)
        let reserves = try Self.reserves(try await reader.readValue(contract: pair.pair, function: "get_reserves", arguments: []))
        let (reserveIn, reserveOut) = pair.token0 == tokenIn ? (reserves.0, reserves.1) : (reserves.1, reserves.0)
        return SwapQuote(
            protocolID: id, request: request, route: path, amountOut: out,
            priceImpactBasisPoints: Slippage.priceImpactBasisPoints(
                amountIn: request.amountIn, amountOut: out, reserveIn: reserveIn, reserveOut: reserveOut
            ),
            firstHopVenue: pair.pair
        )
    }

    /// La paire des deux actifs, lue au router puis vérifiée : son `token_0` doit être l'un d'eux.
    func verifiedPair(_ tokenA: String, _ tokenB: String) async throws -> (pair: String, token0: String) {
        let key = [tokenA, tokenB].sorted().joined(separator: "|")
        if let known = pairs[key] { return known }
        let pairValue = try await reader.readValue(
            contract: contracts.router, function: "router_pair_for",
            arguments: [try ContractArgument.address(tokenA), try ContractArgument.address(tokenB)]
        )
        guard let pair = try? pairValue.address?.toStrKey(), pair.hasPrefix("C") else {
            throw ContractArgument.ArgumentError.malformed("router_pair_for returned \(pairValue)")
        }
        let tokenValue = try await reader.readValue(contract: pair, function: "token_0", arguments: [])
        guard let token0 = try? tokenValue.address?.toStrKey(), token0 == tokenA || token0 == tokenB else {
            throw ContractArgument.ArgumentError.malformed("pair \(pair.prefix(8))… doesn't hold these assets")
        }
        pairs[key] = (pair, token0)
        return (pair, token0)
    }

    // MARK: Appel

    func swapCall(for quote: SwapQuote, minimumOut: Int128, authorizer: String, now: UInt64) throws -> ContractCall {
        try SoroswapCalls.swap(
            router: contracts.router, amountIn: quote.request.amountIn, minimumOut: minimumOut, path: quote.route,
            to: authorizer, deadline: now + SoroswapCalls.deadlineSeconds
        )
    }

    func authShape(for quote: SwapQuote) -> any AuthShape {
        SoroswapAuthShape(router: contracts.router, pair: quote.firstHopVenue)
    }

    func terms(of call: ContractCall) throws -> SignedTerms {
        try SoroswapCalls.terms(of: call, router: contracts.router)
    }

    // MARK: Lecture des réponses

    /// `Vec<i128>` des montants à chaque saut.
    static func amounts(_ value: SCValXDR) throws -> [Int128] {
        guard let items = value.vec else { throw ContractArgument.ArgumentError.malformed("amounts are not a list") }
        return try items.map {
            guard let amount = ContractArgument.int128($0) else { throw ContractArgument.ArgumentError.malformed("amount is not an i128") }
            return amount
        }
    }

    /// `(reserve_0, reserve_1)` de la paire.
    static func reserves(_ value: SCValXDR) throws -> (Int128, Int128) {
        let amounts = try amounts(value)
        guard amounts.count == 2 else { throw ContractArgument.ArgumentError.malformed("reserves are not a pair") }
        return (amounts[0], amounts[1])
    }

    /// Les refus des contrats Soroswap (spécifications lues sur testnet le 2026-10-14) traduits en `SwapError` :
    /// router `4xx`, router combiné `5xx`, bibliothèque `3xx`, factory `205`. `nil` : autre erreur, à faire remonter telle quelle.
    static func swapError(for error: Error) -> SwapError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        let codes: [(Int, SwapError)] = [
            (407, .slippageExceeded), (507, .slippageExceeded),
            (403, .deadlineExpired), (503, .deadlineExpired),
            (409, .noRoute), (509, .noRoute), (205, .noRoute), (305, .noRoute), (514, .noRoute),
            (302, .insufficientLiquidity), (511, .insufficientLiquidity),
        ]
        for (code, swapError) in codes
        where message.range(of: #"Error\(Contract,\s*#\#(code)\)"#, options: .regularExpression) != nil {
            return swapError
        }
        return nil
    }
}
