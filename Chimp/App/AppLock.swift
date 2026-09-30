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
    /// Face ID (ou Touch ID), avec repli sur le code de l'iPhone.
    func authenticate(reason: String) async -> DeviceAuthenticationResult
    /// **Directement** le code de l'iPhone, sans Face ID (« Use iPhone passcode »).
    func authenticateWithPasscode(reason: String) async -> DeviceAuthenticationResult
}

/// `LocalAuthentication`. Rien n'est gardé : ni secret, ni résultat (règle 1). Face ID exige `NSFaceIDUsageDescription`.
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

    /// Règle `.deviceOwnerAuthentication` : Face ID (ou Touch ID), puis le code de l'iPhone si Face ID échoue.
    func authenticate(reason: String) async -> DeviceAuthenticationResult {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .cancelled
        } catch {
            return Self.result(for: error)
        }
    }

    /// iOS n'a pas de règle « code seul » : `.deviceOwnerAuthentication` essaie toujours Face ID d'abord. Une simple
    /// évaluation d'un contrôle d'accès limité au code de l'iPhone (`.devicePasscode`) ouvre directement la saisie du code.
    /// Rien n'est écrit dans le trousseau : aucun élément n'est créé ni lu, seule la vérification a lieu.
    func authenticateWithPasscode(reason: String) async -> DeviceAuthenticationResult {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, &error
        ) else {
            return .failed(error.map { "\($0.takeRetainedValue())" } ?? "SecAccessControlCreateWithFlags")
        }
        let context = LAContext()
        do {
            return try await context.evaluateAccessControl(access, operation: .useItem, localizedReason: reason) ? .success : .cancelled
        } catch {
            return Self.result(for: error)
        }
    }

    private static func result(for error: Error) -> DeviceAuthenticationResult {
        guard let error = error as? LAError else { return .failed("\(error)") }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
        case .passcodeNotSet: return .unavailable
        default: return .failed("\(error.code.rawValue): \(error.localizedDescription)")
        }
    }
}

/// Verrou « Face ID to open the app » (I2) : il protège **un compte**, pas le téléphone. Le réglage est enregistré avec le
/// compte (`SavedAccount.opensWithFaceID`, désactivé par défaut) et part avec lui à la déconnexion.
/// - Aucun verrou sans compte ouvert (A1, onboarding, après la déconnexion du dernier compte).
/// - Compte affiché avec le réglage : verrouillé au lancement et à chaque **retour d'arrière-plan** ; en arrivant sur ce
///   compte (Switch account, reconnexion, déconnexion d'un autre compte), Face ID est demandé tout de suite.
/// - Jamais sur un simple passage « inactif » : la feuille NFC d'iOS, la fenêtre Face ID elle-même et le centre de
///   contrôle rendent l'app inactive sans la quitter ; une signature en cours n'est jamais recouverte.
/// - Toujours deux moyens d'ouvrir : Face ID (avec repli sur le code) et « Use iPhone passcode » (le code, directement).
///   Pas de code propre à l'app.
/// Le verrou recouvre l'écran ; il n'interrompt rien de ce qui tourne dessous.
@Observable
final class AppLock {
    private let session: AppSession
    private let authenticator: DeviceAuthenticator

    /// L'écran de verrouillage recouvre l'app.
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    /// Face ID doit être proposé au prochain passage au premier plan (lancement, retour d'arrière-plan). Remis à faux
    /// dès qu'il est proposé : une fenêtre Face ID annulée ne revient pas en boucle (boutons à la place).
    private var promptsWhenActive: Bool
    /// Compte pour lequel l'état du verrou a été décidé (détecte un changement de compte).
    private var lockedAccount: String?
    /// Dernier échec technique (texte pour « Technical details »).
    private(set) var lastFailure: String?

    init(session: AppSession, authenticator: DeviceAuthenticator = LocalDeviceAuthenticator()) {
        self.session = session
        self.authenticator = authenticator
        let enabled = Self.isEnabled(in: session)
        isLocked = enabled
        promptsWhenActive = enabled
        lockedAccount = session.wallet.account?.address
    }

