import Foundation
import Testing
@testable import ChimpDAO

/// « Face ID to open the app » (I2, session « Réglages », point 1) : verrou à l'ouverture et au retour au premier plan,
/// repli sur le code de l'iPhone (règle `.deviceOwnerAuthentication`), désactivé par défaut.
struct AppLockTests {
    /// Face ID factice : répond ce qu'on lui dit, compte les demandes.
    private final class FakeAuthenticator: DeviceAuthenticator, @unchecked Sendable {
        var lockKind: DeviceLockKind = .faceID
        var results: [DeviceAuthenticationResult] = []
        private(set) var requests = 0

        func kind() -> DeviceLockKind { lockKind }

        func authenticate(reason: String) async -> DeviceAuthenticationResult {
            requests += 1
            return results.isEmpty ? .success : results.removeFirst()
        }
    }

    private func lock(enabled: Bool, _ authenticator: FakeAuthenticator) -> (AppLock, AppPreferences, InMemoryPreferencesStore) {
        let store = InMemoryPreferencesStore(enabled ? [.faceID: "1"] : [:])
        let preferences = AppPreferences(store: store)
        return (AppLock(preferences: preferences, authenticator: authenticator), preferences, store)
    }

    @Test("Désactivé par défaut : jamais verrouillé, jamais de Face ID")
    func disabledByDefault() async {
        let face = FakeAuthenticator()
        let (lock, preferences, _) = lock(enabled: false, face)
        #expect(!preferences.opensWithFaceID && !lock.isLocked)
        await lock.didBecomeActive()
        lock.didEnterBackground()
        #expect(!lock.isLocked && face.requests == 0)
    }

    @Test("Activé : verrouillé au lancement, Face ID proposé au premier plan, ouvert s'il réussit")
    func locksAtLaunch() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = lock(enabled: true, face)
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.requests == 1)
        await lock.didBecomeActive()
        #expect(face.requests == 1, "Déjà ouvert : rien de plus")
    }

    @Test("Retour d'arrière-plan : verrouillé, Face ID redemandé ; un passage « inactif » (NFC, Face ID) ne verrouille pas")
    func relocksAfterBackground() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = lock(enabled: true, face)
        await lock.didBecomeActive()
        // Feuille NFC d'iOS : l'app devient inactive puis active, sans arrière-plan.
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.requests == 1)

        lock.didEnterBackground()
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.requests == 2)
    }

    @Test("Face ID annulé : l'app reste verrouillée, pas de nouvelle fenêtre en boucle ; le bouton « Unlock » redemande")
    func cancelKeepsLockedWithoutLoop() async {
        let face = FakeAuthenticator()
        face.results = [.cancelled, .success]
        let (lock, _, _) = lock(enabled: true, face)
        await lock.didBecomeActive()
        #expect(lock.isLocked && face.requests == 1)
        // La fenêtre Face ID fermée rend l'app active à nouveau : pas de seconde demande automatique.
        await lock.didBecomeActive()
        #expect(face.requests == 1)
        await lock.unlock()
        #expect(!lock.isLocked && face.requests == 2)
    }

    @Test("Échec technique : reste verrouillé, détail gardé pour « Technical details »")
    func failureKeepsDetail() async {
        let face = FakeAuthenticator()
        face.results = [.failed("-1: Biometry lockout")]
        let (lock, _, _) = lock(enabled: true, face)
        await lock.unlock()
        #expect(lock.isLocked && lock.lastFailure == "-1: Biometry lockout")
    }

    @Test("Plus de code sur l'iPhone : l'app s'ouvre et le réglage se coupe")
    func passcodeRemoved() async {
        let face = FakeAuthenticator()
        face.lockKind = .unavailable
        let (lock, preferences, store) = lock(enabled: true, face)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && !preferences.opensWithFaceID && store.values[.faceID] == nil)
        #expect(face.requests == 0)
    }

    @Test("Activer : Face ID doit réussir une fois ; annulé, rien ne change ; sans code, « Set a passcode » d'abord")
    func enable() async {
        let face = FakeAuthenticator()
        face.results = [.cancelled, .success]
        let (lock, preferences, store) = lock(enabled: false, face)
        #expect(await lock.enable() == .cancelled)
        #expect(!preferences.opensWithFaceID)
        #expect(await lock.enable() == .enabled)
        #expect(preferences.opensWithFaceID && store.values[.faceID] == "1")
        #expect(!lock.isLocked, "L'app déjà ouverte n'est pas recouverte")

        lock.disable()
        #expect(!preferences.opensWithFaceID && store.values[.faceID] == nil)

        let noCode = FakeAuthenticator()
        noCode.lockKind = .unavailable
        let (other, _, _) = self.lock(enabled: false, noCode)
        #expect(await other.enable() == .needsPasscode)
        #expect(noCode.requests == 0)
    }

    @Test("« Erase everything » coupe aussi le verrou")
    func eraseResets() throws {
        let store = InMemoryPreferencesStore([.faceID: "1"])
        let preferences = AppPreferences(store: store)
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet, preferences: preferences)
        try session.eraseEverything()
        #expect(!preferences.opensWithFaceID && store.values.isEmpty)
    }

    @Test("Libellés selon l'iPhone : Face ID, Touch ID, Optic ID, code seul")
    func labels() {
        #expect(SettingsView.lockTitle(.faceID) == "Face ID to open the app")
        #expect(SettingsView.lockTitle(.touchID) == "Touch ID to open the app")
        #expect(SettingsView.lockTitle(.opticID) == "Optic ID to open the app")
        #expect(SettingsView.lockTitle(.passcode) == "Passcode to open the app")
    }
}
