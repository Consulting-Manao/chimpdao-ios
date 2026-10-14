import Foundation
import stellarsdk

/// Lecture d'un contrat par simulation (`readContract` de `reference/terminal/src/chain/read.ts`) : rien n'est signé ni
/// envoyé. Ce dont un adaptateur a besoin du réseau ; une implémentation scriptée sert aux tests.
protocol ContractReading {
    /// La valeur rendue par `function` ; une simulation sans valeur est une erreur (`readValue`), jamais « rien ».
    func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR
}

/// Lecture par le RPC du réseau. Source des simulations : le payeur de frais avec une séquence quelconque (une
/// simulation ne lit ni ne consomme la séquence), donc aucun appel `getAccount` par lecture.
struct SimulationReader: ContractReading {
    let client: SorobanClient
    let source: String

    func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
        try await client.readValue(
            source: try Account(accountId: source, sequenceNumber: 0), contract: contract, function: function, arguments: arguments
        )
    }
}

/// Pourquoi un swap ne peut pas se faire, dit simplement (D2, « erreurs gérées »).
enum SwapError: Error, Equatable, LocalizedError {
    /// Aucune paire (ou aucun pool) entre ces actifs chez ce protocole.
    case noRoute
    /// Le pool n'a pas assez de liquidité pour ce montant.
    case insufficientLiquidity
    /// Le prix a bougé : le pool rend moins que le minimum signé (avant l'envoi, ou refus du contrat).
    case slippageExceeded
    /// L'échéance du swap est passée avant l'exécution.
    case deadlineExpired

    var errorDescription: String? {
        switch self {
        case .noRoute: "No route between these assets."
        case .insufficientLiquidity: "The pool doesn't have enough liquidity for this amount."
        case .slippageExceeded: "The price moved past the minimum you agreed to."
        case .deadlineExpired: "The swap's deadline passed."
        }
    }
}
