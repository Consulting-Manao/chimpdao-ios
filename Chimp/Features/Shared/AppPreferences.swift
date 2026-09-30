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
/// du téléphone. Gardés à part du `LocalWallet` (qui ne contient que les comptes, les cartes et le prénom, décision du
/// 2026-09-29) ; « Erase everything on this phone » les efface aussi.
@Observable
final class AppPreferences {
    private let store: PreferencesStore

    /// Apparence : `auto` par défaut.
    var look: ChimpLook {
        didSet { store.set(look.rawValue, for: .look) }
    }

    init(store: PreferencesStore) {
        self.store = store
        look = store.string(for: .look).flatMap(ChimpLook.init(rawValue:)) ?? .auto
    }

    /// Préférences gardées dans `UserDefaults` (l'app) ; en mémoire pour les tests et le catalogue.
    static func live() -> AppPreferences {
        AppPreferences(store: UserDefaultsPreferencesStore())
    }

    /// « Erase everything on this phone » : retour aux valeurs par défaut.
    func reset() {
        look = .auto
        // Après les valeurs par défaut (leur `didSet` les écrit) : rien ne reste dans le stockage.
        store.removeAll()
    }
}

/// Clés des préférences.
enum PreferenceKey: String, CaseIterable {
    case look = "chimp.look"
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
