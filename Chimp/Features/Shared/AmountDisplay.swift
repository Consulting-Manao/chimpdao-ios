import Foundation

/// Montants en dollars ou en quantités seulement.
///
/// Chimp Test, publiée sur l'App Store sur le testnet (drapeau `CHIMP_TESTNET_STORE`, configuration Beta) : **aucune
/// valeur en dollars**, seulement des quantités (« 50 XLM », « 25 USDC »). Des jetons de test n'ont pas de valeur ; un
/// total en dollars les ferait passer pour de l'argent (décision de Barth du 2026-10-22). Chimp Dev et ChimpDAO gardent
/// les dollars.
enum AmountDisplay {
    static let showsDollars: Bool = {
        #if CHIMP_TESTNET_STORE
        false
        #else
        true
        #endif
    }()

    /// Un wallet vide : « $0.00 », ou « 0 » en quantités seulement.
    static var emptyText: String {
        showsDollars ? Decimal(0).formatted(.currency(code: "USD").presentation(.narrow)) : "0"
    }
}
