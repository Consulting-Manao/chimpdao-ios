import Foundation
import stellarsdk

/// Ce qu'un vault DeFindex fait signer à son déposant : portage de `defindexAuthShape`
/// (`reference/terminal/src/modules/earn/defindex/auth.ts`).
///
/// `deposit(amounts_desired, amounts_min, from, invest)` prend `amounts_desired[0]` de l'actif du vault à `from` (vaults
/// à un seul actif : une prise, de ce montant exactement, vérifié par simulation sur testnet le 2026-10-14).
/// `withdraw(shares, min_out, from)` paie et ne prend rien.
struct DeFindexAuthShape: AuthShape {
    /// Vault → SAC de son actif (la liste choisie dans `Config/`, jamais toute l'usine).
    let underlying: [String: String]

    private func known(_ call: ContractCall) -> Bool {
        underlying[call.contract] != nil && (call.function == "deposit" || call.function == "withdraw")
    }

    func signer(of call: ContractCall) -> String? {
        known(call) ? call.addressArgument(2) : nil
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard call.function == "deposit", known(call), call.addressArgument(2) == from,
              let token = underlying[call.contract] else { return [] }
        guard let desired = call.arguments.first?.vec else {
            throw ContractArgument.ArgumentError.malformed("amounts_desired of deposit is not a list")
        }
        var first: Int128 = 0
        if let head = desired.first, let units = ContractArgument.int128(head) { first = units }
        return [try TokenShape.transfer(token: token, from: from, to: call.contract, units: first)]
    }
}
