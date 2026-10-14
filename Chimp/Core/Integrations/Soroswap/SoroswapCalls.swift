import Foundation
import stellarsdk

/// Les appels du router Soroswap, construits et relus : l'opération de `runSwap`
/// (`reference/terminal/src/modules/earn/soroswap/soroswap.ts`) et son décodage en bornes signées (`SignedTerms`).
enum SoroswapCalls {
    static let swapFunction = "swap_exact_tokens_for_tokens"
    /// 5 minutes (`SWAP_DEADLINE_SECS`).
    static let deadlineSeconds: UInt64 = 300

    /// `swap_exact_tokens_for_tokens(amount_in, amount_out_min, path, to, deadline)`. `to` est aussi l'autorisateur :
    /// le router prend `amount_in` à `to` et lui paie le résultat.
    static func swap(
        router: String, amountIn: Int128, minimumOut: Int128, path: [String], to: String, deadline: UInt64
    ) throws -> ContractCall {
        ContractCall(contract: router, function: swapFunction, arguments: [
            ContractArgument.i128(amountIn),
            ContractArgument.i128(minimumOut),
            .vec(try path.map { try ContractArgument.address($0) }),
            try ContractArgument.address(to),
            .u64(deadline),
        ])
    }

    /// Les bornes que porte un appel de swap. Refus si ce n'est pas un swap de ce router ou s'il est mal formé.
    static func terms(of call: ContractCall, router: String) throws -> SignedTerms {
        guard call.contract == router, call.function == swapFunction, call.arguments.count == 5,
              let amountIn = call.i128Argument(0), let minimumOut = call.i128Argument(1),
              let path = ContractArgument.addresses(call.arguments[2]), path.count >= 2,
              let to = call.addressArgument(3), let deadline = call.arguments[4].u64 else {
            throw ContractArgument.ArgumentError.malformed("not a Soroswap swap on \(router.prefix(8))…")
        }
        return SignedTerms(
            action: .swap, contract: router, authorizer: to, assetIn: path[0], amountIn: amountIn,
            assetOut: path[path.count - 1], minimumOut: minimumOut, route: path, deadline: deadline
        )
    }
}
