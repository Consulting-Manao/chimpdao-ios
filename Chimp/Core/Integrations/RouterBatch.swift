import Foundation
import stellarsdk

/// Lot atomique du router ChimpDAO (`router.batch(caller, calls)`, ARCHITECTURE §2.3) : plusieurs appels, une seule
/// transaction, une seule signature de la carte. Portage de `encodeCalls` (`reference/terminal/src/chain/router.ts`).
enum RouterBatch {
    /// Le `Vec<Call>` du router : chaque appel est une map `{ args, contract, method }`, clés triées
    /// (`ChipAuthEncoding.map`, comme `scMap` du terminal).
    static func encode(_ calls: [ContractCall]) throws -> SCValXDR {
        .vec(try calls.map { call in
            ChipAuthEncoding.map([
                ("args", .vec(call.arguments)),
                ("contract", try ContractArgument.address(call.contract)),
                ("method", .symbol(call.function)),
            ])
        })
    }

    /// L'appel racine `batch(caller, legs)` sur `router`.
    static func call(router: String, caller: String, legs: [ContractCall]) throws -> ContractCall {
        ContractCall(contract: router, function: "batch", arguments: [try ContractArgument.address(caller), try encode(legs)])
    }
}
