import Foundation
import stellarsdk

/// Les appels du router Aquarius, construits et relus. **Hors de `reference/`** (le terminal ne connaît pas Aquarius) :
/// signatures lues dans la spécification du router publiée sur testnet (`CBCFTQSP…`, 2026-10-14) et dans la documentation
/// d'Aquarius pour les intégrateurs ; arbres d'autorisation confirmés par simulation (`AquariusAuthShape`).
///
/// - `swap(user, tokens, token_in, token_out, pool_index, in_amount, out_min) -> u128` : un pool.
/// - `swap_chained(user, swaps_chain, token_in, in_amount, out_min) -> u128` : plusieurs pools, chaque maillon
///   `(tokens, pool_index, token_out)`. Utilisé ici pour un saut via l'USDC.
///
/// Les montants sont des **`u128`** (Soroswap et les SAC : `i128`) ; un montant négatif est refusé avant d'être encodé.
/// Les listes de jetons sont **triées par les octets des contrats** (`order_token_ids` de la documentation) : un ordre
/// différent fait échouer l'appel (`#2002 TokensNotSorted`). Aquarius ne porte pas d'échéance : la fenêtre de
/// l'autorisation de la carte (~10 minutes) borne le swap.
enum AquariusCalls {
    static let swapFunction = "swap"
    static let chainedFunction = "swap_chained"

    /// Un pool traversé : ses deux jetons triés, son identifiant dans le router (`pool_index`, 32 octets), son contrat,
    /// et le jeton obtenu.
    struct Hop: Equatable, Hashable, Sendable {
        let tokens: [String]
        let poolHash: Data
        let pool: String
        let tokenOut: String

        /// Le jeton donné à ce pool : l'autre des deux.
        var tokenIn: String? { tokens.first { $0 != tokenOut } }
    }

    /// Les deux jetons dans l'ordre du router : par les 32 octets de leur contrat, comme des entiers non signés.
    static func sortedTokens(_ tokenA: String, _ tokenB: String) throws -> [String] {
        let a = try tokenA.decodeContractId(), b = try tokenB.decodeContractId()
        return a.lexicographicallyPrecedes(b) ? [tokenA, tokenB] : [tokenB, tokenA]
    }

    /// `swap` sur un seul pool. `user` autorise, donne `amountIn` de `tokenIn` et reçoit au moins `minimumOut`.
    static func swap(router: String, user: String, hop: Hop, amountIn: Int128, minimumOut: Int128) throws -> ContractCall {
        guard let tokenIn = hop.tokenIn else { throw ContractArgument.ArgumentError.malformed("pool doesn't hold the asset given") }
        return ContractCall(contract: router, function: swapFunction, arguments: [
            try ContractArgument.address(user),
            .vec(try hop.tokens.map { try ContractArgument.address($0) }),
            try ContractArgument.address(tokenIn),
            try ContractArgument.address(hop.tokenOut),
            .bytes(hop.poolHash),
            try u128(amountIn),
            try u128(minimumOut),
        ])
    }

    /// `swap_chained` : `tokenIn` traverse chaque pool de `hops`, dans l'ordre.
    static func chained(router: String, user: String, tokenIn: String, hops: [Hop], amountIn: Int128, minimumOut: Int128) throws -> ContractCall {
        guard !hops.isEmpty else { throw ContractArgument.ArgumentError.malformed("empty swap chain") }
        return ContractCall(contract: router, function: chainedFunction, arguments: [
            try ContractArgument.address(user),
            .vec(try hops.map { hop in
                .vec([.vec(try hop.tokens.map { try ContractArgument.address($0) }), .bytes(hop.poolHash), try ContractArgument.address(hop.tokenOut)])
            }),
            try ContractArgument.address(tokenIn),
            try u128(amountIn),
            try u128(minimumOut),
        ])
    }

    /// Les bornes que porte un appel de swap Aquarius. Refus si ce n'est pas un swap de ce router ou s'il est mal formé.
    static func terms(of call: ContractCall, router: String) throws -> SignedTerms {
        let malformed = ContractArgument.ArgumentError.malformed("not an Aquarius swap on \(router.prefix(8))…")
        guard call.contract == router, let user = call.addressArgument(0) else { throw malformed }
        switch call.function {
        case swapFunction:
            guard call.arguments.count == 7, let tokens = ContractArgument.addresses(call.arguments[1]), tokens.count == 2,
                  let tokenIn = call.addressArgument(2), let tokenOut = call.addressArgument(3),
                  Set(tokens) == [tokenIn, tokenOut], tokens == (try? sortedTokens(tokens[0], tokens[1])), call.arguments[4].bytes?.count == 32,
                  let amountIn = int128(call.arguments[5]), let minimumOut = int128(call.arguments[6]) else { throw malformed }
            return SignedTerms(
                action: .swap, contract: router, authorizer: user, assetIn: tokenIn, amountIn: amountIn,
                assetOut: tokenOut, minimumOut: minimumOut, route: [tokenIn, tokenOut], deadline: nil
            )
        case chainedFunction:
            guard call.arguments.count == 5, let chain = call.arguments[1].vec, !chain.isEmpty,
                  let tokenIn = call.addressArgument(2),
                  let amountIn = int128(call.arguments[3]), let minimumOut = int128(call.arguments[4]) else { throw malformed }
            // Chaque maillon prend le jeton du maillon précédent et en rend un autre du même pool.
            var route = [tokenIn]
            for link in chain {
                guard let parts = link.vec, parts.count == 3, let tokens = ContractArgument.addresses(parts[0]), tokens.count == 2,
                      tokens == (try? sortedTokens(tokens[0], tokens[1])), parts[1].bytes?.count == 32,
                      let out = parts[2].address.flatMap({ try? $0.toStrKey() }),
                      let current = route.last, Set(tokens) == [current, out] else { throw malformed }
                route.append(out)
            }
            return SignedTerms(
                action: .swap, contract: router, authorizer: user, assetIn: tokenIn, amountIn: amountIn,
                assetOut: route.last, minimumOut: minimumOut, route: route, deadline: nil
            )
        default:
            throw malformed
        }
    }

    /// Un montant d'unités en `u128` : refusé s'il est négatif.
    static func u128(_ units: Int128) throws -> SCValXDR {
        guard units >= 0 else { throw ContractArgument.ArgumentError.malformed("negative amount \(units)") }
        return ContractArgument.u128(UInt128(units))
    }

    /// Un `u128` relu en unités (`Int128` partout ailleurs dans l'app), `nil` s'il n'en est pas un ou s'il déborde.
    static func int128(_ value: SCValXDR) -> Int128? {
        guard let units = ContractArgument.uint128(value), units <= UInt128(Int128.max) else { return nil }
        return Int128(units)
    }
}
