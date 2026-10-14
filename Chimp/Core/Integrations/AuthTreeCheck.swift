import Foundation
import stellarsdk

/// Comparaison d'un arbre d'autorisation reçu (rendu par la simulation) avec l'arbre attendu (déclaré par l'adaptateur),
/// nœud par nœud. Principe 3 de la tranche 2 : « ce qui est signé = ce qui est affiché ». **Absent du terminal**, qui
/// signe l'arbre simulé du Main account sans le comparer (DESIGN_NOTES §13, 2026-10-14).
///
/// La première différence trouvée est nommée (contrat, fonction, argument, nombre de sous-appels) pour que l'erreur dise
/// ce qui a changé ; la comparaison finale reste celle des octets XDR, sans exception.
enum AuthTreeCheck {
    enum Mismatch: Error, Equatable, CustomStringConvertible {
        /// Le nœud n'est pas un appel de fonction de contrat (création de contrat…).
        case notContractCall(path: String)
        case contract(path: String, expected: String, got: String)
        case function(path: String, expected: String, got: String)
        case argumentCount(path: String, expected: Int, got: Int)
        /// L'argument `index` diffère (montant, actif, destination, route, minimum…).
        case argument(path: String, index: Int)
        case subInvocationCount(path: String, expected: Int, got: Int)
        /// Mêmes champs lus, octets différents : ne devrait jamais arriver, refusé quand même.
        case bytes(path: String)

        var description: String {
            switch self {
            case .notContractCall(let path): "\(path) is not a contract call"
            case .contract(let path, let expected, let got): "\(path) calls \(got) instead of \(expected)"
            case .function(let path, let expected, let got): "\(path) calls \(got) instead of \(expected)"
            case .argumentCount(let path, let expected, let got): "\(path) has \(got) arguments instead of \(expected)"
            case .argument(let path, let index): "argument \(index) of \(path) differs"
            case .subInvocationCount(let path, let expected, let got): "\(path) authorizes \(got) sub-calls instead of \(expected)"
            case .bytes(let path): "\(path) differs"
            }
        }
    }

    /// La première différence entre `got` et `expected`, ou `nil` s'ils sont identiques octet pour octet.
    /// `path` nomme le nœud : `root`, puis `root.0`, `root.0.1`… (index des sous-appels).
    static func mismatch(
        _ got: SorobanAuthorizedInvocationXDR,
        expected: SorobanAuthorizedInvocationXDR,
        path: String = "root"
    ) -> Mismatch? {
        guard case .contractFn(let gotCall) = got.function, case .contractFn(let expectedCall) = expected.function else {
            return .notContractCall(path: path)
        }
        let gotContract = (try? gotCall.contractAddress.toStrKey()) ?? "?"
        let expectedContract = (try? expectedCall.contractAddress.toStrKey()) ?? "?"
        guard gotContract == expectedContract else { return .contract(path: path, expected: expectedContract, got: gotContract) }
        guard gotCall.functionName == expectedCall.functionName else {
            return .function(path: path, expected: expectedCall.functionName, got: gotCall.functionName)
        }
        guard gotCall.args.count == expectedCall.args.count else {
            return .argumentCount(path: path, expected: expectedCall.args.count, got: gotCall.args.count)
        }
        for index in gotCall.args.indices where !sameBytes(gotCall.args[index], expectedCall.args[index]) {
            return .argument(path: path, index: index)
        }
        guard got.subInvocations.count == expected.subInvocations.count else {
            return .subInvocationCount(path: path, expected: expected.subInvocations.count, got: got.subInvocations.count)
        }
        for index in got.subInvocations.indices {
            if let mismatch = mismatch(got.subInvocations[index], expected: expected.subInvocations[index], path: "\(path).\(index)") {
                return mismatch
            }
        }
        return sameBytes(got, expected) ? nil : .bytes(path: path)
    }

    private static func sameBytes<T: XDREncodable>(_ lhs: T, _ rhs: T) -> Bool {
        guard let left = try? XDREncoder.encode(lhs), let right = try? XDREncoder.encode(rhs) else { return false }
        return left == right
    }
}
