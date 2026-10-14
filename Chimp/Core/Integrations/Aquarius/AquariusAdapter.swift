import Foundation
import stellarsdk

/// Aquarius comme second protocole d'échange (D2). **Hors de `reference/`** : uniquement des appels de contrats, sans
/// l'API `find-path` (décision du 2026-10-14) ; fonctions et erreurs lues dans les spécifications publiées sur testnet
/// (router `CBCFTQSP…`, pool à produit constant `CAYBMZYJ…`).
///
/// - Pools : `router.get_pools(jetons triés)` → `{ pool_index: pool }`, gardés en mémoire (ils ne changent qu'à une
///   remise à zéro du testnet).
/// - Devis : `router.estimate_swap(jetons, donné, reçu, pool_index, montant)` sur **chaque** pool direct, le meilleur
///   retenu ; puis, si aucun des deux actifs n'est l'actif pivot (USDC de Circle), le meilleur pool de chaque saut
///   donné → USDC → reçu. La route qui rend le plus gagne (à égalité, la directe).
/// - Impact de prix : réserves du pool (`get_reserves`) pour un pool à produit constant, comme Soroswap ; pour un autre
///   type (stable, concentré), écart avec le prix d'un montant mille fois plus petit. Deux sauts : impacts composés.
/// - Appel : `swap` pour un pool, `swap_chained` pour deux (`AquariusCalls`), forme `AquariusAuthShape`.
///
/// Un pool qui refuse le devis (vide, en pause, introuvable) est écarté ; toute autre erreur remonte (règle 7).
final class AquariusAdapter: SwapAdapter {
    let id = "aquarius"
    let name = "Aquarius"
    let contracts: IntegrationConfig.Aquarius
    /// L'actif d'un saut intermédiaire (USDC de Circle) ; `nil` : pools directs seulement.
    let hub: String?
    private let reader: ContractReading

    /// Les pools de chaque couple de jetons triés (`get_pools`).
    private var pools: [[String]: [(hash: Data, pool: String)]] = [:]
    /// Le type de chaque pool (`get_info`), qui ne change jamais.
    private var poolTypes: [String: String] = [:]

    init(contracts: IntegrationConfig.Aquarius, hub: String?, reader: ContractReading) {
        self.contracts = contracts
        self.hub = hub
        self.reader = reader
    }

    // MARK: Devis

    func quote(_ request: SwapRequest) async throws -> SwapQuote? {
        let tokenIn = request.assetIn.contract, tokenOut = request.assetOut.contract
        guard request.amountIn > 0, tokenIn != tokenOut else { return nil }

        // Montants en `TokenAmount` à travers les fonctions `async` (règle de l'app, `TokenAmount`).
        var routes: [(hops: [(hop: SwapHop, out: Int128)], out: Int128)] = []
        if let direct = try await bestHop(from: tokenIn, to: tokenOut, amount: TokenAmount(request.amountIn)) {
            routes.append(([direct], direct.out))
        }
        if let hub, hub != tokenIn, hub != tokenOut,
           let first = try await bestHop(from: tokenIn, to: hub, amount: TokenAmount(request.amountIn)),
           let second = try await bestHop(from: hub, to: tokenOut, amount: TokenAmount(first.out)) {
            routes.append(([first, second], second.out))
        }
        guard let best = routes.reduce(nil, { (best: (hops: [(hop: SwapHop, out: Int128)], out: Int128)?, route) in
            guard let best else { return route }
            return route.out > best.out ? route : best
        }) else { return nil }

        var amountIn = request.amountIn
        var impacts: [Int?] = []
        for (hop, out) in best.hops {
            let small = amountIn / 1_000
            let reference = try await spotReference(of: hop, small: small > 0 ? TokenAmount(small) : nil)
            impacts.append(reference.flatMap {
                Slippage.priceImpactBasisPoints(amountIn: amountIn, amountOut: out, reserveIn: $0.reserveIn, reserveOut: $0.reserveOut)
            })
            amountIn = out
        }
        let hops = best.hops.map(\.hop)
        return SwapQuote(
            protocolID: id, request: request, route: [tokenIn] + hops.map(\.tokenOut), amountOut: best.out,
            priceImpactBasisPoints: Self.compounded(impacts),
            firstHopVenue: hops.count == 1 ? hops[0].pool : contracts.router,
            hops: hops
        )
    }

