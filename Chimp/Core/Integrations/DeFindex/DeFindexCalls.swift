import Foundation
import stellarsdk

/// Les appels d'un vault DeFindex, construits et relus : `depositOp` et `withdrawOp`
/// (`reference/terminal/src/modules/earn/defindex/defindex.ts`) et leur décodage en bornes signées (`SignedTerms`).
enum DeFindexCalls {
    /// `deposit(amounts_desired, amounts_min, from, invest)` : vault à un seul actif, donc minimum = désiré (aucun ratio
    /// ne peut dériver), et `invest: true` (« idle undeposited funds earn nothing »).
    static func deposit(vault: String, from: String, units: Int128) throws -> ContractCall {
        ContractCall(contract: vault, function: "deposit", arguments: [
            .vec([ContractArgument.i128(units)]),
            .vec([ContractArgument.i128(units)]),
            try ContractArgument.address(from),
            .bool(true),
        ])
    }

    /// `withdraw(withdraw_shares, min_amounts_out, from)` : retrait par parts, minimum en actif du vault.
    static func withdraw(vault: String, from: String, shares: Int128, minimumOut: Int128) throws -> ContractCall {
        ContractCall(contract: vault, function: "withdraw", arguments: [
            ContractArgument.i128(shares),
            .vec([ContractArgument.i128(minimumOut)]),
            try ContractArgument.address(from),
        ])
    }

    /// Les bornes que porte un appel de vault. `underlying` : le SAC de l'actif du vault (lu dans `Config/`).
    /// Dépôt : l'actif part, les parts arrivent (sans minimum). Retrait : les parts partent, l'actif arrive au minimum signé.
    static func terms(of call: ContractCall, underlying: String) throws -> SignedTerms {
        let malformed = ContractArgument.ArgumentError.malformed("not a DeFindex \(call.function) on \(call.contract.prefix(8))…")
        switch call.function {
        case "deposit":
            guard call.arguments.count == 4, let desired = call.arguments[0].vec, let minimum = call.arguments[1].vec,
                  desired.count == 1, minimum.count == 1,
                  let units = ContractArgument.int128(desired[0]), ContractArgument.int128(minimum[0]) == units,
                  let from = call.addressArgument(2), call.arguments[3].bool == true else { throw malformed }
            return SignedTerms(
                action: .deposit, contract: call.contract, authorizer: from, assetIn: underlying, amountIn: units,
                assetOut: call.contract, minimumOut: nil, route: [], deadline: nil
            )
        case "withdraw":
            guard call.arguments.count == 3, let shares = call.i128Argument(0), let minimum = call.arguments[1].vec,
                  minimum.count == 1, let minimumOut = ContractArgument.int128(minimum[0]),
                  let from = call.addressArgument(2) else { throw malformed }
            return SignedTerms(
                action: .withdraw, contract: call.contract, authorizer: from, assetIn: call.contract, amountIn: shares,
                assetOut: underlying, minimumOut: minimumOut, route: [], deadline: nil
            )
        default:
            throw malformed
        }
    }
}
