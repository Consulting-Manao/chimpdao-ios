import Foundation
import stellarsdk

/// Un appel de contrat : `Call` de `reference/terminal/src/chain/call.ts` (contrat, fonction, arguments).
/// Vocabulaire commun des intégrations : appel simple, jambe d'un lot du router (`router.batch`), nœud d'un arbre
/// d'autorisation déclaré.
struct ContractCall {
    let contract: String
    let function: String
    let arguments: [SCValXDR]

    /// L'appel tel qu'il figure dans une entrée d'autorisation (`contractFn` de `auth-tree.ts`), avec ses sous-appels.
    func invocation(subInvocations: [SorobanAuthorizedInvocationXDR] = []) throws -> SorobanAuthorizedInvocationXDR {
        try SorobanAuth.contractInvocation(
            contract: contract, function: function, arguments: arguments, subInvocations: subInvocations
        )
    }

    /// L'adresse de l'argument `index` (G, M ou C), ou `nil` si ce n'en est pas une (`argAddress` de `auth-tree.ts`).
    func addressArgument(_ index: Int) -> String? {
        guard arguments.indices.contains(index), let address = arguments[index].address else { return nil }
        return try? address.toStrKey()
    }

    /// Le montant `i128` de l'argument `index`, ou `nil` si ce n'en est pas un.
    func i128Argument(_ index: Int) -> Int128? {
        guard arguments.indices.contains(index) else { return nil }
        return ContractArgument.int128(arguments[index])
    }
}

extension ContractCall: Equatable {
    /// Deux appels sont égaux s'ils ont le même contrat, la même fonction et **les mêmes octets** d'arguments.
    static func == (lhs: ContractCall, rhs: ContractCall) -> Bool {
        guard lhs.contract == rhs.contract, lhs.function == rhs.function, lhs.arguments.count == rhs.arguments.count else {
            return false
        }
        return (try? lhs.arguments.map { try XDREncoder.encode($0) } == rhs.arguments.map { try XDREncoder.encode($0) }) ?? false
    }
}

/// Encodage et lecture des arguments des contrats des intégrations (`Address.fromString(…).toScVal()`,
/// `nativeToScVal(n, { type: "i128" })` du terminal). Les montants Soroban sont des entiers 128 bits.
enum ContractArgument {
    enum ArgumentError: Error, Equatable, LocalizedError {
        /// L'argument attendu n'a pas le bon type (adresse, montant…) : l'appel est mal formé, on ne signe rien.
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let detail): "Malformed contract call: \(detail)"
            }
        }
    }

    /// Adresse G, M ou C (`SACClient.address`).
    static func address(_ strkey: String) throws -> SCValXDR {
        .address(try SACClient.address(strkey))
    }

    static func i128(_ value: Int128) -> SCValXDR {
        .i128(Int128PartsXDR(hi: Int64(truncatingIfNeeded: value >> 64), lo: UInt64(truncatingIfNeeded: value)))
    }

    static func u128(_ value: UInt128) -> SCValXDR {
        .u128(UInt128PartsXDR(hi: UInt64(truncatingIfNeeded: value >> 64), lo: UInt64(truncatingIfNeeded: value)))
    }

    /// `i128` → entier, `nil` si la valeur n'est pas un `i128`.
    static func int128(_ value: SCValXDR) -> Int128? {
        guard let parts = value.i128 else { return nil }
        return Int128(parts.hi) << 64 | Int128(parts.lo)
    }

    /// `u128` → entier, `nil` si la valeur n'est pas un `u128`.
    static func uint128(_ value: SCValXDR) -> UInt128? {
        guard let parts = value.u128 else { return nil }
        return UInt128(parts.hi) << 64 | UInt128(parts.lo)
    }

    /// Une liste d'adresses (le `path` d'un swap), `nil` si un élément n'est pas une adresse.
    static func addresses(_ value: SCValXDR) -> [String]? {
        guard let items = value.vec else { return nil }
        var out: [String] = []
        for item in items {
            guard let address = item.address, let strkey = try? address.toStrKey() else { return nil }
            out.append(strkey)
        }
        return out
    }
}