    /// Le pool direct qui rend le plus pour `amount`, `nil` s'il n'y en a aucun. Les devis des pools partent ensemble.
    private func bestHop(from tokenIn: String, to tokenOut: String, amount: TokenAmount) async throws -> (hop: SwapHop, out: Int128)? {
        let tokens = try AquariusCalls.sortedTokens(tokenIn, tokenOut)
        let units = try AquariusCalls.u128(amount.units)
        let candidates = try await poolsOf(tokens)
        let estimates = try candidates.map { candidate in
            let arguments = try Self.estimateArguments(tokens: tokens, from: tokenIn, to: tokenOut, poolHash: candidate.hash, units: units)
            return Task { try await self.estimate(arguments) }
        }
        var best: (hop: SwapHop, out: Int128)?
        for (candidate, task) in zip(candidates, estimates) {
            let out: Int128
            do {
                out = try await task.value
            } catch let error where swapError(for: error) != nil {
                continue // ce pool refuse (vide, en pause…) : on essaie les autres
            }
            guard out > 0, out > (best?.out ?? 0) else { continue }
            best = (SwapHop(tokens: tokens, poolHash: candidate.hash, pool: candidate.pool, tokenOut: tokenOut), out)
        }
        return best
    }

    /// Les arguments de `estimate_swap(jetons, donné, reçu, pool_index, montant)`.
    static func estimateArguments(tokens: [String], from tokenIn: String, to tokenOut: String, poolHash: Data, units: SCValXDR) throws -> [SCValXDR] {
        [
            .vec(try tokens.map { try ContractArgument.address($0) }),
            try ContractArgument.address(tokenIn), try ContractArgument.address(tokenOut),
            .bytes(poolHash), units,
        ]
    }

    private func estimate(_ arguments: [SCValXDR]) async throws -> Int128 {
        let value = try await reader.readValue(contract: contracts.router, function: "estimate_swap", arguments: arguments)
        guard let out = AquariusCalls.int128(value) else { throw ContractArgument.ArgumentError.malformed("estimate is not a u128") }
        return out
    }

    /// Les pools d'un couple de jetons triés, lus une fois.
    private func poolsOf(_ tokens: [String]) async throws -> [(hash: Data, pool: String)] {
        if let known = pools[tokens] { return known }
        let found = try Self.pools(try await reader.readValue(
            contract: contracts.router, function: "get_pools", arguments: [.vec(try tokens.map { try ContractArgument.address($0) })]
        ))
        pools[tokens] = found
        return found
    }

    /// Le prix « spot » d'un saut, sous forme de deux quantités (`reserveIn` donne `reserveOut`) : les réserves du pool à
    /// produit constant (comme Soroswap), sinon le devis d'un montant mille fois plus petit (`small`). `nil` si on ne
    /// peut pas le connaître.
    private func spotReference(of hop: SwapHop, small: TokenAmount?) async throws -> (reserveIn: Int128, reserveOut: Int128)? {
        guard let tokenIn = hop.tokenIn else { return nil }
        if try await poolType(of: hop) == "constant_product" {
            let reserves = try Self.reserves(try await reader.readValue(
                contract: contracts.router, function: "get_reserves",
                arguments: [.vec(try hop.tokens.map { try ContractArgument.address($0) }), .bytes(hop.poolHash)]
            ))
            return hop.tokens[0] == tokenIn ? (reserves.0, reserves.1) : (reserves.1, reserves.0)
        }
        guard let small else { return nil }
        let smallOut = try await estimate(try Self.estimateArguments(
            tokens: hop.tokens, from: tokenIn, to: hop.tokenOut, poolHash: hop.poolHash, units: try AquariusCalls.u128(small.units)
        ))
        return (small.units, smallOut)
    }

    private func poolType(of hop: SwapHop) async throws -> String? {
        if let known = poolTypes[hop.pool] { return known }
        let info = try await reader.readValue(
            contract: contracts.router, function: "get_info",
            arguments: [.vec(try hop.tokens.map { try ContractArgument.address($0) }), .bytes(hop.poolHash)]
        )
        let type = info.map?.first { $0.key.symbol == "pool_type" }?.val.symbol
        if let type { poolTypes[hop.pool] = type }
        return type
    }

