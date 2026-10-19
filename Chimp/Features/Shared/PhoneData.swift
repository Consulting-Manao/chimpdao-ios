import Foundation

/// Ce que l'app garde sur ce téléphone hors des fichiers du compte et de l'historique : les préférences (`UserDefaults` :
/// réglages, historique de Grow, dernier ledger vu par l'horloge, réglages de développement) et l'horloge des ledgers
/// en mémoire. « Erase everything on this phone » efface tout (décision de Barth du 2026-10-19).
enum PhoneData {
    static func eraseAll(defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) {
        if let domain { defaults.removePersistentDomain(forName: domain) }
        LedgerClock.forgetShared()
    }
}
