import Foundation
import SwiftUI
import Testing
@testable import ChimpDAO

/// « Face ID to open the app » (I2) : un verrou **par compte** (réglage enregistré avec le compte, désactivé par défaut),
/// aucun verrou sans compte ouvert, Face ID en arrivant sur un compte qui l'a activé, toujours « Use iPhone passcode » en
/// plus de Face ID, jamais sur un simple passage « inactif » (feuille NFC).
struct AppLockTests {
    /// Face ID factice : répond ce qu'on lui dit, compte les demandes (Face ID et code séparément).
    private final class FakeAuthenticator: DeviceAuthenticator, @unchecked Sendable {
        var lockKind: DeviceLockKind = .faceID
        var results: [DeviceAuthenticationResult] = []
        private(set) var faceIDRequests = 0
        private(set) var passcodeRequests = 0

        func kind() -> DeviceLockKind { lockKind }

        func authenticate(reason: String) async -> DeviceAuthenticationResult {
            faceIDRequests += 1
            return results.isEmpty ? .success : results.removeFirst()
        }

        func authenticateWithPasscode(reason: String) async -> DeviceAuthenticationResult {
            passcodeRequests += 1
            return results.isEmpty ? .success : results.removeFirst()
        }
    }

    private let leo = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let shop = "CCDO6JSHOPACCOUNTXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXDDYB"

    /// Léo affiché (Face ID selon `leoLocked`), Shop ouvert à côté (Face ID selon `shopLocked`).
    private func wallet(leoLocked: Bool, shopLocked: Bool = false, withShop: Bool = false) -> LocalWallet {
        LocalWallet(
            firstName: "Léo", tourSeen: true,
            account: SavedAccount(address: leo, cards: [], opensWithFaceID: leoLocked ? true : nil),
            otherAccounts: withShop ? [SavedAccount(address: shop, cards: [], firstName: "Shop", opensWithFaceID: shopLocked ? true : nil)] : nil
        )
    }

    private func make(_ wallet: LocalWallet, _ face: FakeAuthenticator) -> (AppLock, AppSession, InMemoryLocalWalletStore) {
        let store = InMemoryLocalWalletStore(wallet)
        let session = AppSession(store: store, network: .testnet)
        return (AppLock(session: session, authenticator: face), session, store)
    }

    // MARK: Par compte

