import Foundation
import LocalAuthentication
import Observation

/// Ce que l'iPhone permet pour déverrouiller l'app.
enum DeviceLockKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// Pas de biométrie enregistrée, mais un code : l'iPhone demande son code.
    case passcode
    /// Pas de code sur l'iPhone : impossible de protéger l'app.
    case unavailable
}

/// Résultat d'une demande de Face ID (ou du code de l'iPhone).
enum DeviceAuthenticationResult: Equatable, Sendable {
    case success
    /// Fenêtre fermée par la personne, par une autre app ou par le système.
    case cancelled
    /// Plus de code sur l'iPhone : la protection n'est plus possible.
    case unavailable
    case failed(String)
}

/// Face ID, Touch ID ou code de l'iPhone. `LocalDeviceAuthenticator` dans l'app, un faux dans les tests.
protocol DeviceAuthenticator: Sendable {
    func kind() -> DeviceLockKind
    func authenticate(reason: String) async -> DeviceAuthenticationResult
}

/// `LocalAuthentication`, règle `.deviceOwnerAuthentication` : Face ID (ou Touch ID), avec **repli sur le code de
/// l'iPhone**. Rien n'est gardé : ni secret, ni résultat. Face ID exige `NSFaceIDUsageDescription` dans l'Info.plist.
struct LocalDeviceAuthenticator: DeviceAuthenticator {
    func kind() -> DeviceLockKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        // `biometryType` n'est renseigné qu'après `canEvaluatePolicy`.
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcode
            }
        }
        return .passcode
    }

    func authenticate(reason: String) async -> DeviceAuthenticationResult {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .cancelled
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
            case .passcodeNotSet: return .unavailable
            default: return .failed("\(error.code.rawValue): \(error.localizedDescription)")
            }
        } catch {
            return .failed("\(error)")
        }
    }
}

/// Verrou de l'app (I2 « Face ID to open the app ») : **désactivé par défaut**. Activé, l'app se verrouille à
/// l'ouverture et à chaque **retour au premier plan** après être passée en arrière-plan, et Face ID (ou le code de
/// l'iPhone) la rouvre. Jamais sur un simple passage « inactif » : la feuille NFC d'iOS, la fenêtre Face ID elle-même et
/// le centre de contrôle rendent l'app inactive sans la quitter (une signature en cours n'est jamais recouverte).
/// Le verrou recouvre l'écran ; il n'interrompt rien de ce qui tourne dessous.
@Observable
final class AppLock {
    private let preferences: AppPreferences
    private let authenticator: DeviceAuthenticator

    /// L'écran de verrouillage recouvre l'app.
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    /// Face ID doit être proposé au prochain passage au premier plan (lancement, retour d'arrière-plan). Remis à faux
    /// dès qu'il est proposé : une fenêtre Face ID annulée ne revient pas en boucle (bouton « Unlock » à la place).
    private var promptsWhenActive: Bool
    /// Dernier échec technique (texte pour « Technical details »).
    private(set) var lastFailure: String?

    init(preferences: AppPreferences, authenticator: DeviceAuthenticator = LocalDeviceAuthenticator()) {
        self.preferences = preferences
        self.authenticator = authenticator
        isLocked = preferences.opensWithFaceID
        promptsWhenActive = preferences.opensWithFaceID
    }

    var isEnabled: Bool { preferences.opensWithFaceID }

    /// Ce que l'iPhone permet (libellé de la ligne des réglages, texte du bouton).
    var kind: DeviceLockKind { authenticator.kind() }

    /// Raison affichée par iOS pour Touch ID et le code (Face ID affiche `NSFaceIDUsageDescription`).
    static var reason: String { String(localized: "Unlock ChimpDAO") }

    // MARK: Cycle de vie

    /// L'app passe en arrière-plan : elle se verrouille (l'aperçu du sélecteur d'apps ne montre plus les soldes).
    func didEnterBackground() {
        guard preferences.opensWithFaceID else { return }
        isLocked = true
        promptsWhenActive = true
    }

    /// L'app est au premier plan : Face ID est proposé s'il vient d'un lancement ou d'un retour d'arrière-plan.
    func didBecomeActive() async {
        guard isLocked, promptsWhenActive else { return }
        promptsWhenActive = false
        await unlock()
    }

    /// Bouton « Unlock » de l'écran de verrouillage, ou premier plan.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        guard preferences.opensWithFaceID else {
            isLocked = false
            return
        }
        if authenticator.kind() == .unavailable {
            // Plus de code sur l'iPhone : impossible de vérifier qui ouvre l'app. Celui qui l'a retiré avait l'iPhone
            // déverrouillé ; l'app s'ouvre et le réglage se coupe (DESIGN_NOTES §12).
            preferences.opensWithFaceID = false
            isLocked = false
            return
        }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: Self.reason)
        isAuthenticating = false
        switch result {
        case .success:
            lastFailure = nil
            isLocked = false
        case .unavailable:
            preferences.opensWithFaceID = false
            isLocked = false
        case .cancelled:
            lastFailure = nil
        case .failed(let detail):
            lastFailure = detail
        }
    }

    // MARK: Réglage

    enum EnableOutcome: Equatable {
        case enabled
        /// L'iPhone n'a pas de code : « Set a passcode on your iPhone first. »
        case needsPasscode
        case cancelled
        case failed(String)
    }

    /// Interrupteur mis sur « oui » : Face ID doit réussir une fois (on ne s'enferme jamais dehors par erreur).
    func enable() async -> EnableOutcome {
        guard !preferences.opensWithFaceID else { return .enabled }
        guard authenticator.kind() != .unavailable else { return .needsPasscode }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: Self.reason)
        isAuthenticating = false
        switch result {
        case .success:
            preferences.opensWithFaceID = true
            return .enabled
        case .cancelled: return .cancelled
        case .unavailable: return .needsPasscode
        case .failed(let detail): return .failed(detail)
        }
    }

    /// Interrupteur mis sur « non » : l'app est déjà ouverte, pas besoin de Face ID.
    func disable() {
        preferences.opensWithFaceID = false
    }
}
