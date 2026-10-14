import Foundation

/// Slippage et impact de prix des intégrations (principe 5 de la tranche 2, seuils validés par Barth le 2026-10-14) :
/// 0,5 % par défaut, 3 % au maximum, avertissement fort au-delà de 5 % d'impact de prix.
///
/// Règle ajoutée le 2026-10-14 : **jamais de valeur en dollars tirée d'un pool**. Tout ce qui sort d'ici est en quantités
/// d'un actif (unités on-chain), jamais en monnaie : les prix des pools du testnet n'ont aucun sens.
enum Slippage {
    /// 0,5 % (`SLIPPAGE_BPS` de `soroswap/config.ts`).
    static let defaultBasisPoints = 50
    /// 3 % : au-delà, l'app refuse de signer.
    static let maximumBasisPoints = 300
    /// 5 % d'impact de prix : avertissement fort avant la vérification.
    static let priceImpactWarningBasisPoints = 500

    enum SlippageError: Error, Equatable, LocalizedError {
        /// Tolérance hors de 0 … 3 %.
        case outOfRange(basisPoints: Int)

        var errorDescription: String? {
            switch self {
            case .outOfRange(let basisPoints): "Slippage of \(basisPoints) basis points is outside 0–\(Slippage.maximumBasisPoints)."
            }
        }
    }

    /// Une tolérance choisie, refusée si elle sort de 0 … 3 %.
    static func checked(_ basisPoints: Int) throws -> Int {
        guard (0...maximumBasisPoints).contains(basisPoints) else { throw SlippageError.outOfRange(basisPoints: basisPoints) }
        return basisPoints
    }

    /// `withSlippage` (`lib/amount.ts`) : le minimum accepté pour `units` à `basisPoints` de tolérance, arrondi vers le bas.
    /// 0 pour un montant nul ou négatif.
    static func minimum(of units: Int128, basisPoints: Int) -> Int128 {
        guard units > 0 else { return 0 }
        return units * Int128(10_000 - basisPoints) / 10_000
    }

    /// Écart entre ce que le pool rend et ce qu'il rendrait au prix « spot » de ses réserves, en points de base
    /// (frais du pool compris). `nil` si les réserves ou les montants ne permettent pas de le calculer.
    static func priceImpactBasisPoints(amountIn: Int128, amountOut: Int128, reserveIn: Int128, reserveOut: Int128) -> Int? {
        guard amountIn > 0, amountOut >= 0, reserveIn > 0, reserveOut > 0 else { return nil }
        let (spot, overflow) = amountIn.multipliedReportingOverflow(by: reserveOut)
        guard !overflow else { return nil }
        let spotOut = spot / reserveIn
        guard spotOut > 0 else { return nil }
        guard amountOut < spotOut else { return 0 }
        return Int((spotOut - amountOut) * 10_000 / spotOut)
    }

    /// Au-delà de 5 % : avertissement fort.
    static func needsPriceImpactWarning(_ basisPoints: Int) -> Bool {
        basisPoints > priceImpactWarningBasisPoints
    }
}