    @Test("Désactivé par défaut : jamais verrouillé, jamais de Face ID")
    func disabledByDefault() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = make(wallet(leoLocked: false), face)
        #expect(!lock.isEnabled && !lock.isLocked)
        await lock.didBecomeActive()
        lock.didEnterBackground()
        #expect(!lock.isLocked && face.faceIDRequests == 0)
    }

    @Test("Aucun compte ouvert (A1, onboarding) : jamais de verrou")
    func noAccountNoLock() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = make(LocalWallet(), face)
        #expect(!lock.isEnabled && !lock.isLocked)
        lock.didEnterBackground()
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 0)
        #expect(await lock.enable() != .enabled, "Rien à protéger sans compte")
    }

    @Test("Le réglage est enregistré avec le compte, pas sur le téléphone")
    func settingBelongsToAccount() async throws {
        let face = FakeAuthenticator()
        let (lock, session, store) = make(wallet(leoLocked: false, withShop: true), face)
        #expect(await lock.enable() == .enabled)
        #expect(store.wallet.account?.opensWithFaceID == true)
        #expect(store.wallet.otherAccount(shop)?.opensWithFaceID == nil, "Shop n'est pas concerné")
        #expect(session.preferences.look == .auto, "Rien dans les réglages du téléphone")
        lock.disable()
        #expect(store.wallet.account?.opensWithFaceID == nil)
    }

    @Test("Switch account vers un compte avec Face ID : verrouillé et Face ID demandé tout de suite")
    func switchToLockedAccount() async throws {
        let face = FakeAuthenticator()
        face.results = [.cancelled]
        let (lock, session, _) = make(wallet(leoLocked: false, shopLocked: true, withShop: true), face)
        #expect(!lock.isLocked)
        try session.switchAccount(to: shop)
        await lock.accountDidChange()
        #expect(lock.isLocked && face.faceIDRequests == 1)
        await lock.unlock()
        #expect(!lock.isLocked)
    }

    @Test("Switch account vers un compte sans Face ID : le verrou du compte quitté ne suit pas")
    func switchToUnlockedAccount() async throws {
        let face = FakeAuthenticator()
        let (lock, session, store) = make(wallet(leoLocked: true, withShop: true), face)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 1)
        try session.switchAccount(to: shop)
        await lock.accountDidChange()
        #expect(!lock.isEnabled && !lock.isLocked && face.faceIDRequests == 1)
        lock.didEnterBackground()
        #expect(!lock.isLocked)
        #expect(store.wallet.otherAccount(leo)?.opensWithFaceID == true, "Léo garde son réglage")
    }

    @Test("Déconnexion : le réglage part avec le compte ; plus de compte, plus de verrou ; il revient à la reconnexion")
    func disconnectTakesSetting() async throws {
        let face = FakeAuthenticator()
        let (lock, session, store) = make(wallet(leoLocked: true), face)
        await lock.didBecomeActive()
        try session.disconnect()
        await lock.accountDidChange()
        #expect(!lock.isEnabled && !lock.isLocked)
        #expect(store.wallet.disconnectedAccount(leo)?.opensWithFaceID == true)
        lock.didEnterBackground()
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 1, "A1 n'est jamais verrouillé")

        let card = SavedCard(publicKey: MockChipReader.secp256k1Key.hex, chip: "infineon2Go", tokenID: 7, pocket: nil, name: "Banana", color: "banana")
        try session.signIn(account: leo, card: card)
        #expect(store.wallet.account?.opensWithFaceID == true)
        await lock.accountDidChange()
        #expect(face.faceIDRequests == 2, "En arrivant sur le compte, Face ID est demandé")
    }

    @Test("Déconnexion d'un compte sans Face ID vers un compte qui l'a : Face ID demandé")
    func disconnectToLockedAccount() async throws {
        let face = FakeAuthenticator()
        face.results = [.cancelled]
        let (lock, session, _) = make(wallet(leoLocked: false, shopLocked: true, withShop: true), face)
        try session.disconnect()
        await lock.accountDidChange()
        #expect(lock.isLocked && face.faceIDRequests == 1)
    }

    @Test("« Erase everything » : plus de compte, plus de verrou")
    func eraseRemovesLock() async throws {
        let face = FakeAuthenticator()
        let (lock, session, _) = make(wallet(leoLocked: true), face)
        #expect(lock.isLocked)
        try session.eraseEverything()
        await lock.accountDidChange()
        #expect(!lock.isLocked && !lock.isEnabled)
    }

    // MARK: Cycle de vie

    @Test("Activé : verrouillé au lancement, Face ID proposé au premier plan, ouvert s'il réussit")
    func locksAtLaunch() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 1)
        await lock.didBecomeActive()
        #expect(face.faceIDRequests == 1, "Déjà ouvert : rien de plus")
    }

    @Test("Retour d'arrière-plan : reverrouillé ; un passage « inactif » (feuille NFC, Face ID) ne verrouille jamais")
    func relocksAfterBackgroundOnly() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        await lock.didBecomeActive()
        // Feuille NFC d'iOS pendant une signature : l'app devient inactive puis active, sans arrière-plan.
        await lock.didBecomeActive()
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 1)
        // Le compte n'a pas changé : l'événement de compte ne verrouille pas non plus.
        await lock.accountDidChange()
        #expect(!lock.isLocked)

        lock.didEnterBackground()
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && face.faceIDRequests == 2)
    }

    @Test("Face ID annulé : reste verrouillé, pas de nouvelle fenêtre en boucle")
    func cancelKeepsLockedWithoutLoop() async {
        let face = FakeAuthenticator()
        face.results = [.cancelled]
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        await lock.didBecomeActive()
        await lock.didBecomeActive()
        #expect(lock.isLocked && face.faceIDRequests == 1)
    }

    // MARK: Code de l'iPhone

    @Test("« Use iPhone passcode » : le code directement, sans Face ID, et sans attendre un échec")
    func passcodeDirectly() async {
        let face = FakeAuthenticator()
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        await lock.unlockWithPasscode()
        #expect(!lock.isLocked)
        #expect(face.passcodeRequests == 1 && face.faceIDRequests == 0)
    }

    @Test("Code annulé : reste verrouillé ; Face ID reste possible ensuite")
    func passcodeCancelled() async {
        let face = FakeAuthenticator()
        face.results = [.cancelled, .success]
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        await lock.unlockWithPasscode()
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(!lock.isLocked && face.faceIDRequests == 1 && face.passcodeRequests == 1)
    }

    @Test("Échec technique : reste verrouillé, détail gardé pour « Technical details »")
    func failureKeepsDetail() async {
        let face = FakeAuthenticator()
        face.results = [.failed("-8: Biometry lockout")]
        let (lock, _, _) = make(wallet(leoLocked: true), face)
        await lock.unlock()
        #expect(lock.isLocked && lock.lastFailure == "-8: Biometry lockout")
    }

    @Test("Plus de code sur l'iPhone : le compte s'ouvre et son réglage se coupe")
    func passcodeRemoved() async {
        let face = FakeAuthenticator()
        face.lockKind = .unavailable
        let (lock, _, store) = make(wallet(leoLocked: true), face)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && store.wallet.account?.opensWithFaceID == nil)
        #expect(face.faceIDRequests == 0 && face.passcodeRequests == 0)
    }

    // MARK: Réglage

    @Test("Activer : Face ID doit réussir une fois ; annulé, rien ne change ; sans code, « Set a passcode » d'abord")
    func enable() async {
        let face = FakeAuthenticator()
        face.results = [.cancelled, .success]
        let (lock, _, store) = make(wallet(leoLocked: false), face)
        #expect(await lock.enable() == .cancelled)
        #expect(store.wallet.account?.opensWithFaceID == nil)
        #expect(await lock.enable() == .enabled)
        #expect(store.wallet.account?.opensWithFaceID == true)
        #expect(!lock.isLocked, "L'app déjà ouverte n'est pas recouverte")

        let noCode = FakeAuthenticator()
        noCode.lockKind = .unavailable
        let (other, _, _) = make(wallet(leoLocked: false), noCode)
        #expect(await other.enable() == .needsPasscode)
        #expect(noCode.faceIDRequests == 0)
    }

    @Test("Écran de verrouillage : bouton biométrique selon l'iPhone, code seul sans biométrie")
    func lockScreenButtons() {
        #expect(AppLockView.biometryTitle(.faceID) == "Unlock with Face ID")
        #expect(AppLockView.biometryTitle(.touchID) == "Unlock with Touch ID")
        #expect(AppLockView.biometryTitle(.passcode) == nil)
        #expect(AppLockView.biometryTitle(.unavailable) == nil)
    }

    @Test("Libellés des réglages selon l'iPhone : Face ID, Touch ID, Optic ID, code seul")
    func labels() {
        #expect(SettingsView.lockTitle(.faceID) == "Face ID to open the app")
        #expect(SettingsView.lockTitle(.touchID) == "Touch ID to open the app")
        #expect(SettingsView.lockTitle(.opticID) == "Optic ID to open the app")
        #expect(SettingsView.lockTitle(.passcode) == "Passcode to open the app")
    }

    @Test("Un fichier écrit avant le réglage par compte reste lisible (désactivé)")
    func oldFileReadable() throws {
        let json = #"{"version":1,"tourSeen":true,"cardHints":[],"account":{"address":"\#(leo)","cards":[]}}"#
        let wallet = try FileLocalWalletStore.decoder.decode(LocalWallet.self, from: Data(json.utf8))
        #expect(wallet.account?.opensWithFaceID == nil)
    }
}
