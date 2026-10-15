import Foundation

/// Ce qu'une position a coûté, lu dans l'historique (décision de Barth du 2026-10-15 : aucun taux promis, seulement
/// l'évolution réelle de la valeur depuis le dépôt, avec sa date). Le terminal n'affiche aucun « gagné » faute de base ;
/// l'app la tire de l'Activity (dépôts et retraits de ce tiroir dans ce vault).
///
/// - Un dépôt ajoute ce qui est entré ; la date est celle du premier dépôt de la position en cours (après un retrait
///   total, une nouvelle position commence).
/// - Un retrait dont on connaît les parts réduit la base **au prorata des parts rendues** (rendre la moitié des parts
///   retire la moitié de ce qui avait été mis, pas ce qui est revenu, sinon le gain disparaîtrait) ; sans les parts, de
///   ce qui est revenu.
/// - `nil` quand l'historique ne permet pas de le dire (pas de dépôt connu) : l'écran montre alors la valeur seule.
struct VaultBasis: Equatable {
    /// Ce qui reste « mis » dans la position, dans l'actif du vault.
    let putIn: Decimal
    /// Le premier dépôt de la position en cours.
    let since: Date

    static func from(records: [ActivityRecord], drawer: String, vault: String) -> VaultBasis? {
        let mine = records
            .filter { ($0.event == .vaultDeposit && $0.from == drawer && $0.to == vault) || ($0.event == .vaultWithdraw && $0.from == vault && $0.to == drawer) }
            .sorted { $0.at < $1.at }
        var putIn: Decimal = 0
        var since: Date?
        /// Parts tenues, tant que chaque ligne les connaît ; `nil` dès qu'une ligne ne les a pas.
        var shares: Decimal? = 0
        for record in mine {
            switch record.event {
            case .vaultDeposit:
                guard let amount = record.amount, amount > 0 else { continue }
                if putIn <= 0 { since = record.at }
                putIn += amount
                shares = shares.flatMap { held in record.shares.map { held + $0 } }
            default:
                if let given = record.shares, let held = shares, held > 0 {
                    putIn -= putIn * min(given, held) / held
                    shares = held - min(given, held)
                } else {
                    putIn -= record.amount ?? 0
                    shares = nil
                }
                if putIn <= 0 || shares == 0 {
                    putIn = 0
                    since = nil
                    shares = 0
                }
            }
        }
        guard putIn > 0, let since else { return nil }
        return VaultBasis(putIn: putIn, since: since)
    }

    /// Ce que la position a fait depuis : valeur actuelle moins ce qui y a été mis (peut être négatif).
    func change(value: Decimal) -> Decimal {
        value - putIn
    }
}