    /// Impacts de plusieurs sauts composés : 1 − ∏(1 − impact). `nil` si l'un d'eux est inconnu.
    static func compounded(_ impacts: [Int?]) -> Int? {
        var kept: Int128 = 10_000
        for impact in impacts {
            guard let impact else { return nil }
            kept = kept * Int128(10_000 - min(max(impact, 0), 10_000)) / 10_000
        }
        return Int(10_000 - kept)
    }

    // MARK: Appel

    func swapCall(for quote: SwapQuote, minimumOut: Int128, authorizer: String, now: UInt64) throws -> ContractCall {
        if quote.hops.count == 1 {
            return try AquariusCalls.swap(
                router: contracts.router, user: authorizer, hop: quote.hops[0], amountIn: quote.request.amountIn, minimumOut: minimumOut
            )
        }
        return try AquariusCalls.chained(
            router: contracts.router, user: authorizer, tokenIn: quote.request.assetIn.contract, hops: quote.hops,
            amountIn: quote.request.amountIn, minimumOut: minimumOut
        )
    }

    func authShape(for quote: SwapQuote) -> any AuthShape {
        quote.hops.count == 1
            ? AquariusAuthShape(router: contracts.router, pool: quote.hops[0].pool, poolTokens: quote.hops[0].tokens)
            : AquariusAuthShape(router: contracts.router, pool: "", poolTokens: [])
    }

    func terms(of call: ContractCall) throws -> SignedTerms {
        try AquariusCalls.terms(of: call, router: contracts.router)
    }

    /// Aquarius ne porte pas d'échéance : la fenêtre de l'autorisation de la carte borne le swap.
    var deadlineSeconds: UInt64? { nil }

    func swapError(for error: Error) -> SwapError? {
        Self.swapError(for: error)
    }

    /// `swap` et `swap_chained` rendent la quantité reçue (`u128`).
    func receivedUnits(_ returnValue: SCValXDR) -> Int128? {
        AquariusCalls.int128(returnValue)
    }

    // MARK: Lecture des réponses

    /// `Map<BytesN<32>, Address>` de `get_pools`, rangé par `pool_index` (ordre stable).
    static func pools(_ value: SCValXDR) throws -> [(hash: Data, pool: String)] {
        guard let entries = value.map else { throw ContractArgument.ArgumentError.malformed("pools are not a map") }
        return try entries.map { entry in
            guard let hash = entry.key.bytes, hash.count == 32,
                  let pool = try? entry.val.address?.toStrKey(), pool.hasPrefix("C") else {
                throw ContractArgument.ArgumentError.malformed("pool entry is malformed")
            }
            return (hash, pool)
        }
        .sorted { $0.hash.lexicographicallyPrecedes($1.hash) }
    }

    /// `Vec<u128>` des réserves, dans l'ordre des jetons triés.
    static func reserves(_ value: SCValXDR) throws -> (Int128, Int128) {
        guard let items = value.vec, items.count == 2,
              let first = AquariusCalls.int128(items[0]), let second = AquariusCalls.int128(items[1]) else {
            throw ContractArgument.ArgumentError.malformed("reserves are not two u128")
        }
        return (first, second)
    }

    /// Les refus des contrats Aquarius (spécifications du router et du pool lues sur testnet le 2026-10-14) traduits en
    /// `SwapError`. `nil` : autre erreur, à faire remonter telle quelle.
    static func swapError(for error: Error) -> SwapError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        let codes: [(Int, SwapError)] = [
            (2006, .slippageExceeded),                                           // OutMinNotSatisfied
            (301, .noRoute), (404, .noRoute), (307, .noRoute), (2007, .noRoute), // pool introuvable, chemin vide, même jeton
            (206, .noRoute),                                                     // PoolSwapKilled : swaps du pool en pause
            (2010, .insufficientLiquidity), (324, .insufficientLiquidity), (2018, .insufficientLiquidity), // vide, montant nul
        ]
        for (code, swapError) in codes
        where message.range(of: #"Error\(Contract,\s*#\#(code)\)"#, options: .regularExpression) != nil {
            return swapError
        }
        return nil
    }
}
