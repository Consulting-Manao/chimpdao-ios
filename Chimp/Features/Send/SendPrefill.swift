import Foundation

/// Envoi prérempli : « Pay again » (reçu d'un envoi), « Send back » (reçu d'un paiement reçu) ou code QR scanné (C1).
///
/// Ce ne sont que des valeurs de départ : C1, C2 et C4 restent obligatoires, rien n'est signé sans la vérification
/// (décision de Barth du 2026-10-01 : adresse, actif **et** montant préremplis, C4 toujours).
struct SendPrefill: Hashable {
    enum Origin: Hashable {
        /// Payer de nouveau la même adresse.
        case payAgain
        /// Renvoyer un paiement reçu à son expéditeur : Chimpy prévient qu'un exchange peut ne pas le reconnaître.
        case sendBack
        /// Code QR scanné en C1 (adresse seule ou lien SEP-7).
        case scan
    }

    /// Adresse G, M ou C, telle qu'elle sera vérifiée par `StellarAddressParser`.
    var address: String
    /// Memo ID d'une adresse G (lien SEP-7 avec `memo_type=MEMO_ID`).
    var memoID: UInt64?
    var asset: SendAsset?
    /// Montant exact dans l'actif ; ignoré s'il a plus de décimales que le pavé n'en permet (jamais arrondi).
    var amount: Decimal?
    var origin: Origin
}

extension SendAsset {
    /// L'actif de l'app de ce code (« USDC », « XLM », « CETES »), pour un code **déjà lu par l'app** (relevé par l'adresse
    /// exacte de son contrat) ; `nil` sinon. Pour un envoi, vérifier aussi `isSendable`.
    init?(code: String) {
        guard let asset = SendAsset.allCases.first(where: { $0.code == code }) else { return nil }
        self = asset
    }
}
