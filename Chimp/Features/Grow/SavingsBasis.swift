import Foundation

/// Le prix auquel on a obtenu les CETES d'un tiroir, lu dans l'historique (décision de Barth du 2026-10-15 : « Price +0.62%
/// since you got them » = le prix indicatif d'Etherfuse au moment du swap, gardé sur le téléphone ; sans lui, la valeur
/// seule).
///
/// - Un swap **vers** le stablebond ajoute ce qui est arrivé, au prix d'Etherfuse noté à ce moment-là (`receivedPriceUSD`).
/// - Un swap **depuis** le stablebond (ou un clawback) retire des jetons sans changer le prix moyen de ceux qui restent.
/// - Tout se vide → une nouvelle position commence (son prix repart de zéro).
/// - `nil` quand l'historique ne permet pas de le dire honnêtement : un jeton reçu sans prix noté (swap relu sur la chaîne,
///   prix indisponible, autre téléphone, transfert entrant), ou un historique qui ne retrouve pas le solde actuel exact.
struct SavingsBasis: Equatable {
    /// Prix moyen d'un jeton détenu, en dollars, au moment où on l'a obtenu.
    let unitPriceUSD: Decimal
    /// Le premier swap de la position en cours.
    let since: Date

    static func from(records: [ActivityRecord], drawer: String, code: String, balance: Decimal) -> SavingsBasis? {
        guard balance > 0 else { return nil }
        var held: Decimal = 0
        var cost: Decimal = 0
        var known = true
        var since: Date?
        for record in records.sorted(by: { $0.at < $1.at }) {
            if let (amount, price) = acquisition(record, drawer: drawer, code: code) {
                if held <= 0 { since = record.at }
                guard let amount, amount > 0 else { known = false; continue }
                held += amount
                if let price { cost += amount * price } else { known = false }
            } else if let out = disposal(record, drawer: drawer, code: code), held > 0 {
                let taken = min(out, held)
                cost -= cost * taken / held
                held -= taken
                if held <= 0 {
                    held = 0
                    cost = 0
                    known = true
                    since = nil
                }
            }
        }
        // L'historique doit retrouver exactement le solde lu sur la chaîne : sinon, des jetons ont un prix inconnu.
        guard known, held == balance, held > 0, cost > 0, let since else { return nil }
        return SavingsBasis(unitPriceUSD: cost / held, since: since)
    }

    /// Jetons arrivés dans ce tiroir (quantité, prix noté) : un swap vers le stablebond, ou un transfert entrant (sans prix).
    private static func acquisition(_ record: ActivityRecord, drawer: String, code: String) -> (Decimal?, Decimal?)? {
        switch record.event {
        case .swap where record.from == drawer && record.receivedAssetCode == code:
            return (record.receivedAmount, record.receivedPriceUSD)
        case .transfer where record.to == drawer && record.from != drawer && record.assetCode == code:
            return (record.amount, nil)
        default:
            return nil
        }
    }

    /// Jetons partis de ce tiroir : un swap depuis le stablebond, un transfert sortant, ou un clawback.
    private static func disposal(_ record: ActivityRecord, drawer: String, code: String) -> Decimal? {
        switch record.event {
        case .swap where record.from == drawer && record.assetCode == code:
            return record.amount
        case .transfer where record.from == drawer && record.to != drawer && record.assetCode == code:
            return record.amount
        case .clawback where record.from == drawer && record.assetCode == code:
            return record.amount
        default:
            return nil
        }
    }

    /// Évolution du prix depuis l'obtention, en fraction (0,0062 = +0,62 %).
    func priceChange(now price: Decimal) -> Decimal {
        (price - unitPriceUSD) / unitPriceUSD
    }
}
