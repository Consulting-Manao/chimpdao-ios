import Foundation
import Testing
import UIKit
@testable import ChimpDAO

/// Réglages du téléphone (I2) : apparence, puis devise et Face ID. Gardés à part du `LocalWallet`.
struct PreferencesTests {
    @Test("Look : « Auto » par défaut, qui suit l'iPhone ; Yellow banana clair, Jungle night sombre")
    func lookDefaultsAndStyles() {
        let preferences = AppPreferences(store: InMemoryPreferencesStore())
        #expect(preferences.look == .auto)
        #expect(ChimpLook.auto.interfaceStyle == .unspecified)
        #expect(ChimpLook.yellowBanana.interfaceStyle == .light)
        #expect(ChimpLook.jungleNight.interfaceStyle == .dark)
    }

    @Test("Look : le choix est enregistré et relu au lancement suivant")
    func lookIsPersisted() {
        let store = InMemoryPreferencesStore()
        AppPreferences(store: store).look = .jungleNight
        #expect(store.values[.look] == "jungleNight")
        #expect(AppPreferences(store: store).look == .jungleNight)
    }

    @Test("Look : une valeur inconnue dans le stockage redonne « Auto »")
    func unknownLookFallsBack() {
        let store = InMemoryPreferencesStore([.look: "neon"])
        #expect(AppPreferences(store: store).look == .auto)
    }

    @Test("UserDefaults : écriture, relecture et effacement de toutes les clés")
    func userDefaultsStore() throws {
        let suite = "PreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.set("yellowBanana", for: .look)
        #expect(AppPreferences(store: store).look == .yellowBanana)
        store.removeAll()
        #expect(store.string(for: .look) == nil)
    }

    @Test("« Erase everything on this phone » remet les réglages par défaut")
    func eraseResetsPreferences() throws {
        let store = InMemoryPreferencesStore()
        let preferences = AppPreferences(store: store)
        preferences.look = .jungleNight
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet, preferences: preferences)
        try session.eraseEverything()
        #expect(preferences.look == .auto)
        #expect(store.values.isEmpty)
    }

    @Test("Réglages : changer « Look » depuis I2 change la préférence du téléphone")
    func settingsLook() {
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let model = SettingsModel(session: session, walletCards: [])
        model.look = .yellowBanana
        #expect(session.preferences.look == .yellowBanana)
        #expect(SettingsView.lookSegments.map(\.value) == [.auto, .yellowBanana, .jungleNight])
    }
}
