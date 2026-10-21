import Foundation
import Observation
import SwiftUI

/// Apparence de l'app (I2 « Look ») : comme l'iPhone (par défaut), ou forcée claire ou sombre.
enum ChimpLook: String, CaseIterable, Identifiable, Sendable {
    /// Suit le réglage de l'iPhone.
    case auto
    /// Thème clair (« Yellow banana »).
    case yellowBanana
    /// Thème sombre (« Jungle night »).
    case jungleNight

    var id: String { rawValue }

    /// Style imposé à la fenêtre de l'app (`.unspecified` : celui de l'iPhone).
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .auto: .unspecified
        case .yellowBanana: .light
        case .jungleNight: .dark
        }
    }
}

/// Réglages de l'app sur ce téléphone (I2). **Aucun secret** et rien de lié à un compte : ils valent pour tous les comptes
/// du téléphone (Face ID, lui, est un réglage **du compte** : `SavedAccount.opensWithFaceID`). Gardés à part du `LocalWallet` (qui ne contient que les comptes, les cartes et le prénom, décision du
/// 2026-09-29) ; « Erase everything on this phone » les efface aussi.
@Observable
final class AppPreferences {
    private let store: PreferencesStore

    /// Apparence : `auto` par défaut.
    var look: ChimpLook {
        didSet { store.set(look.rawValue, for: .look) }
    }

    /// Devise d'affichage du Wallet et des pages de tiroir (I3) : dollar par défaut, comme le terminal (`readDenom`).
    var currency: DisplayCurrency {
        didSet { store.set(currency.rawValue, for: .currency) }
    }

    /// Petits sons (tap réussi, envoi réussi, erreur) : activés par défaut ; le bouton silencieux de l'iPhone les coupe aussi.
    var soundsEnabled: Bool {
        didSet { store.set(soundsEnabled ? nil : "off", for: .sounds) }
    }

    /// Fenêtre « testnet » du premier lancement validée (Chimp Test). Effacée avec le reste : elle revient après
    /// « Erase everything on this phone ».
    var hasAcceptedTestnetNotice: Bool {
        didSet { store.set(hasAcceptedTestnetNotice ? "accepted" : nil, for: .testnetNotice) }
    }

    init(store: PreferencesStore) {
        self.store = store
        look = store.string(for: .look).flatMap(ChimpLook.init(rawValue:)) ?? .auto
        currency = store.string(for: .currency).flatMap(DisplayCurrency.init(rawValue:)) ?? .usd
        soundsEnabled = store.string(for: .sounds) != "off"
        hasAcceptedTestnetNotice = store.string(for: .testnetNotice) == "accepted"
    }

    /// Préférences gardées dans `UserDefaults` (l'app) ; en mémoire pour les tests et le catalogue.
    static func live() -> AppPreferences {
        AppPreferences(store: UserDefaultsPreferencesStore())
    }

    /// « Erase everything on this phone » : retour aux valeurs par défaut.
    func reset() {
        look = .auto
        currency = .usd
        soundsEnabled = true
        hasAcceptedTestnetNotice = false
        // Après les valeurs par défaut (leur `didSet` les écrit) : rien ne reste dans le stockage.
        store.removeAll()
    }
}

/// Clés des préférences.
enum PreferenceKey: String, CaseIterable {
    case look = "chimp.look"
    case currency = "chimp.currency"
    case sounds = "chimp.sounds"
    case testnetNotice = "chimp.testnetNotice"
}

/// Lecture et écriture des préférences. Implémenté par `UserDefaultsPreferencesStore` et `InMemoryPreferencesStore`.
protocol PreferencesStore {
    func string(for key: PreferenceKey) -> String?
    func set(_ value: String?, for key: PreferenceKey)
    func removeAll()
}

struct UserDefaultsPreferencesStore: PreferencesStore {
    var defaults: UserDefaults = .standard

    func string(for key: PreferenceKey) -> String? { defaults.string(forKey: key.rawValue) }

    func set(_ value: String?, for key: PreferenceKey) { defaults.set(value, forKey: key.rawValue) }

    func removeAll() {
        for key in PreferenceKey.allCases { defaults.removeObject(forKey: key.rawValue) }
    }
}

final class InMemoryPreferencesStore: PreferencesStore {
    private(set) var values: [PreferenceKey: String] = [:]

    init(_ values: [PreferenceKey: String] = [:]) {
        self.values = values
    }

    func string(for key: PreferenceKey) -> String? { values[key] }

    func set(_ value: String?, for key: PreferenceKey) { values[key] = value }

    func removeAll() { values = [:] }
}
