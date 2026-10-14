import Foundation

/// Un montant en unités on-chain (128 bits, comme un `i128` Soroban) qui peut traverser une fonction `async`.
///
/// **Règle de l'app** : aucun `Int128` ni `UInt128` nu en paramètre d'une fonction ou d'une closure `async` ; un montant
/// qui doit en traverser une passe par `TokenAmount`. Swift 6.3.3 (Xcode 26.6), en Debug (`-Onone`), corrompt la moitié
/// haute d'un `Int128` passé à une fonction `async` après d'autres paramètres, et une structure qui ne contient qu'un
/// `Int128` aussi (alignement 16) ; deux mots de 64 bits passent intacts (DESIGN_NOTES §13, 2026-10-14). La règle est
/// vérifiée par `AsyncAmountRuleTests` (lecture du code source de `Chimp/`, et montant intact à l'exécution).
struct TokenAmount: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByIntegerLiteral {
    private let high: Int64
    private let low: UInt64

    init(_ units: Int128) {
        high = Int64(truncatingIfNeeded: units >> 64)
        low = UInt64(truncatingIfNeeded: units)
    }

    init(integerLiteral value: Int64) {
        self.init(Int128(value))
    }

    /// Le montant, en unités on-chain.
    var units: Int128 { Int128(high) << 64 | Int128(low) }

    static func < (lhs: TokenAmount, rhs: TokenAmount) -> Bool { lhs.units < rhs.units }

    var description: String { String(units) }
}