    /// Le compte affiché a activé Face ID. Faux sans compte ouvert.
    var isEnabled: Bool { Self.isEnabled(in: session) }

    private static func isEnabled(in session: AppSession) -> Bool {
        session.wallet.account?.opensWithFaceID == true
    }

    /// Ce que l'iPhone permet (libellé de la ligne des réglages, texte des boutons).
    var kind: DeviceLockKind { authenticator.kind() }

    /// Raison affichée par iOS pour Touch ID et le code (Face ID affiche `NSFaceIDUsageDescription`).
    static var reason: String { String(localized: "Unlock ChimpDAO") }

    // MARK: Cycle de vie

    /// L'app passe en arrière-plan : le compte se verrouille (l'aperçu du sélecteur d'apps ne montre plus les soldes).
    func didEnterBackground() {
        guard isEnabled else { return }
        isLocked = true
        promptsWhenActive = true
    }

    /// L'app est au premier plan : Face ID est proposé s'il vient d'un lancement ou d'un retour d'arrière-plan.
    func didBecomeActive() async {
        guard isLocked, promptsWhenActive else { return }
        promptsWhenActive = false
        await unlock()
    }

    /// Le compte affiché a changé (Switch account, « + Add an account », déconnexion, onboarding, « Erase everything ») :
    /// verrouillé, et Face ID demandé tout de suite, si le compte d'arrivée l'a activé ; sinon ouvert.
    func accountDidChange() async {
        let account = session.wallet.account?.address
        guard account != lockedAccount else { return }
        lockedAccount = account
        lastFailure = nil
        guard isEnabled else {
            isLocked = false
            promptsWhenActive = false
            return
        }
        isLocked = true
        promptsWhenActive = false
        await unlock()
    }

    /// « Unlock with Face ID » : Face ID, avec repli sur le code de l'iPhone.
    func unlock() async {
        await open { await self.authenticator.authenticate(reason: Self.reason) }
    }

    /// « Use iPhone passcode » : le code de l'iPhone, sans passer par Face ID.
    func unlockWithPasscode() async {
        await open { await self.authenticator.authenticateWithPasscode(reason: Self.reason) }
    }

    private func open(_ authenticate: () async -> DeviceAuthenticationResult) async {
        guard isLocked, !isAuthenticating else { return }
        guard isEnabled else {
            isLocked = false
            return
        }
        if authenticator.kind() == .unavailable {
            // Plus de code sur l'iPhone : impossible de vérifier qui ouvre l'app. Celui qui l'a retiré avait l'iPhone
            // déverrouillé ; le compte s'ouvre et son réglage se coupe (DESIGN_NOTES §12).
            try? session.setOpensWithFaceID(false)
            isLocked = false
            return
        }
        isAuthenticating = true
        let result = await authenticate()
        isAuthenticating = false
        switch result {
        case .success:
            lastFailure = nil
            isLocked = false
        case .unavailable:
            try? session.setOpensWithFaceID(false)
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

    /// Interrupteur mis sur « oui » pour le compte affiché : Face ID (ou le code) doit réussir une fois.
    func enable() async -> EnableOutcome {
        guard session.wallet.account != nil else { return .failed("No account is open on this phone.") }
        guard !isEnabled else { return .enabled }
        guard authenticator.kind() != .unavailable else { return .needsPasscode }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: Self.reason)
        isAuthenticating = false
        switch result {
        case .success:
            do {
                try session.setOpensWithFaceID(true)
                return .enabled
            } catch {
                return .failed(OnboardingModel.details(error))
            }
        case .cancelled: return .cancelled
        case .unavailable: return .needsPasscode
        case .failed(let detail): return .failed(detail)
        }
    }

    /// Interrupteur mis sur « non » : l'app est déjà ouverte, pas besoin de Face ID. Renvoie le détail technique si le
    /// téléphone n'a pas pu l'écrire.
    @discardableResult
    func disable() -> String? {
        do {
            try session.setOpensWithFaceID(false)
            return nil
        } catch {
            return OnboardingModel.details(error)
        }
    }
}
