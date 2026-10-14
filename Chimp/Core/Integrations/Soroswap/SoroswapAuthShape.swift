import Foundation
import stellarsdk

/// Ce que le router Soroswap fait signer : portage de `soroswapAuthShape`
/// (`reference/terminal/src/modules/earn/soroswap/auth.ts`).
///
/// Chaque jambe envoie des jetons **à la paire**, pas au router appelé, et l'adresse de la paire n'est dans aucun
/// argument : elle est lue avant (`router_pair_for`) et donnée à la forme. Vérifié par simulation sur testnet
/// (2026-09-02 pour le terminal, 2026-10-14 pour l'app) : `swap_exact_tokens_for_tokens` rend exactement un sous-appel,
/// `transfer(signataire → paire, amount_in)` sur `path[0]`, y compris sur un chemin à plusieurs sauts (la paire est
/// alors celle du premier saut).
///
/// `remove_liquidity` prend le jeton LP, qui **est** la paire. `add_liquidity` prend les deux jambes aux montants
/// « désirés », que l'appelant fige (désiré = minimum) quand une Pocket signe : un arbre déclaré nomme des montants exacts.
struct SoroswapAuthShape: AuthShape {
    let router: String
    /// La paire du premier saut.
    let pair: String

    /// Quel argument nomme l'autorisateur, par fonction : `to`, dans chaque cas.
    static let signerArgument: [String: Int] = [
        "swap_exact_tokens_for_tokens": 3,
        "add_liquidity": 6,
        "remove_liquidity": 5,
    ]

    private func argument(_ call: ContractCall) -> Int? {
        call.contract == router ? Self.signerArgument[call.function] : nil
    }

    func signer(of call: ContractCall) -> String? {
        argument(call).flatMap { call.addressArgument($0) }
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard let index = argument(call), call.addressArgument(index) == from else { return [] }
        switch call.function {
        case "swap_exact_tokens_for_tokens":
            guard call.arguments.count > 2, let token = ContractArgument.addresses(call.arguments[2])?.first else { return [] }
            return [try TokenShape.transfer(token: token, from: from, to: pair, units: try units(call, 0))]
        case "remove_liquidity":
            return [try TokenShape.transfer(token: pair, from: from, to: pair, units: try units(call, 2))]
        default:
            // add_liquidity : les deux jambes, aux montants désirés (figés).
            guard let tokenA = call.addressArgument(0), let tokenB = call.addressArgument(1) else { return [] }
            return [
                try TokenShape.transfer(token: tokenA, from: from, to: pair, units: try units(call, 2)),
                try TokenShape.transfer(token: tokenB, from: from, to: pair, units: try units(call, 3)),
            ]
        }
    }

    private func units(_ call: ContractCall, _ index: Int) throws -> Int128 {
        guard let units = call.i128Argument(index) else {
            throw ContractArgument.ArgumentError.malformed("argument \(index) of \(call.function) is not an i128")
        }
        return units
    }
}
