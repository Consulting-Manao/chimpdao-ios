import Foundation
import stellarsdk

/// Ce que le router Aquarius fait signer. **Hors de `reference/`** : relevé par simulation « recording » sur testnet
/// (2026-10-14, Main account `CCDO6J…DDYB`, router `CBCFTQSP…`), une seule entrée d'autorisation par swap :
///
/// - `swap` : router.`swap(user, …)` → pool.`swap(user, in_idx: u32, out_idx: u32, in_amount, out_min)` →
///   `transfer(user → pool, in_amount)` sur le jeton donné. Les indices sont ceux des jetons triés du pool.
/// - `swap_chained` : router.`swap_chained(user, …)` → `transfer(user → router, in_amount)` sur `token_in`, en un saut
///   comme en deux (le router paie ensuite chaque pool lui-même).
///
/// Le pool et ses jetons ne sont pas tous dans les arguments du pool : la forme les reçoit du devis (`get_pools`).
struct AquariusAuthShape: AuthShape {
    let router: String
    /// Le pool d'un `swap` direct (ignoré pour `swap_chained`).
    let pool: String
    /// Les deux jetons de ce pool, triés.
    let poolTokens: [String]

    func signer(of call: ContractCall) -> String? {
        switch (call.contract, call.function) {
        case (router, AquariusCalls.swapFunction), (router, AquariusCalls.chainedFunction), (pool, AquariusCalls.swapFunction):
            call.addressArgument(0)
        default:
            nil
        }
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard signer(of: call) == from else { return [] }
        switch (call.contract, call.function) {
        case (router, AquariusCalls.swapFunction):
            // Le router appelle le pool avec les indices des jetons triés.
            guard call.arguments.count == 7, let tokenIn = call.addressArgument(2), let tokenOut = call.addressArgument(3),
                  ContractArgument.addresses(call.arguments[1]) == poolTokens,
                  let inIndex = poolTokens.firstIndex(of: tokenIn), let outIndex = poolTokens.firstIndex(of: tokenOut) else {
                throw ContractArgument.ArgumentError.malformed("Aquarius swap doesn't match pool \(pool.prefix(8))…")
            }
            return [ContractCall(contract: pool, function: AquariusCalls.swapFunction, arguments: [
                call.arguments[0], .u32(UInt32(inIndex)), .u32(UInt32(outIndex)), call.arguments[5], call.arguments[6],
            ])]
        case (pool, AquariusCalls.swapFunction):
            guard call.arguments.count == 5, let inIndex = call.arguments[1].u32, poolTokens.indices.contains(Int(inIndex)),
                  let units = AquariusCalls.int128(call.arguments[3]) else {
                throw ContractArgument.ArgumentError.malformed("Aquarius pool swap is malformed")
            }
            return [try TokenShape.transfer(token: poolTokens[Int(inIndex)], from: from, to: pool, units: units)]
        default:
            // swap_chained : une seule prise, vers le router.
            guard call.arguments.count == 5, let tokenIn = call.addressArgument(2), let units = AquariusCalls.int128(call.arguments[3]) else {
                throw ContractArgument.ArgumentError.malformed("Aquarius swap_chained is malformed")
            }
            return [try TokenShape.transfer(token: tokenIn, from: from, to: router, units: units)]
        }
    }
}
